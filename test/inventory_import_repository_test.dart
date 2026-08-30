import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stocklens/data/local/app_database.dart';
import 'package:stocklens/models/inventory_import.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/stock_transaction.dart';
import 'package:stocklens/repositories/local_inventory_import_repository.dart';
import 'package:stocklens/repositories/local_product_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temporaryDirectory;
  late AppDatabase database;
  late LocalProductRepository products;
  late LocalInventoryImportRepository repository;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'stocklens-inventory-import-repository-',
    );
    database = AppDatabase.forTesting(
      '${temporaryDirectory.path}${Platform.pathSeparator}stocklens.db',
    );
    products = LocalProductRepository(database);
    repository = LocalInventoryImportRepository(database);
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Product product({
    required String id,
    required String barcode,
    required int quantity,
    String name = 'Existing',
    double sellingPrice = 10,
    double costPrice = 4,
  }) => Product(
    id: id,
    barcode: barcode,
    name: name,
    sellingPrice: sellingPrice,
    costPrice: costPrice,
    lowStockThreshold: 5,
    category: 'Original',
    description: 'Existing description',
    quantity: quantity,
    imagePath: 'managed/image.jpg',
    createdAt: DateTime.utc(2026, 8, 1),
    updatedAt: DateTime.utc(2026, 8, 1),
  );

  InventoryImportRowPreview existingRow(
    Product before, {
    String? name,
    double? sellingPrice,
    double? costPrice,
    int? quantity,
  }) {
    final candidate = InventoryImportCandidate(
      rowNumber: 2,
      barcode: before.barcode,
      name: name,
      sellingPrice: sellingPrice,
      costPrice: costPrice,
      quantity: quantity,
    );
    final after = before.copyWith(
      name: name,
      sellingPrice: sellingPrice,
      costPrice: costPrice,
      quantity: quantity,
    );
    return InventoryImportRowPreview(
      candidate: candidate,
      before: before,
      after: after,
      productDetailsChanged:
          name != null || sellingPrice != null || costPrice != null,
      stockChanged: quantity != null && quantity != before.quantity,
    );
  }

  Future<List<StockTransaction>> importTransactions(String importId) async {
    final rows = await (await database.database).query(
      'stock_transactions',
      where: 'source = ? AND source_id = ?',
      whereArgs: ['csv_import', importId],
      orderBy: 'product_id ASC',
    );
    return rows.map(StockTransaction.fromJson).toList();
  }

  test(
    'atomically applies explicit fields and price-snapshotted stock changes',
    () async {
      final existing = product(id: 'existing', barcode: '111', quantity: 5);
      await products.add(existing);
      final existingPreview = existingRow(
        existing,
        name: 'Renamed',
        sellingPrice: 12,
        costPrice: 5,
        quantity: 0,
      );
      final created = product(
        id: 'created',
        barcode: '222',
        name: 'Created',
        quantity: 3,
        sellingPrice: 8,
        costPrice: 2,
      ).copyWith(imagePath: null);
      final newPreview = InventoryImportRowPreview(
        candidate: const InventoryImportCandidate(
          rowNumber: 3,
          barcode: '222',
          name: 'Created',
          sellingPrice: 8,
          costPrice: 2,
          quantity: 3,
          lowStockThreshold: 5,
          category: 'Original',
          description: 'Existing description',
        ),
        before: null,
        after: created,
        productDetailsChanged: true,
        stockChanged: true,
      );
      final preview = InventoryImportPreview(
        importId: 'import-1',
        rows: [existingPreview, newPreview],
        blockingErrors: const [],
      );

      final changes = await repository.apply(
        preview,
        appliedAt: DateTime.utc(2026, 8, 20),
      );

      expect(changes, hasLength(2));
      final storedExisting = await products.getById('existing');
      expect(storedExisting!.name, 'Renamed');
      expect(storedExisting.sellingPrice, 12);
      expect(storedExisting.costPrice, 5);
      expect(storedExisting.quantity, 0);
      expect(storedExisting.category, 'Original');
      expect(storedExisting.description, 'Existing description');
      expect(storedExisting.imagePath, 'managed/image.jpg');
      expect((await products.getById('created'))!.quantity, 3);

      final transactions = await importTransactions('import-1');
      expect(transactions, hasLength(2));
      final transactionsByProduct = {
        for (final transaction in transactions)
          transaction.productId: transaction,
      };
      expect(transactionsByProduct['existing']!.delta, -5);
      expect(transactionsByProduct['created']!.delta, 3);
      expect(
        transactions.every(
          (transaction) =>
              transaction.reason == 'Inventory Correction' &&
              transaction.source == 'csv_import' &&
              transaction.sourceId == 'import-1',
        ),
        isTrue,
      );
      expect(transactionsByProduct['existing']!.sellingPriceSnapshot, 12);
      expect(transactionsByProduct['existing']!.costPriceSnapshot, 5);
    },
  );

  test('rejects a stale preview without applying any import row', () async {
    final existing = product(id: 'existing', barcode: '111', quantity: 5);
    await products.add(existing);
    final created = product(id: 'created', barcode: '222', quantity: 2);
    final preview = InventoryImportPreview(
      importId: 'stale-import',
      rows: [
        existingRow(existing, quantity: 0),
        InventoryImportRowPreview(
          candidate: const InventoryImportCandidate(
            rowNumber: 3,
            barcode: '222',
            name: 'Created',
            quantity: 2,
          ),
          before: null,
          after: created,
          productDetailsChanged: true,
          stockChanged: true,
        ),
      ],
      blockingErrors: const [],
    );
    await products.adjustStock(
      productId: existing.id,
      delta: 1,
      reason: 'Restock',
      note: '',
    );

    await expectLater(
      repository.apply(preview, appliedAt: DateTime.utc(2026, 8, 20)),
      throwsA(isA<StaleInventoryImportException>()),
    );

    expect((await products.getById(existing.id))!.quantity, 6);
    expect(await products.getByBarcode('222'), isNull);
    expect(await importTransactions('stale-import'), isEmpty);
  });

  test('rolls back earlier rows when a later database write fails', () async {
    final first = product(
      id: 'duplicate-id',
      barcode: '111',
      name: 'First',
      quantity: 1,
    ).copyWith(imagePath: null);
    final second = product(
      id: 'duplicate-id',
      barcode: '222',
      name: 'Second',
      quantity: 1,
    ).copyWith(imagePath: null);
    final preview = InventoryImportPreview(
      importId: 'rollback-import',
      rows: [
        for (final (rowNumber, proposed) in [(2, first), (3, second)])
          InventoryImportRowPreview(
            candidate: InventoryImportCandidate(
              rowNumber: rowNumber,
              barcode: proposed.barcode,
              name: proposed.name,
              sellingPrice: proposed.sellingPrice,
              costPrice: proposed.costPrice,
              quantity: proposed.quantity,
              lowStockThreshold: proposed.lowStockThreshold,
              category: proposed.category,
              description: proposed.description,
            ),
            before: null,
            after: proposed,
            productDetailsChanged: true,
            stockChanged: true,
          ),
      ],
      blockingErrors: const [],
    );

    await expectLater(
      repository.apply(preview, appliedAt: DateTime.utc(2026, 8, 20)),
      throwsA(anything),
    );

    expect(await products.getByBarcode('111'), isNull);
    expect(await products.getByBarcode('222'), isNull);
    expect(await importTransactions('rollback-import'), isEmpty);
  });
}
