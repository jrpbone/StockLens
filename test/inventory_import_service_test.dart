import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stocklens/data/local/app_database.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/repositories/local_inventory_import_repository.dart';
import 'package:stocklens/repositories/local_product_repository.dart';
import 'package:stocklens/services/inventory_import_service.dart';
import 'package:stocklens/services/low_stock_notification_service.dart';

class _RecordingGateway implements LowStockNotificationGateway {
  final shown = <String>[];

  @override
  Future<void> showLowStock(Product product) async => shown.add(product.id);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temporaryDirectory;
  late AppDatabase database;
  late LocalProductRepository products;
  late _RecordingGateway gateway;
  late InventoryImportService service;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'stocklens-inventory-import-service-',
    );
    database = AppDatabase.forTesting(
      '${temporaryDirectory.path}${Platform.pathSeparator}stocklens.db',
    );
    products = LocalProductRepository(database);
    gateway = _RecordingGateway();
    service = InventoryImportService(
      LocalInventoryImportRepository(database),
      lowStockNotifications: LowStockNotificationService(
        products,
        gateway: gateway,
      ),
      nowProvider: () => DateTime.utc(2026, 8, 20, 9),
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<Product> addProduct({
    required String id,
    required String barcode,
    String name = 'Existing',
    int quantity = 5,
    int threshold = 2,
    DateTime? archivedAt,
  }) async {
    final product = Product(
      id: id,
      barcode: barcode,
      name: name,
      sellingPrice: 10,
      costPrice: 4,
      lowStockThreshold: threshold,
      category: 'Original',
      description: 'Keep me',
      quantity: quantity,
      imagePath: 'managed/image.jpg',
      archivedAt: archivedAt,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
    );
    await products.add(product);
    return product;
  }

  test(
    'classifies new, detail-update, stock-change, and unchanged rows',
    () async {
      await addProduct(id: 'existing', barcode: '111');
      await addProduct(id: 'unchanged', barcode: '222', quantity: 7);

      final preview = await service.preview(
        'barcode,name,selling_price,cost_price,category,quantity,'
        'low_stock_threshold,description\n'
        '333,New item,20,8,,3,,\n'
        '111,Renamed,,,Updated,0,,\n'
        '222,,,,,,,',
      );

      expect(preview.newProducts, hasLength(1));
      expect(preview.productUpdates, hasLength(1));
      expect(preview.stockChanges, hasLength(1));
      expect(preview.unchangedRows, hasLength(1));
      expect(preview.blockingErrors, isEmpty);

      final created = preview.newProducts.single.after;
      expect(created.name, 'New item');
      expect(created.quantity, 3);
      expect(created.lowStockThreshold, 5);
      expect(created.category, 'Uncategorized');
      expect(created.description, '');

      final updated = preview.productUpdates.single.after;
      expect(updated.name, 'Renamed');
      expect(updated.sellingPrice, 10);
      expect(updated.costPrice, 4);
      expect(updated.category, 'Updated');
      expect(updated.description, 'Keep me');
      expect(preview.stockChanges.single.beforeQuantity, 5);
      expect(preview.stockChanges.single.afterQuantity, 0);
    },
  );

  test(
    'returns blocking errors for archived conflicts and unnamed new rows',
    () async {
      final archived = await addProduct(id: 'archived', barcode: '444');
      await products.setArchived(archived.id, archived: true);

      final preview = await service.preview(
        'barcode,name,quantity\n444,Archived edit,1\n555,,2',
      );

      expect(preview.canApply, isFalse);
      expect(preview.rows, isEmpty);
      expect(
        preview.blockingErrors.map((error) => error.toString()),
        containsAll([
          'Row 2: Barcode 444 belongs to an archived product.',
          'Row 3: Name is required for a new product.',
        ]),
      );
    },
  );

  test('converts parser failures into a blocking preview', () async {
    final preview = await service.preview(
      'barcode,name,quantity\n123,A,-1\n123,B,2',
    );

    expect(preview.canApply, isFalse);
    expect(preview.rows, isEmpty);
    expect(preview.blockingErrors, hasLength(2));
    expect(
      preview.blockingErrors.map((error) => error.rowNumber),
      containsAll([2, 3]),
    );
  });

  test(
    'applies the accepted preview then evaluates low-stock crossings',
    () async {
      await addProduct(
        id: 'existing',
        barcode: '111',
        quantity: 6,
        threshold: 5,
      );
      final preview = await service.preview(
        'barcode,name,quantity\n111,Existing,5',
      );

      await service.apply(preview);

      final stored = await products.getById('existing');
      expect(stored!.quantity, 5);
      expect(stored.lowStockNotified, isTrue);
      expect(gateway.shown, ['existing']);
    },
  );

  test('refuses to apply a preview containing blocking errors', () async {
    final preview = await service.preview('barcode,name\nnew,');

    await expectLater(service.apply(preview), throwsStateError);
    expect(await products.getByBarcode('new'), isNull);
  });
}
