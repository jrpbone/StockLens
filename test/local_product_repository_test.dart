import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqflite_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stocklens/data/local/app_database.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/sale_order.dart';
import 'package:stocklens/repositories/local_product_repository.dart';
import 'package:stocklens/repositories/product_repository.dart';

void main() {
  sqfliteFfiInit();
  final databaseEvents = <SqfliteLoggerEvent>[];
  // ignore: experimental_member_use
  databaseFactory = SqfliteDatabaseFactoryLogger(
    databaseFactoryFfi,
    options: SqfliteLoggerOptions(log: databaseEvents.add),
  );

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
    double? sellingPrice,
    double costPrice = 12,
  }) {
    final now = DateTime.utc(2020);
    return Product(
      id: id,
      barcode: barcode,
      name: name,
      sellingPrice: sellingPrice ?? price,
      costPrice: costPrice,
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
      source: 'manual',
      sourceId: '  receipt-42  ',
    );

    expect(updated.quantity, 7);
    final history = await repository.getStockTransactions('product-1');
    expect(history, hasLength(2));
    expect(history.first.reason, 'Sale');
    expect(history.first.note, 'Receipt 42');
    expect(history.first.previousQuantity, 10);
    expect(history.first.resultingQuantity, 7);
    expect(history.first.sellingPriceSnapshot, 25);
    expect(history.first.costPriceSnapshot, 12);
    expect(history.first.source, 'manual');
    expect(history.first.sourceId, 'receipt-42');

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

  test(
    'stock adjustment rejects blank reason and source before mutation',
    () async {
      await repository.add(product());

      await expectLater(
        repository.adjustStock(
          productId: 'product-1',
          delta: -1,
          reason: '   ',
          note: '',
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.adjustStock(
          productId: 'product-1',
          delta: -1,
          reason: 'Sale',
          note: '',
          source: '\t',
        ),
        throwsArgumentError,
      );

      expect((await repository.getById('product-1'))!.quantity, 10);
      expect(await repository.getStockTransactions('product-1'), hasLength(1));
    },
  );

  test(
    'stock adjustment trims metadata and normalizes blank source ID',
    () async {
      await repository.add(product());

      await repository.adjustStock(
        productId: 'product-1',
        delta: -1,
        reason: '  Sale  ',
        note: '',
        source: '  manual  ',
        sourceId: '   ',
      );

      final adjustment = (await repository.getStockTransactions(
        'product-1',
      )).first;
      expect(adjustment.reason, 'Sale');
      expect(adjustment.source, 'manual');
      expect(adjustment.sourceId, isNull);
    },
  );

  test(
    'sale keeps its original price snapshot after a product price edit',
    () async {
      await repository.add(
        product(quantity: 5, sellingPrice: 20, costPrice: 12),
      );

      await repository.adjustStock(
        productId: 'product-1',
        delta: -2,
        reason: 'Sale',
        note: '',
        source: 'manual',
      );
      await repository.update(
        product(quantity: 3, sellingPrice: 30, costPrice: 18),
      );

      final sale = (await repository.getStockTransactions('product-1')).first;
      expect(sale.sellingPriceSnapshot, 20);
      expect(sale.costPriceSnapshot, 12);
      expect(sale.source, 'manual');
    },
  );

  test('low-stock notification state is persisted independently', () async {
    await repository.add(product());

    await repository.setLowStockNotified('product-1', true);

    expect((await repository.getById('product-1'))!.lowStockNotified, isTrue);
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
    'permanent deletion rejects active stocktake references but cascades completed ones',
    () async {
      await repository.add(product());
      await repository.setArchived('product-1', archived: true);
      final db = await database.database;
      await db.insert('stocktake_sessions', {
        'id': 'session-1',
        'name': 'Active count',
        'status': 'in_progress',
        'scope_description': 'All products',
        'notes': '',
        'created_at': DateTime.utc(2026, 8, 19).toIso8601String(),
        'completed_at': null,
      });
      await db.insert('stocktake_items', {
        'session_id': 'session-1',
        'product_id': 'product-1',
        'expected_quantity': 10,
        'counted_quantity': null,
        'updated_at': DateTime.utc(2026, 8, 19).toIso8601String(),
      });

      await expectLater(
        repository.deletePermanently('product-1'),
        throwsA(isA<ProductReferencedByInProgressStocktakeException>()),
      );
      expect(await repository.getById('product-1'), isNotNull);
      expect(await db.query('stocktake_items'), hasLength(1));

      await db.update(
        'stocktake_sessions',
        {
          'status': 'completed',
          'completed_at': DateTime.utc(2026, 8, 20).toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: ['session-1'],
      );
      await repository.deletePermanently('product-1');

      expect(await repository.getById('product-1'), isNull);
      expect(await db.query('stocktake_items'), isEmpty);
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

  test('backup reads every table through one database transaction', () async {
    await repository.add(product());
    databaseEvents.clear();

    await repository.createBackup();

    const tables = {
      'products',
      'stock_transactions',
      'stocktake_sessions',
      'stocktake_items',
    };
    final backupQueries = databaseEvents
        .whereType<SqfliteLoggerSqlEvent>()
        .where(
          (event) => tables.any((table) => event.sql.contains('FROM $table')),
        );
    expect(backupQueries, hasLength(tables.length));
    expect(
      backupQueries.map((event) => event.transactionId),
      everyElement(isNotNull),
    );
    expect(
      backupQueries.map((event) => event.transactionId).toSet(),
      hasLength(1),
    );
  });

  test(
    'version 1 backup restore normalizes pricing and clears notifications',
    () async {
      final legacyProduct = product(sellingPrice: 10).toJson()
        ..remove('cost_price')
        ..remove('low_stock_threshold')
        ..['low_stock_notified'] = 1;

      await repository.restoreBackup({
        'format': 'stocklens-backup',
        'schema_version': 1,
        'products': [legacyProduct],
        'stock_transactions': [],
      });

      final restored = await repository.getByBarcode('4801234567890');
      expect(restored!.sellingPrice, 10);
      expect(restored.costPrice, 0);
      expect(restored.lowStockThreshold, 5);
      expect(restored.lowStockNotified, isFalse);
    },
  );

  test('legacy POS version 2 backup restores without offline fields', () async {
    final legacyProduct = product(price: 10).toJson()
      ..remove('cost_price')
      ..remove('low_stock_threshold')
      ..remove('low_stock_notified');

    await repository.restoreBackup({
      'format': 'stocklens-backup',
      'schema_version': 2,
      'products': [legacyProduct],
      'stock_transactions': [],
      'orders': [],
      'order_items': [],
    });

    final restored = await repository.getByBarcode('4801234567890');
    expect(restored!.sellingPrice, 10);
    expect(restored.costPrice, 0);
    expect(restored.lowStockThreshold, 5);
    expect(restored.lowStockNotified, isFalse);
  });

  test('version 2 backup round trips raw stocktake rows', () async {
    await repository.add(product());
    final db = await database.database;
    await db.insert('stocktake_sessions', {
      'id': 'session-1',
      'name': 'Weekly count',
      'status': 'in_progress',
      'scope_description': 'All shelves',
      'notes': '',
      'created_at': DateTime.utc(2020).toIso8601String(),
      'completed_at': null,
    });
    await db.insert('stocktake_items', {
      'session_id': 'session-1',
      'product_id': 'product-1',
      'expected_quantity': 10,
      'counted_quantity': 9,
      'updated_at': DateTime.utc(2020).toIso8601String(),
    });

    final backup = await repository.createBackup();
    expect(backup['schema_version'], 2);
    expect(backup['stocktake_sessions'], hasLength(1));
    expect(backup['stocktake_items'], hasLength(1));

    await repository.restoreBackup(backup);

    expect(await db.query('stocktake_sessions'), hasLength(1));
    expect(await db.query('stocktake_items'), hasLength(1));
  });

  test('version 2 restore rejects invalid transaction metadata', () async {
    await repository.add(product());
    final backup = await repository.createBackup();
    final transaction = Map<String, Object?>.from(
      (backup['stock_transactions']! as List).single as Map,
    )..['selling_price_snapshot'] = -1;

    await expectLater(
      repository.restoreBackup({
        ...backup,
        'stock_transactions': [transaction],
      }),
      throwsFormatException,
    );

    expect(await repository.getById('product-1'), isNotNull);
  });

  test('version 2 restore rejects malformed raw product values', () async {
    await repository.add(product());
    final backup = await repository.createBackup();
    final validProduct = Map<String, Object?>.from(
      (backup['products']! as List).single as Map,
    );
    const missing = Object();
    final invalidValues = <(String, Object?)>[
      ('id', missing),
      ('id', '   '),
      ('id', 7),
      ('barcode', missing),
      ('barcode', ''),
      ('barcode', 7),
      ('name', missing),
      ('name', '\t'),
      ('name', 7),
      ('category', missing),
      ('category', 7),
      ('description', missing),
      ('description', 7),
      ('price', missing),
      ('price', -1),
      ('price', double.nan),
      ('price', double.infinity),
      ('cost_price', missing),
      ('cost_price', -1),
      ('cost_price', double.nan),
      ('cost_price', double.infinity),
      ('quantity', missing),
      ('quantity', -1),
      ('quantity', 1.5),
      ('low_stock_threshold', missing),
      ('low_stock_threshold', -1),
      ('low_stock_threshold', 1.5),
      ('low_stock_notified', missing),
      ('low_stock_notified', 2),
      ('low_stock_notified', true),
      ('created_at', missing),
      ('created_at', 'not-a-date'),
      ('updated_at', missing),
      ('updated_at', 'not-a-date'),
      ('archived_at', 'not-a-date'),
    ];

    for (final (field, value) in invalidValues) {
      final malformed = Map<String, Object?>.from(validProduct);
      if (identical(value, missing)) {
        malformed.remove(field);
      } else {
        malformed[field] = value;
      }

      await expectLater(
        repository.restoreBackup({
          ...backup,
          'products': [malformed],
        }),
        throwsFormatException,
        reason: 'v2 product must reject $field=$value',
      );
    }

    expect((await repository.getById('product-1'))!.quantity, 10);
  });

  test('version 1 restore validates products after normalization', () async {
    final legacyProduct = product().toJson()
      ..remove('cost_price')
      ..remove('low_stock_threshold')
      ..remove('low_stock_notified');
    final malformedRows = <Map<String, Object?>>[
      Map<String, Object?>.from(legacyProduct)..remove('price'),
      Map<String, Object?>.from(legacyProduct)..remove('category'),
      Map<String, Object?>.from(legacyProduct)..['description'] = 7,
      Map<String, Object?>.from(legacyProduct)..['quantity'] = 1.5,
      Map<String, Object?>.from(legacyProduct)..['created_at'] = 'not-a-date',
    ];

    for (final malformed in malformedRows) {
      await expectLater(
        repository.restoreBackup({
          'format': 'stocklens-backup',
          'schema_version': 1,
          'products': [malformed],
          'stock_transactions': [],
        }),
        throwsFormatException,
      );
    }

    expect(await repository.getById('product-1'), isNull);
  });

  test('version 2 restore rejects fractional transaction quantities', () async {
    await repository.add(product());
    final backup = await repository.createBackup();
    final transaction =
        Map<String, Object?>.from(
            (backup['stock_transactions']! as List).single as Map,
          )
          ..['delta'] = 1.5
          ..['resulting_quantity'] = 1.5;

    await expectLater(
      repository.restoreBackup({
        ...backup,
        'stock_transactions': [transaction],
      }),
      throwsFormatException,
    );

    expect((await repository.getById('product-1'))!.quantity, 10);
  });

  test(
    'version 2 restore rejects malformed stocktake items and unknown products',
    () async {
      await repository.add(product());
      final backup = await repository.createBackup();
      final timestamp = DateTime.utc(2020).toIso8601String();

      Future<void> expectInvalidItem(Map<String, Object?> item) => expectLater(
        repository.restoreBackup({
          ...backup,
          'stocktake_sessions': [
            {
              'id': 'session-1',
              'name': 'Weekly count',
              'status': 'in_progress',
              'scope_description': 'All shelves',
              'notes': '',
              'created_at': timestamp,
              'completed_at': null,
            },
          ],
          'stocktake_items': [item],
        }),
        throwsFormatException,
      );

      await expectInvalidItem({
        'session_id': 'session-1',
        'product_id': 'unknown-product',
        'expected_quantity': 10,
        'counted_quantity': null,
        'updated_at': timestamp,
      });
      await expectInvalidItem({
        'session_id': 'session-1',
        'product_id': 'product-1',
        'expected_quantity': 1.5,
        'counted_quantity': null,
        'updated_at': timestamp,
      });

      expect(await repository.getById('product-1'), isNotNull);
    },
  );

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
    final row = product().toJson()
      ..remove('archived_at')
      ..remove('cost_price')
      ..remove('low_stock_threshold')
      ..remove('low_stock_notified');
    await legacy.insert('products', row);
    await legacy.close();

    database = AppDatabase.forTesting(path);
    repository = LocalProductRepository(database);
    final migrated = await repository.getById('product-1');
    final columns = await (await database.database).rawQuery(
      'PRAGMA table_info(products)',
    );

    expect(migrated?.name, 'Test Product');
    expect(migrated?.sellingPrice, 25);
    expect(
      columns.map((column) => column['name']),
      containsAll([
        'archived_at',
        'cost_price',
        'low_stock_threshold',
        'low_stock_notified',
      ]),
    );
    expect(migrated?.costPrice, 0);
    expect(migrated?.lowStockThreshold, 5);
    expect(migrated?.lowStockNotified, isFalse);
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

  test(
    'clean version 3 database creates stocktake tables and report indexes',
    () async {
      final db = await database.database;
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final productIndexes = await db.rawQuery('PRAGMA index_list(products)');
      final transactionIndexes = await db.rawQuery(
        'PRAGMA index_list(stock_transactions)',
      );
      final sessionIndexes = await db.rawQuery(
        'PRAGMA index_list(stocktake_sessions)',
      );
      final itemIndexes = await db.rawQuery(
        'PRAGMA index_list(stocktake_items)',
      );

      expect(
        tables,
        contains(
          predicate<Map<String, Object?>>(
            (row) => row['name'] == 'stocktake_sessions',
          ),
        ),
      );
      expect(
        tables,
        contains(
          predicate<Map<String, Object?>>(
            (row) => row['name'] == 'stocktake_items',
          ),
        ),
      );
      expect(
        productIndexes.map((row) => row['name']),
        contains('idx_products_active_low_stock'),
      );
      expect(
        transactionIndexes.map((row) => row['name']),
        contains('idx_transactions_date_reason'),
      );
      expect(
        sessionIndexes.map((row) => row['name']),
        contains('idx_stocktake_sessions_status_date'),
      );
      expect(
        itemIndexes.map((row) => row['name']),
        contains('idx_stocktake_items_product'),
      );
    },
  );

  test('version 2 database migrates stocktake and transaction schema', () async {
    await database.close();
    final path =
        '${temporaryDirectory.path}${Platform.pathSeparator}stocklens.db';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE products (
              id TEXT PRIMARY KEY,
              barcode TEXT NOT NULL UNIQUE,
              name TEXT NOT NULL,
              price REAL NOT NULL,
              category TEXT NOT NULL,
              description TEXT NOT NULL DEFAULT '',
              quantity INTEGER NOT NULL,
              image_path TEXT,
              archived_at TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE stock_transactions (
              id TEXT PRIMARY KEY,
              product_id TEXT NOT NULL,
              delta INTEGER NOT NULL,
              reason TEXT NOT NULL,
              note TEXT NOT NULL DEFAULT '',
              previous_quantity INTEGER NOT NULL,
              resulting_quantity INTEGER NOT NULL,
              occurred_at TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE TABLE app_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    await legacy.insert('products', {
      'id': 'legacy-v2-product',
      'barcode': '4801234567891',
      'name': 'Legacy v2 Product',
      'price': 31.25,
      'category': 'Legacy',
      'description': 'Migrated product',
      'quantity': 6,
      'created_at': DateTime.utc(2020).toIso8601String(),
      'updated_at': DateTime.utc(2020).toIso8601String(),
    });
    await legacy.insert('stock_transactions', {
      'id': 'legacy-v2-transaction',
      'product_id': 'legacy-v2-product',
      'delta': 6,
      'reason': 'Initial stock',
      'note': 'Original inventory',
      'previous_quantity': 0,
      'resulting_quantity': 6,
      'occurred_at': DateTime.utc(2020).toIso8601String(),
    });
    await legacy.close();

    database = AppDatabase.forTesting(path);
    repository = LocalProductRepository(database);
    final db = await database.database;
    final transactionColumns = await db.rawQuery(
      'PRAGMA table_info(stock_transactions)',
    );
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );

    expect(
      transactionColumns.map((column) => column['name']),
      containsAll([
        'selling_price_snapshot',
        'cost_price_snapshot',
        'source',
        'source_id',
      ]),
    );
    expect(
      tables.map((row) => row['name']),
      containsAll(['stocktake_sessions', 'stocktake_items']),
    );
    final migratedProduct = await repository.getById('legacy-v2-product');
    final migratedHistory = await repository.getStockTransactions(
      'legacy-v2-product',
    );

    expect(migratedProduct?.sellingPrice, 31.25);
    expect(migratedHistory, hasLength(1));
    expect(migratedHistory.single.reason, 'Initial stock');
    expect(migratedHistory.single.note, 'Original inventory');
    expect(migratedHistory.single.sellingPriceSnapshot, isNull);
    expect(migratedHistory.single.costPriceSnapshot, isNull);
    expect(migratedHistory.single.source, isNull);
    expect(migratedHistory.single.sourceId, isNull);
  });
}
