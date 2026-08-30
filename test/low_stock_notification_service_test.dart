import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stocklens/data/local/app_database.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/repositories/local_product_repository.dart';
import 'package:stocklens/services/low_stock_notification_service.dart';

class _RecordingGateway implements LowStockNotificationGateway {
  _RecordingGateway({this.shouldFail = false, this.failingIds = const {}});

  final bool shouldFail;
  final Set<String> failingIds;
  final attempted = <String>[];
  final shown = <String>[];

  @override
  Future<void> showLowStock(Product product) async {
    attempted.add(product.id);
    if (shouldFail || failingIds.contains(product.id)) {
      throw StateError('Platform notifications unavailable');
    }
    shown.add(product.id);
  }
}

class _FaultInjectingRepository extends LocalProductRepository {
  _FaultInjectingRepository(
    super.database, {
    this.lookupFailureIds = const {},
    this.stateFailureIds = const {},
  });

  final Set<String> lookupFailureIds;
  final Set<String> stateFailureIds;

  @override
  Future<Product?> getById(String id) {
    if (lookupFailureIds.contains(id)) {
      throw StateError('Notification-state lookup failed for $id');
    }
    return super.getById(id);
  }

  @override
  Future<void> setLowStockNotified(String productId, bool value) {
    if (stateFailureIds.contains(productId)) {
      throw StateError('Notification-state write failed for $productId');
    }
    return super.setLowStockNotified(productId, value);
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temporaryDirectory;
  late AppDatabase database;
  late LocalProductRepository repository;

  Product product({
    String id = 'product-1',
    String barcode = '4801234567890',
    String name = 'Product',
    int quantity = 6,
    int threshold = 5,
    DateTime? archivedAt,
  }) {
    final timestamp = DateTime.utc(2020);
    return Product(
      id: id,
      barcode: barcode,
      name: name,
      sellingPrice: 10,
      category: 'Test',
      description: '',
      quantity: quantity,
      lowStockThreshold: threshold,
      archivedAt: archivedAt,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'stocklens-low-stock-',
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

  test(
    'notifies once on a low-stock crossing and resets after recovery',
    () async {
      await repository.add(product());
      final gateway = _RecordingGateway();
      final service = LowStockNotificationService(repository, gateway: gateway);

      await service.evaluate(
        before: product(quantity: 6),
        after: product(quantity: 5),
      );
      expect(gateway.shown, ['product-1']);
      expect((await repository.getById('product-1'))!.lowStockNotified, isTrue);

      await service.evaluate(
        before: product(quantity: 5),
        after: product(quantity: 4),
      );
      expect(gateway.shown, hasLength(1));

      await service.evaluate(
        before: product(quantity: 5),
        after: product(quantity: 6),
      );
      expect(
        (await repository.getById('product-1'))!.lowStockNotified,
        isFalse,
      );
    },
  );

  test(
    'notifies when an edit raises the threshold across current stock',
    () async {
      await repository.add(product(quantity: 4, threshold: 3));
      final gateway = _RecordingGateway();
      final service = LowStockNotificationService(repository, gateway: gateway);

      await service.evaluate(
        before: product(quantity: 4, threshold: 3),
        after: product(quantity: 4, threshold: 5),
      );

      expect(gateway.shown, ['product-1']);
    },
  );

  test('a threshold of zero alerts only when quantity reaches zero', () async {
    await repository.add(product(quantity: 1, threshold: 0));
    final gateway = _RecordingGateway();
    final service = LowStockNotificationService(repository, gateway: gateway);

    await service.evaluate(
      before: product(quantity: 2, threshold: 0),
      after: product(quantity: 1, threshold: 0),
    );
    await service.evaluate(
      before: product(quantity: 1, threshold: 0),
      after: product(quantity: 0, threshold: 0),
    );

    expect(gateway.shown, ['product-1']);
  });

  test(
    'archiving a notified low-stock product clears its alert state',
    () async {
      final active = product(quantity: 5).copyWith(lowStockNotified: true);
      await repository.add(active);
      final gateway = _RecordingGateway();
      final service = LowStockNotificationService(repository, gateway: gateway);

      await service.evaluate(
        before: active,
        after: active.copyWith(archivedAt: DateTime.utc(2026, 8, 19)),
      );

      expect(gateway.shown, isEmpty);
      expect((await repository.getById(active.id))!.lowStockNotified, isFalse);
    },
  );

  test('restoring a low-stock product is an active-state crossing', () async {
    final archived = product(
      quantity: 5,
      archivedAt: DateTime.utc(2026, 8, 19),
    );
    await repository.add(archived);
    final gateway = _RecordingGateway();
    final service = LowStockNotificationService(repository, gateway: gateway);

    await service.evaluate(
      before: archived,
      after: archived.copyWith(archivedAt: null),
    );

    expect(gateway.shown, [archived.id]);
    expect((await repository.getById(archived.id))!.lowStockNotified, isTrue);
  });

  test(
    'a gateway failure does not persist notification state or throw',
    () async {
      await repository.add(product());
      final service = LowStockNotificationService(
        repository,
        gateway: _RecordingGateway(shouldFail: true),
      );

      await service.evaluate(
        before: product(quantity: 6),
        after: product(quantity: 5),
      );

      expect(
        (await repository.getById('product-1'))!.lowStockNotified,
        isFalse,
      );
    },
  );

  test(
    'batch evaluation continues after lookup, gateway, and state-write errors',
    () async {
      final faultingRepository = _FaultInjectingRepository(
        database,
        lookupFailureIds: const {'lookup-failure'},
        stateFailureIds: const {'state-failure'},
      );
      for (final id in const [
        'lookup-failure',
        'gateway-failure',
        'state-failure',
        'success',
      ]) {
        await faultingRepository.add(product(id: id, barcode: id, quantity: 5));
      }
      final gateway = _RecordingGateway(failingIds: const {'gateway-failure'});
      final service = LowStockNotificationService(
        faultingRepository,
        gateway: gateway,
      );

      await service.evaluateAll([
        for (final id in const [
          'lookup-failure',
          'gateway-failure',
          'state-failure',
          'success',
        ])
          LowStockProductChange(
            before: product(id: id, barcode: id, quantity: 6),
            after: product(id: id, barcode: id, quantity: 5),
          ),
      ]);

      expect(gateway.attempted, [
        'gateway-failure',
        'state-failure',
        'success',
      ]);
      expect(gateway.shown, ['state-failure', 'success']);
      expect(
        (await faultingRepository.getById('success'))!.lowStockNotified,
        isTrue,
      );
      expect(
        (await faultingRepository.getById('state-failure'))!.lowStockNotified,
        isFalse,
      );
    },
  );

  test('returns active low-stock products in escalation order', () async {
    await repository.add(
      product(
        id: 'out-far',
        barcode: '1',
        name: 'Zero',
        quantity: 0,
        threshold: 5,
      ),
    );
    await repository.add(
      product(
        id: 'out-exact',
        barcode: '2',
        name: 'Empty',
        quantity: 0,
        threshold: 0,
      ),
    );
    await repository.add(
      product(
        id: 'low-far',
        barcode: '3',
        name: 'Beta',
        quantity: 2,
        threshold: 9,
      ),
    );
    await repository.add(
      product(
        id: 'low-near',
        barcode: '4',
        name: 'apple',
        quantity: 4,
        threshold: 9,
      ),
    );
    await repository.add(
      product(
        id: 'healthy',
        barcode: '5',
        name: 'Healthy',
        quantity: 6,
        threshold: 5,
      ),
    );
    await repository.add(
      product(
        id: 'archived',
        barcode: '6',
        name: 'Archived',
        quantity: 0,
        threshold: 9,
      ),
    );
    await repository.setArchived('archived', archived: true);

    final products = await repository.getLowStockProducts();

    expect(products.map((item) => item.id), [
      'out-far',
      'out-exact',
      'low-far',
      'low-near',
    ]);
  });
}
