import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stocklens/data/local/app_database.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/sale_order.dart';
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

  Product product({
    String id = 'product-1',
    String barcode = '4801234567890',
    String name = 'Test Product',
    double price = 25,
    int quantity = 10,
  }) {
    final now = DateTime.utc(2020);
    return Product(
      id: id,
      barcode: barcode,
      name: name,
      price: price,
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

  test('checkout atomically saves snapshots and deducts inventory', () async {
    await repository.add(product());
    await repository.add(
      product(
        id: 'product-2',
        barcode: 'BREAD001',
        name: 'Bread',
        price: 12.34,
        quantity: 5,
      ),
    );

    final order = await repository.completeSale(const [
      SaleRequestItem(productId: 'product-1', quantity: 2),
      SaleRequestItem(productId: 'product-2', quantity: 3),
    ]);

    expect(order.orderNumber, startsWith('ORD-'));
    expect(order.totalItems, 2);
    expect(order.totalQuantity, 5);
    expect(order.totalAmountCents, 8702);
    expect((await repository.getById('product-1'))!.quantity, 8);
    expect((await repository.getById('product-2'))!.quantity, 2);

    final orders = await repository.getOrders();
    expect(orders, hasLength(1));
    expect(orders.single.items, hasLength(2));
    final bread = orders.single.items.singleWhere(
      (item) => item.productId == 'product-2',
    );
    expect(bread.productName, 'Bread');
    expect(bread.sku, 'BREAD001');
    expect(bread.unitPriceCents, 1234);
    expect(bread.subtotalCents, 3702);

    final stockHistory = await repository.getStockTransactions('product-2');
    expect(stockHistory.first.reason, 'POS sale');
    expect(stockHistory.first.note, order.orderNumber);
    expect(stockHistory.first.delta, -3);

    final nextOrder = await repository.completeSale(const [
      SaleRequestItem(productId: 'product-1', quantity: 1),
    ]);
    expect(order.orderNumber, endsWith('-0001'));
    expect(nextOrder.orderNumber, endsWith('-0002'));
    expect((await repository.getOrders()).first.id, nextOrder.id);
  });

  test('failed checkout rolls back the complete sale', () async {
    await repository.add(product(quantity: 3));

    await expectLater(
      repository.completeSale(const [
        SaleRequestItem(productId: 'product-1', quantity: 2),
        SaleRequestItem(productId: 'missing', quantity: 1),
      ]),
      throwsA(isA<ProductMissingForSaleException>()),
    );
    expect((await repository.getById('product-1'))!.quantity, 3);
    expect(await repository.getOrders(), isEmpty);

    await expectLater(
      repository.completeSale(const [
        SaleRequestItem(productId: 'product-1', quantity: 4),
      ]),
      throwsA(isA<ProductUnavailableException>()),
    );
    expect((await repository.getById('product-1'))!.quantity, 3);
    expect(await repository.getOrders(), isEmpty);
  });

  test('sales history retains snapshots after product changes', () async {
    final original = product(name: 'Original Name', price: 19.99);
    await repository.add(original);
    final order = await repository.completeSale(const [
      SaleRequestItem(productId: 'product-1', quantity: 1),
    ]);

    final remaining = (await repository.getById('product-1'))!;
    await repository.update(remaining.copyWith(name: 'New Name', price: 29.99));
    await repository.setArchived('product-1', archived: true);
    await repository.deletePermanently('product-1');

    final stored = (await repository.getOrders()).single;
    expect(stored.id, order.id);
    expect(stored.items.single.productName, 'Original Name');
    expect(stored.items.single.unitPriceCents, 1999);
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
    final sale = await repository.completeSale(const [
      SaleRequestItem(productId: 'product-1', quantity: 2),
    ]);
    final backup = await repository.createBackup();

    await repository.setArchived('product-1', archived: true);
    await repository.deletePermanently('product-1');
    expect(await repository.getById('product-1'), isNull);

    await repository.restoreBackup(backup);
    expect((await repository.getById('product-1'))!.quantity, 13);
    expect(await repository.getStockTransactions('product-1'), hasLength(3));
    final restoredOrder = (await repository.getOrders()).single;
    expect(restoredOrder.orderNumber, sale.orderNumber);
    expect(restoredOrder.items.single.productName, 'Test Product');
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
    final salesTables = await (await database.database).rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name IN ('orders', 'order_items')",
    );
    expect(
      salesTables.map((table) => table['name']),
      containsAll(['orders', 'order_items']),
    );
  });
}
