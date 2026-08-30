import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stocklens/data/local/app_database.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/stocktake_session.dart';
import 'package:stocklens/repositories/local_product_repository.dart';
import 'package:stocklens/repositories/local_stocktake_repository.dart';
import 'package:stocklens/repositories/stocktake_repository.dart';
import 'package:stocklens/services/low_stock_notification_service.dart';
import 'package:stocklens/services/stocktake_service.dart';

class _RecordingGateway implements LowStockNotificationGateway {
  final shown = <String>[];

  @override
  Future<void> showLowStock(Product product) async {
    shown.add(product.id);
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temporaryDirectory;
  late AppDatabase database;
  late LocalProductRepository products;
  late StocktakeService service;
  late _RecordingGateway gateway;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'stocklens-stocktake-service-',
    );
    database = AppDatabase.forTesting(
      '${temporaryDirectory.path}${Platform.pathSeparator}stocklens.db',
    );
    products = LocalProductRepository(database);
    gateway = _RecordingGateway();
    service = StocktakeService(
      LocalStocktakeRepository(database),
      products,
      lowStockNotifications: LowStockNotificationService(
        products,
        gateway: gateway,
      ),
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<Product> addProduct({
    required String id,
    required String barcode,
    required int quantity,
    int lowStockThreshold = 5,
  }) async {
    final now = DateTime.utc(2026, 8, 19);
    final product = Product(
      id: id,
      barcode: barcode,
      name: 'Product $id',
      price: 12,
      category: 'Test',
      description: '',
      quantity: quantity,
      lowStockThreshold: lowStockThreshold,
      createdAt: now,
      updatedAt: now,
    );
    await products.add(product);
    return product;
  }

  test(
    'creates and resumes a session with the product quantities at start',
    () async {
      final cola = await addProduct(id: 'cola', barcode: '111', quantity: 12);
      final water = await addProduct(id: 'water', barcode: '222', quantity: 3);

      final created = await service.create(
        name: '  Beverages count  ',
        productIds: [cola.id, water.id],
        scopeDescription: '  Category: Beverages  ',
        notes: '  Morning shift  ',
      );
      final resumed = await service.session(created.id);

      expect(created.name, 'Beverages count');
      expect(created.scopeDescription, 'Category: Beverages');
      expect(created.notes, 'Morning shift');
      expect(resumed.items.map((item) => item.productId), [cola.id, water.id]);
      expect(resumed.items.map((item) => item.expectedQuantity), [12, 3]);
    },
  );

  test(
    'setCount autosaves and incrementing a barcode accumulates the count',
    () async {
      final cola = await addProduct(id: 'cola', barcode: '111', quantity: 12);
      final session = await service.create(
        name: 'Beverages count',
        productIds: [cola.id],
        scopeDescription: 'Category: Beverages',
      );

      await service.setCount(session.id, cola.id, 7);
      await service.incrementByBarcode(session.id, cola.barcode);
      await service.incrementByBarcode(session.id, cola.barcode);

      final item = (await service.session(session.id)).items.single;
      expect(item.countedQuantity, 9);
    },
  );

  test('concurrent barcode increments preserve every scan', () async {
    final cola = await addProduct(id: 'cola', barcode: '111', quantity: 12);
    final session = await service.create(
      name: 'Beverages count',
      productIds: [cola.id],
      scopeDescription: 'Category: Beverages',
    );

    await Future.wait(
      List.generate(
        12,
        (_) => service.incrementByBarcode(session.id, cola.barcode),
      ),
    );

    expect(
      (await service.session(session.id)).items.single.countedQuantity,
      12,
    );
  });

  test(
    'uses canonical product-ID scope order when creating and resuming',
    () async {
      final apple = await addProduct(id: 'apple', barcode: '111', quantity: 12);
      final zebra = await addProduct(id: 'zebra', barcode: '222', quantity: 3);

      final created = await service.create(
        name: 'Reverse input order',
        productIds: [zebra.id, apple.id],
        scopeDescription: 'Category: Test',
      );
      final resumed = await service.session(created.id);

      expect(created.items.map((item) => item.productId), ['apple', 'zebra']);
      expect(resumed.items.map((item) => item.productId), ['apple', 'zebra']);
    },
  );

  test(
    'sets unresolved items to zero while retaining an entered count',
    () async {
      final cola = await addProduct(id: 'cola', barcode: '111', quantity: 12);
      final water = await addProduct(id: 'water', barcode: '222', quantity: 3);
      final session = await service.create(
        name: 'Beverages count',
        productIds: [cola.id, water.id],
        scopeDescription: 'Category: Beverages',
      );
      await service.setCount(session.id, cola.id, 7);

      await service.setRemainingToZero(session.id);

      final items = (await service.session(session.id)).items;
      expect(
        items.singleWhere((item) => item.productId == cola.id).countedQuantity,
        7,
      );
      expect(
        items.singleWhere((item) => item.productId == water.id).countedQuantity,
        0,
      );
    },
  );

  test(
    'preview reads current product quantity and leaves unresolved items unchanged',
    () async {
      final cola = await addProduct(id: 'cola', barcode: '111', quantity: 12);
      final water = await addProduct(id: 'water', barcode: '222', quantity: 3);
      final session = await service.create(
        name: 'Beverages count',
        productIds: [cola.id, water.id],
        scopeDescription: 'Category: Beverages',
      );
      await service.setCount(session.id, cola.id, 7);
      await products.adjustStock(
        productId: cola.id,
        delta: 2,
        reason: 'Delivery',
        note: '',
      );

      final preview = await service.previewCompletion(session.id);

      expect(preview.unresolvedCount, 1);
      expect(preview.lines.single.currentQuantity, 14);
      expect(preview.lines.single.variance, -7);
      expect(preview.lines.single.changedSinceStart, isTrue);
      expect(
        (await service.session(session.id)).items
            .singleWhere((item) => item.productId == water.id)
            .countedQuantity,
        isNull,
      );
    },
  );

  test(
    'completes an accepted preview and evaluates low-stock alerts after commit',
    () async {
      final cola = await addProduct(
        id: 'cola',
        barcode: '111',
        quantity: 6,
        lowStockThreshold: 5,
      );
      final session = await service.create(
        name: 'Beverages count',
        productIds: [cola.id],
        scopeDescription: 'Category: Beverages',
      );
      await service.setCount(session.id, cola.id, 5);
      final preview = await service.previewCompletion(session.id);

      await service.complete(session.id, preview);

      expect((await products.getById(cola.id))!.quantity, 5);
      expect((await products.getById(cola.id))!.lowStockNotified, isTrue);
      expect(gateway.shown, [cola.id]);
      expect(
        (await service.session(session.id)).status,
        StocktakeStatus.completed,
      );
    },
  );

  test('rejects completion while any item remains unresolved', () async {
    final cola = await addProduct(id: 'cola', barcode: '111', quantity: 6);
    final water = await addProduct(id: 'water', barcode: '222', quantity: 4);
    final session = await service.create(
      name: 'Beverages count',
      productIds: [cola.id, water.id],
      scopeDescription: 'Category: Beverages',
    );
    await service.setCount(session.id, cola.id, 5);
    final preview = await service.previewCompletion(session.id);

    await expectLater(
      service.complete(session.id, preview),
      throwsA(isA<IncompleteStocktakeException>()),
    );

    expect((await products.getById(cola.id))!.quantity, 6);
    expect(
      (await service.session(session.id)).status,
      StocktakeStatus.inProgress,
    );
    expect(gateway.shown, isEmpty);
  });

  test('rejects a preview made stale by a later stock change', () async {
    final cola = await addProduct(id: 'cola', barcode: '111', quantity: 10);
    final session = await service.create(
      name: 'Beverages count',
      productIds: [cola.id],
      scopeDescription: 'Category: Beverages',
    );
    await service.setCount(session.id, cola.id, 7);
    final preview = await service.previewCompletion(session.id);
    await products.adjustStock(
      productId: cola.id,
      delta: -1,
      reason: 'Sale',
      note: '',
    );

    await expectLater(
      service.complete(session.id, preview),
      throwsA(isA<StaleStocktakeCompletionException>()),
    );

    expect((await products.getById(cola.id))!.quantity, 9);
    expect(
      (await service.session(session.id)).status,
      StocktakeStatus.inProgress,
    );
    expect(gateway.shown, isEmpty);
  });

  test('reconciles from the latest quantity accepted in the preview', () async {
    final cola = await addProduct(id: 'cola', barcode: '111', quantity: 10);
    final session = await service.create(
      name: 'Beverages count',
      productIds: [cola.id],
      scopeDescription: 'Category: Beverages',
    );
    await service.setCount(session.id, cola.id, 7);
    await products.adjustStock(
      productId: cola.id,
      delta: -1,
      reason: 'Sale',
      note: '',
    );
    final preview = await service.previewCompletion(session.id);

    expect(preview.lines.single.changedSinceStart, isTrue);
    expect(preview.lines.single.currentQuantity, 9);
    expect(preview.lines.single.variance, -2);
    await service.complete(session.id, preview);

    expect((await products.getById(cola.id))!.quantity, 7);
    final corrections = (await products.getStockTransactions(
      cola.id,
    )).where((transaction) => transaction.source == 'stocktake').toList();
    expect(corrections.single.delta, -2);
    expect(corrections.single.previousQuantity, 9);
    expect(corrections.single.resultingQuantity, 7);
  });

  test('rejects a completion preview created for another session', () async {
    final cola = await addProduct(id: 'cola', barcode: '111', quantity: 10);
    final first = await service.create(
      name: 'First count',
      productIds: [cola.id],
      scopeDescription: 'Product: Cola',
    );
    final second = await service.create(
      name: 'Second count',
      productIds: [cola.id],
      scopeDescription: 'Product: Cola',
    );
    await service.setCount(first.id, cola.id, 7);
    await service.setCount(second.id, cola.id, 7);
    final secondPreview = await service.previewCompletion(second.id);

    await expectLater(
      service.complete(first.id, secondPreview),
      throwsA(isA<StaleStocktakeCompletionException>()),
    );

    expect((await products.getById(cola.id))!.quantity, 10);
    expect(
      (await service.session(first.id)).status,
      StocktakeStatus.inProgress,
    );
    expect(
      (await service.session(second.id)).status,
      StocktakeStatus.inProgress,
    );
  });

  test(
    'rejects invalid scope, product IDs, counts, and scans before mutation',
    () async {
      final cola = await addProduct(id: 'cola', barcode: '111', quantity: 12);
      final outsideScope = await addProduct(
        id: 'outside-scope',
        barcode: '333',
        quantity: 8,
      );
      final archived = await addProduct(
        id: 'archived',
        barcode: '222',
        quantity: 3,
      );
      await products.setArchived(archived.id, archived: true);

      await expectLater(
        service.create(
          name: '   ',
          productIds: [cola.id],
          scopeDescription: 'Category: Beverages',
        ),
        throwsArgumentError,
      );
      await expectLater(
        service.create(
          name: 'Beverages count',
          productIds: [cola.id],
          scopeDescription: '   ',
        ),
        throwsArgumentError,
      );
      await expectLater(
        service.create(
          name: 'Beverages count',
          productIds: [],
          scopeDescription: 'Category: Beverages',
        ),
        throwsArgumentError,
      );
      await expectLater(
        service.create(
          name: 'Beverages count',
          productIds: ['   '],
          scopeDescription: 'Category: Beverages',
        ),
        throwsArgumentError,
      );
      await expectLater(
        service.create(
          name: 'Beverages count',
          productIds: ['missing-product'],
          scopeDescription: 'Category: Beverages',
        ),
        throwsStateError,
      );
      await expectLater(
        service.create(
          name: 'Beverages count',
          productIds: [cola.id, cola.id],
          scopeDescription: 'Category: Beverages',
        ),
        throwsArgumentError,
      );
      await expectLater(
        service.create(
          name: 'Beverages count',
          productIds: [archived.id],
          scopeDescription: 'Category: Beverages',
        ),
        throwsStateError,
      );
      final session = await service.create(
        name: 'Beverages count',
        productIds: [cola.id],
        scopeDescription: 'Category: Beverages',
      );
      await expectLater(
        service.setCount(session.id, cola.id, -1),
        throwsArgumentError,
      );
      await expectLater(
        service.incrementByBarcode(session.id, 'not-in-scope'),
        throwsStateError,
      );
      await expectLater(
        service.incrementByBarcode(session.id, outsideScope.barcode),
        throwsStateError,
      );
      expect(
        (await service.session(session.id)).items.single.countedQuantity,
        isNull,
      );
    },
  );

  test('rejects count mutations after a session is completed', () async {
    final cola = await addProduct(id: 'cola', barcode: '111', quantity: 12);
    final session = await service.create(
      name: 'Beverages count',
      productIds: [cola.id],
      scopeDescription: 'Category: Beverages',
    );
    await (await database.database).update(
      'stocktake_sessions',
      {
        'status': 'completed',
        'completed_at': DateTime.utc(2026, 8, 19, 11).toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [session.id],
    );

    await expectLater(
      service.setCount(session.id, cola.id, 2),
      throwsStateError,
    );
    await expectLater(
      service.incrementByBarcode(session.id, cola.barcode),
      throwsStateError,
    );
    await expectLater(service.setRemainingToZero(session.id), throwsStateError);
    expect(
      (await service.session(session.id)).items.single.countedQuantity,
      isNull,
    );
  });
}
