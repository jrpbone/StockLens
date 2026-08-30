import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stocklens/data/local/app_database.dart';
import 'package:stocklens/models/inventory_report.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/stock_transaction.dart';
import 'package:stocklens/repositories/local_inventory_report_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temporaryDirectory;
  late AppDatabase database;
  late LocalInventoryReportRepository repository;

  Future<void> insertProduct({
    required String id,
    required String name,
    required String category,
    required int quantity,
    required double sellingPrice,
    required double costPrice,
    required int lowStockThreshold,
    bool archived = false,
  }) async {
    final now = DateTime(2026, 7, 1);
    await (await database.database).insert(
      'products',
      Product(
        id: id,
        barcode: 'barcode-$id',
        name: name,
        sellingPrice: sellingPrice,
        costPrice: costPrice,
        lowStockThreshold: lowStockThreshold,
        category: category,
        description: '',
        quantity: quantity,
        archivedAt: archived ? DateTime(2026, 8, 2) : null,
        createdAt: now,
        updatedAt: now,
      ).toJson(),
    );
  }

  Future<void> insertTransaction({
    required String id,
    required String productId,
    required int delta,
    required String reason,
    required DateTime occurredAt,
    double? sellingPrice,
    double? costPrice,
  }) async {
    final previous = delta < 0 ? 20 : 0;
    await (await database.database).insert(
      'stock_transactions',
      StockTransaction(
        id: id,
        productId: productId,
        delta: delta,
        reason: reason,
        note: '',
        previousQuantity: previous,
        resultingQuantity: previous + delta,
        occurredAt: occurredAt,
        sellingPriceSnapshot: sellingPrice,
        costPriceSnapshot: costPrice,
      ).toJson(),
    );
  }

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'stocklens-inventory-report-repository-',
    );
    database = AppDatabase.forTesting(
      '${temporaryDirectory.path}${Platform.pathSeparator}stocklens.db',
    );
    repository = LocalInventoryReportRepository(database);

    await insertProduct(
      id: 'cola',
      name: 'Cola',
      category: 'Beverages',
      quantity: 5,
      sellingPrice: 20,
      costPrice: 10,
      lowStockThreshold: 5,
    );
    await insertProduct(
      id: 'rice',
      name: 'Rice',
      category: 'Food',
      quantity: 0,
      sellingPrice: 8,
      costPrice: 5,
      lowStockThreshold: 2,
    );
    await insertProduct(
      id: 'soap',
      name: 'Soap',
      category: 'Personal Care',
      quantity: 4,
      sellingPrice: 12.5,
      costPrice: 7.5,
      lowStockThreshold: 1,
    );
    await insertProduct(
      id: 'archived',
      name: 'Archived Juice',
      category: 'Beverages',
      quantity: 2,
      sellingPrice: 200,
      costPrice: 100,
      lowStockThreshold: 5,
      archived: true,
    );

    await insertTransaction(
      id: 'sale-at-start',
      productId: 'cola',
      delta: -3,
      reason: 'Sale',
      occurredAt: DateTime(2026, 8, 1),
      sellingPrice: 20,
      costPrice: 12,
    );
    await insertTransaction(
      id: 'legacy-sale',
      productId: 'cola',
      delta: -2,
      reason: 'Sale',
      occurredAt: DateTime(2026, 8, 2, 12),
      sellingPrice: 20,
    );
    await insertTransaction(
      id: 'damage',
      productId: 'rice',
      delta: -2,
      reason: 'Damaged Item',
      occurredAt: DateTime(2026, 8, 2, 13),
    );
    await insertTransaction(
      id: 'archived-expiry',
      productId: 'archived',
      delta: -1,
      reason: 'Expired Item',
      occurredAt: DateTime(2026, 8, 3, 14),
    );
    await insertTransaction(
      id: 'restock',
      productId: 'rice',
      delta: 7,
      reason: 'Restock',
      occurredAt: DateTime(2026, 8, 3, 15),
    );
    await insertTransaction(
      id: 'before-start',
      productId: 'cola',
      delta: -4,
      reason: 'Sale',
      occurredAt: DateTime(2026, 7, 31, 23, 59, 59),
      sellingPrice: 20,
      costPrice: 10,
    );
    await insertTransaction(
      id: 'at-end-exclusive',
      productId: 'cola',
      delta: -5,
      reason: 'Sale',
      occurredAt: DateTime(2026, 8, 4),
      sellingPrice: 20,
      costPrice: 10,
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'current valuation and categories include active products only',
    () async {
      final valuation = await repository.getValuation();
      final categories = await repository.getCategoryValuations();

      expect(valuation.totalUnits, 9);
      expect(valuation.costValue, 80);
      expect(valuation.retailValue, 150);
      expect(valuation.potentialMargin, 70);
      expect(valuation.lowStockCount, 2);
      expect(valuation.outOfStockCount, 1);
      expect(categories.map((row) => row.category), [
        'Beverages',
        'Personal Care',
        'Food',
      ]);
      expect(categories.first.totalUnits, 5);
      expect(categories.first.costValue, 50);
      expect(categories.first.retailValue, 100);
    },
  );

  test(
    'range aggregates use half-open boundaries and archived history',
    () async {
      final range = ReportRange.custom(
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 3),
      );

      final movement = await repository.getMovementSummary(range);
      final fastMovers = await repository.getFastMovers(range);
      final inactive = await repository.getInactiveProducts(range);

      expect(movement.unitsSold, 5);
      expect(movement.recordedRevenue, 60);
      expect(movement.recordedCost, 36);
      expect(movement.estimatedGrossProfit, 24);
      expect(movement.legacySaleUnits, 2);
      expect(movement.damagedUnits, 2);
      expect(movement.expiredUnits, 1);
      expect(movement.netMovement, -1);
      expect(fastMovers, hasLength(1));
      expect(fastMovers.single.productId, 'cola');
      expect(fastMovers.single.unitsSold, 5);
      expect(inactive.map((row) => row.productId), ['soap']);
      expect(inactive.single.unitsOnHand, 4);
    },
  );

  test('all-time omits boundaries while retaining legacy disclosure', () async {
    const range = ReportRange.allTime();

    final movement = await repository.getMovementSummary(range);
    final inactive = await repository.getInactiveProducts(range);

    expect(movement.unitsSold, 14);
    expect(movement.recordedRevenue, 240);
    expect(movement.recordedCost, 126);
    expect(movement.legacySaleUnits, 2);
    expect(inactive.map((row) => row.productId), ['soap']);
  });
}
