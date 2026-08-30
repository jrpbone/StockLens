import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stocklens/data/local/app_database.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/stocktake_item.dart';
import 'package:stocklens/models/stocktake_session.dart';
import 'package:stocklens/repositories/local_product_repository.dart';
import 'package:stocklens/repositories/local_stocktake_repository.dart';
import 'package:stocklens/repositories/stocktake_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temporaryDirectory;
  late AppDatabase database;
  late LocalProductRepository products;
  late LocalStocktakeRepository repository;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'stocklens-stocktake-repository-',
    );
    database = AppDatabase.forTesting(
      '${temporaryDirectory.path}${Platform.pathSeparator}stocklens.db',
    );
    products = LocalProductRepository(database);
    repository = LocalStocktakeRepository(database);
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Product product({
    required String id,
    required String barcode,
    required int quantity,
    double sellingPrice = 12,
    double costPrice = 7,
  }) {
    final now = DateTime.utc(2026, 8, 19);
    return Product(
      id: id,
      barcode: barcode,
      name: 'Product $id',
      sellingPrice: sellingPrice,
      costPrice: costPrice,
      category: 'Test',
      description: '',
      quantity: quantity,
      createdAt: now,
      updatedAt: now,
    );
  }

  test(
    'persists a session and expected-quantity item snapshots together',
    () async {
      await products.add(product(id: 'cola', barcode: '111', quantity: 12));
      await products.add(product(id: 'water', barcode: '222', quantity: 3));
      final createdAt = DateTime.utc(2026, 8, 19, 9);

      await repository.create(
        StocktakeSession(
          id: 'session-1',
          name: 'Beverages count',
          status: StocktakeStatus.inProgress,
          scopeDescription: 'Category: Beverages',
          notes: 'Morning shift',
          createdAt: createdAt,
        ),
        [
          StocktakeItem(
            sessionId: 'session-1',
            productId: 'cola',
            expectedQuantity: 12,
            updatedAt: createdAt,
          ),
          StocktakeItem(
            sessionId: 'session-1',
            productId: 'water',
            expectedQuantity: 3,
            updatedAt: createdAt,
          ),
        ],
      );

      final loaded = await repository.getById('session-1');

      expect(loaded, isNotNull);
      expect(loaded!.name, 'Beverages count');
      expect(loaded.scopeDescription, 'Category: Beverages');
      expect(loaded.notes, 'Morning shift');
      expect(loaded.items.map((item) => item.productId), ['cola', 'water']);
      expect(loaded.items.map((item) => item.expectedQuantity), [12, 3]);
      expect(
        loaded.items.every((item) => item.countedQuantity == null),
        isTrue,
      );
    },
  );

  test(
    'autosaves an item count without changing its expected snapshot',
    () async {
      await products.add(product(id: 'cola', barcode: '111', quantity: 12));
      final createdAt = DateTime.utc(2026, 8, 19, 9);
      await repository.create(
        StocktakeSession(
          id: 'session-1',
          name: 'Beverages count',
          status: StocktakeStatus.inProgress,
          scopeDescription: 'Category: Beverages',
          notes: '',
          createdAt: createdAt,
        ),
        [
          StocktakeItem(
            sessionId: 'session-1',
            productId: 'cola',
            expectedQuantity: 12,
            updatedAt: createdAt,
          ),
        ],
      );

      await repository.setCount(
        sessionId: 'session-1',
        productId: 'cola',
        countedQuantity: 7,
        updatedAt: DateTime.utc(2026, 8, 19, 10),
      );

      final item = (await repository.getById('session-1'))!.items.single;
      expect(item.expectedQuantity, 12);
      expect(item.countedQuantity, 7);
      expect(item.updatedAt, DateTime.utc(2026, 8, 19, 10));
    },
  );

  test(
    'completes reconciliation with sourced price-snapshot transactions',
    () async {
      await products.add(
        product(
          id: 'cola',
          barcode: '111',
          quantity: 10,
          sellingPrice: 15,
          costPrice: 9,
        ),
      );
      await products.add(product(id: 'water', barcode: '222', quantity: 4));
      final createdAt = DateTime.utc(2026, 8, 19, 9);
      await repository.create(
        StocktakeSession(
          id: 'session-1',
          name: 'Beverages count',
          status: StocktakeStatus.inProgress,
          scopeDescription: 'Category: Beverages',
          notes: '',
          createdAt: createdAt,
        ),
        [
          StocktakeItem(
            sessionId: 'session-1',
            productId: 'cola',
            expectedQuantity: 10,
            countedQuantity: 7,
            updatedAt: createdAt,
          ),
          StocktakeItem(
            sessionId: 'session-1',
            productId: 'water',
            expectedQuantity: 4,
            countedQuantity: 4,
            updatedAt: createdAt,
          ),
        ],
      );

      final changes = await repository.complete(
        sessionId: 'session-1',
        acceptedLines: const [
          AcceptedStocktakeLine(
            sessionId: 'session-1',
            productId: 'cola',
            countedQuantity: 7,
            currentQuantity: 10,
          ),
          AcceptedStocktakeLine(
            sessionId: 'session-1',
            productId: 'water',
            countedQuantity: 4,
            currentQuantity: 4,
          ),
        ],
        completedAt: DateTime.utc(2026, 8, 19, 11),
      );

      expect(changes, hasLength(1));
      expect(changes.single.before.quantity, 10);
      expect(changes.single.after.quantity, 7);
      expect((await products.getById('cola'))!.quantity, 7);
      expect((await products.getById('water'))!.quantity, 4);
      final completed = await repository.getById('session-1');
      expect(completed!.status, StocktakeStatus.completed);
      expect(completed.completedAt, DateTime.utc(2026, 8, 19, 11));

      final corrections = (await products.getStockTransactions(
        'cola',
      )).where((transaction) => transaction.source == 'stocktake').toList();
      expect(corrections, hasLength(1));
      expect(corrections.single.delta, -3);
      expect(corrections.single.reason, 'Inventory Correction');
      expect(corrections.single.previousQuantity, 10);
      expect(corrections.single.resultingQuantity, 7);
      expect(corrections.single.sellingPriceSnapshot, 15);
      expect(corrections.single.costPriceSnapshot, 9);
      expect(corrections.single.sourceId, 'session-1');
      expect(
        (await products.getStockTransactions(
          'water',
        )).where((transaction) => transaction.source == 'stocktake'),
        isEmpty,
      );
    },
  );

  test('rejects a stale accepted preview without changing inventory', () async {
    await products.add(product(id: 'cola', barcode: '111', quantity: 10));
    final createdAt = DateTime.utc(2026, 8, 19, 9);
    await repository.create(
      StocktakeSession(
        id: 'session-1',
        name: 'Beverages count',
        status: StocktakeStatus.inProgress,
        scopeDescription: 'Category: Beverages',
        notes: '',
        createdAt: createdAt,
      ),
      [
        StocktakeItem(
          sessionId: 'session-1',
          productId: 'cola',
          expectedQuantity: 10,
          countedQuantity: 7,
          updatedAt: createdAt,
        ),
      ],
    );
    await products.adjustStock(
      productId: 'cola',
      delta: -1,
      reason: 'Sale',
      note: '',
    );

    await expectLater(
      repository.complete(
        sessionId: 'session-1',
        acceptedLines: const [
          AcceptedStocktakeLine(
            sessionId: 'session-1',
            productId: 'cola',
            countedQuantity: 7,
            currentQuantity: 10,
          ),
        ],
        completedAt: DateTime.utc(2026, 8, 19, 11),
      ),
      throwsA(isA<StaleStocktakeCompletionException>()),
    );

    expect((await products.getById('cola'))!.quantity, 9);
    expect(
      (await repository.getById('session-1'))!.status,
      StocktakeStatus.inProgress,
    );
    expect(
      (await products.getStockTransactions(
        'cola',
      )).where((transaction) => transaction.source == 'stocktake'),
      isEmpty,
    );
  });

  test('rolls back every product when a later correction fails', () async {
    await products.add(product(id: 'cola', barcode: '111', quantity: 10));
    await products.add(product(id: 'water', barcode: '222', quantity: 5));
    final createdAt = DateTime.utc(2026, 8, 19, 9);
    await repository.create(
      StocktakeSession(
        id: 'session-1',
        name: 'Beverages count',
        status: StocktakeStatus.inProgress,
        scopeDescription: 'Category: Beverages',
        notes: '',
        createdAt: createdAt,
      ),
      [
        StocktakeItem(
          sessionId: 'session-1',
          productId: 'cola',
          expectedQuantity: 10,
          countedQuantity: 7,
          updatedAt: createdAt,
        ),
        StocktakeItem(
          sessionId: 'session-1',
          productId: 'water',
          expectedQuantity: 5,
          countedQuantity: 2,
          updatedAt: createdAt,
        ),
      ],
    );
    await (await database.database).execute('''
      CREATE TRIGGER fail_second_stocktake_correction
      BEFORE INSERT ON stock_transactions
      WHEN NEW.source = 'stocktake' AND NEW.product_id = 'water'
      BEGIN
        SELECT RAISE(ABORT, 'forced stocktake failure');
      END
    ''');

    await expectLater(
      repository.complete(
        sessionId: 'session-1',
        acceptedLines: const [
          AcceptedStocktakeLine(
            sessionId: 'session-1',
            productId: 'cola',
            countedQuantity: 7,
            currentQuantity: 10,
          ),
          AcceptedStocktakeLine(
            sessionId: 'session-1',
            productId: 'water',
            countedQuantity: 2,
            currentQuantity: 5,
          ),
        ],
        completedAt: DateTime.utc(2026, 8, 19, 11),
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect((await products.getById('cola'))!.quantity, 10);
    expect((await products.getById('water'))!.quantity, 5);
    expect(
      (await repository.getById('session-1'))!.status,
      StocktakeStatus.inProgress,
    );
    for (final productId in const ['cola', 'water']) {
      expect(
        (await products.getStockTransactions(
          productId,
        )).where((transaction) => transaction.source == 'stocktake'),
        isEmpty,
      );
    }
  });
}
