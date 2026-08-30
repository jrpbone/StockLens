import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stocklens/data/local/app_database.dart';
import 'package:stocklens/models/inventory_report.dart';
import 'package:stocklens/models/pos_cart_item.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/repositories/local_inventory_import_repository.dart';
import 'package:stocklens/repositories/local_inventory_report_repository.dart';
import 'package:stocklens/repositories/local_product_repository.dart';
import 'package:stocklens/repositories/local_stocktake_repository.dart';
import 'package:stocklens/services/inventory_import_service.dart';
import 'package:stocklens/services/inventory_report_service.dart';
import 'package:stocklens/services/low_stock_notification_service.dart';
import 'package:stocklens/services/product_service.dart';
import 'package:stocklens/services/stocktake_service.dart';

class _NoopGateway implements LowStockNotificationGateway {
  @override
  Future<void> showLowStock(Product product) async {}
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'backup restore preserves stocktake, CSV audit, and report history',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'stocklens-offline-integration-',
      );
      final database = AppDatabase.forTesting(
        '${directory.path}${Platform.pathSeparator}stocklens.db',
      );
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      final products = LocalProductRepository(database);
      final notifications = LowStockNotificationService(
        products,
        gateway: _NoopGateway(),
      );
      final productService = ProductService(
        products,
        lowStockNotifications: notifications,
      );
      final stocktakeService = StocktakeService(
        LocalStocktakeRepository(database),
        products,
        lowStockNotifications: notifications,
      );
      final importService = InventoryImportService(
        LocalInventoryImportRepository(database),
        lowStockNotifications: notifications,
      );
      final reportService = InventoryReportService(
        LocalInventoryReportRepository(database),
      );

      final original = await productService.add(
        barcode: '111',
        name: 'Original product',
        sellingPrice: 20,
        costPrice: 8,
        category: 'Test',
        quantity: 10,
        description: '',
      );
      await stocktakeService.create(
        name: 'Open count',
        productIds: [original.id],
        scopeDescription: 'All products',
      );
      final order = await productService.completeSale([
        PosCartItem.fromProduct(original),
      ]);
      await productService.adjustStock(original, -2, reason: 'Sale', note: '');
      final preview = await importService.preview(
        'barcode,name,selling_price,cost_price,quantity\n'
        '222,Imported product,12,5,3',
      );
      await importService.apply(preview);

      final backup = await productService.createBackup();
      expect(backup['orders'], hasLength(1));
      expect(backup['order_items'], hasLength(1));
      expect(backup['stocktake_sessions'], hasLength(1));
      expect(backup['stocktake_items'], hasLength(1));
      await productService.restoreBackup(backup);

      expect(await stocktakeService.sessions(), hasLength(1));
      expect((await stocktakeService.sessions()).single.name, 'Open count');
      final restoredOrders = await productService.orders();
      expect(restoredOrders, hasLength(1));
      expect(restoredOrders.single.id, order.id);
      expect(
        restoredOrders.single.items.single.productName,
        'Original product',
      );
      expect((await productService.byBarcode('111'))?.quantity, 7);
      final imported = await productService.byBarcode('222');
      expect(imported, isNotNull);
      expect(imported!.quantity, 3);
      expect(
        (await productService.stockTransactions(imported.id))
            .singleWhere((transaction) => transaction.source == 'csv_import')
            .sourceId,
        preview.importId,
      );
      final report = await reportService.load(const ReportRange.allTime());
      expect(report.movement.unitsSold, 2);
      expect(report.movement.recordedRevenue, 40);
      expect(report.movement.recordedCost, 16);
    },
  );
}
