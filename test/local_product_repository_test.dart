import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stocklens/data/local/app_database.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/repositories/local_product_repository.dart';
import 'package:stocklens/repositories/product_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temporaryDirectory;
  late AppDatabase database;
  late LocalProductRepository repository;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'stocklens-test-',
    );
    database = AppDatabase.forTesting(
      '${temporaryDirectory.path}${Platform.pathSeparator}stocklens.db',
    );
    repository = LocalProductRepository(database);
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Product product({String id = 'product-1', int quantity = 10}) {
    final now = DateTime.utc(2026, 8, 12);
    return Product(
      id: id,
      barcode: '4801234567890',
      name: 'Test Product',
      price: 25,
      category: 'Test',
      description: 'Repository test product',
      quantity: quantity,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('stock adjustment updates quantity and history atomically', () async {
    await repository.add(product());

    final updated = await repository.adjustStock(
      productId: 'product-1',
      delta: -3,
      reason: 'Sale',
      note: 'Receipt 42',
    );

    expect(updated.quantity, 7);
    final history = await repository.getStockTransactions('product-1');
    expect(history, hasLength(2));
    expect(history.first.reason, 'Sale');
    expect(history.first.note, 'Receipt 42');
    expect(history.first.previousQuantity, 10);
    expect(history.first.resultingQuantity, 7);

    await expectLater(
      repository.adjustStock(
        productId: 'product-1',
        delta: -8,
        reason: 'Sale',
        note: '',
      ),
      throwsA(isA<StockCannotBeNegativeException>()),
    );
    expect((await repository.getById('product-1'))!.quantity, 7);
    expect(await repository.getStockTransactions('product-1'), hasLength(2));
  });

  test('archive hides a product and restore returns it to inventory', () async {
    await repository.add(product());

    final archived = await repository.setArchived('product-1', archived: true);
    expect(archived.archivedAt, isNotNull);
    expect(await repository.getProducts(), isEmpty);
    expect(await repository.getByBarcode('4801234567890'), isNull);
    expect(await repository.getArchivedProducts(), hasLength(1));

    final restored = await repository.setArchived('product-1', archived: false);
    expect(restored.archivedAt, isNull);
    expect(await repository.getProducts(), hasLength(1));
  });

  test(
    'permanent deletion is limited to archived products and cascades history',
    () async {
      await repository.add(product());
      await expectLater(
        repository.deletePermanently('product-1'),
        throwsStateError,
      );

      await repository.setArchived('product-1', archived: true);
      await repository.deletePermanently('product-1');

      expect(await repository.getById('product-1'), isNull);
      expect(await repository.getStockTransactions('product-1'), isEmpty);
    },
  );

  test(
    'sample inventory is not recreated after users delete everything',
    () async {
      await repository.initialize();
      final samples = await repository.getProducts();
      expect(samples, hasLength(4));
      for (final sample in samples) {
        await repository.setArchived(sample.id, archived: true);
        await repository.deletePermanently(sample.id);
      }

      await repository.initialize();
      expect(await repository.getProducts(), isEmpty);
    },
  );

  test('backup restore replaces products and preserves history', () async {
    await repository.add(product());
    await repository.adjustStock(
      productId: 'product-1',
      delta: 5,
      reason: 'Restock',
      note: '',
    );
    final backup = await repository.createBackup();

    await repository.setArchived('product-1', archived: true);
    await repository.deletePermanently('product-1');
    expect(await repository.getById('product-1'), isNull);

    await repository.restoreBackup(backup);
    expect((await repository.getById('product-1'))!.quantity, 15);
    expect(await repository.getStockTransactions('product-1'), hasLength(2));
  });

  test('version 1 database migrates without losing products', () async {
    await database.close();
    final path =
        '${temporaryDirectory.path}${Platform.pathSeparator}stocklens.db';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            barcode TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            price REAL NOT NULL,
            category TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            quantity INTEGER NOT NULL,
            image_path TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        '''),
      ),
    );
    final row = product().toJson()..remove('archived_at');
    await legacy.insert('products', row);
    await legacy.close();

    database = AppDatabase.forTesting(path);
    repository = LocalProductRepository(database);
    final migrated = await repository.getById('product-1');
    final columns = await (await database.database).rawQuery(
      'PRAGMA table_info(products)',
    );

    expect(migrated?.name, 'Test Product');
    expect(columns.map((column) => column['name']), contains('archived_at'));
    expect(await repository.getStockTransactions('product-1'), isEmpty);
  });
}
