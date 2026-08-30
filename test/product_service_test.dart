import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stocklens/data/local/app_database.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/repositories/local_product_repository.dart';
import 'package:stocklens/services/product_image_storage.dart';
import 'package:stocklens/services/low_stock_notification_service.dart';
import 'package:stocklens/services/product_service.dart';

class _FakeImageStorage implements ProductImageStorage {
  final deleted = <String>[];
  final persisted = <String?>[];

  @override
  Future<String?> persist(String? sourcePath) async {
    persisted.add(sourcePath);
    if (sourcePath == null || sourcePath.startsWith('managed/')) {
      return sourcePath;
    }
    return 'managed/$sourcePath';
  }

  @override
  Future<String> persistBytes(
    List<int> bytes, {
    required String extension,
  }) async => 'managed/restored$extension';

  @override
  Future<void> delete(String? imagePath) async {
    if (imagePath != null) deleted.add(imagePath);
  }
}

class _RecordingLowStockGateway implements LowStockNotificationGateway {
  _RecordingLowStockGateway({this.shouldFail = false});

  final bool shouldFail;
  final shown = <String>[];

  @override
  Future<void> showLowStock(Product product) async {
    if (shouldFail) throw StateError('Notification platform unavailable');
    shown.add(product.id);
  }
}

class _FailingNotificationLookupRepository extends LocalProductRepository {
  _FailingNotificationLookupRepository(super.database);

  @override
  Future<Product?> getById(String id) {
    throw StateError('Notification-state lookup failed');
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temporaryDirectory;
  late AppDatabase database;
  late LocalProductRepository repository;
  late ProductService service;
  late _FakeImageStorage images;
  late _RecordingLowStockGateway gateway;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'stocklens-service-',
    );
    database = AppDatabase.forTesting(
      '${temporaryDirectory.path}${Platform.pathSeparator}stocklens.db',
    );
    repository = LocalProductRepository(database);
    images = _FakeImageStorage();
    gateway = _RecordingLowStockGateway();
    service = ProductService(
      repository,
      imageStorage: images,
      lowStockNotifications: LowStockNotificationService(
        repository,
        gateway: gateway,
      ),
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'images become managed and normal edits cannot bypass stock history',
    () async {
      final added = await service.add(
        barcode: '123',
        name: 'Product',
        price: 10,
        category: 'Test',
        quantity: 4,
        description: '',
        imagePath: 'picker/photo.jpg',
      );
      expect(added.imagePath, 'managed/picker/photo.jpg');

      final edited = await service.update(
        added.copyWith(quantity: 999, imagePath: 'picker/replacement.png'),
      );
      expect(edited.quantity, 4);
      expect(edited.imagePath, 'managed/picker/replacement.png');
      expect(images.deleted, contains('managed/picker/photo.jpg'));
      expect(await service.stockTransactions(added.id), hasLength(1));
    },
  );

  test(
    'rejects negative selling price, cost price, and threshold before add',
    () async {
      Future<void> expectInvalid({
        required double sellingPrice,
        required double costPrice,
        required int lowStockThreshold,
      }) async {
        await expectLater(
          service.add(
            barcode: '123',
            name: 'Product',
            sellingPrice: sellingPrice,
            costPrice: costPrice,
            lowStockThreshold: lowStockThreshold,
            category: 'Test',
            quantity: 4,
            description: '',
            imagePath: 'picker/photo.jpg',
          ),
          throwsArgumentError,
        );
      }

      await expectInvalid(
        sellingPrice: -0.01,
        costPrice: 0,
        lowStockThreshold: 5,
      );
      await expectInvalid(
        sellingPrice: 10,
        costPrice: -0.01,
        lowStockThreshold: 5,
      );
      await expectInvalid(
        sellingPrice: 10,
        costPrice: 0,
        lowStockThreshold: -1,
      );

      expect(await service.products(), isEmpty);
      expect(images.persisted, isEmpty);
    },
  );

  test('rejects non-finite prices before add persistence', () async {
    final invalidPricing = <(double, double)>[
      (double.nan, 5),
      (double.infinity, 5),
      (10, double.nan),
      (10, double.infinity),
    ];

    for (var index = 0; index < invalidPricing.length; index++) {
      final (sellingPrice, costPrice) = invalidPricing[index];
      await expectLater(
        service.add(
          barcode: 'invalid-$index',
          name: 'Product',
          sellingPrice: sellingPrice,
          costPrice: costPrice,
          category: 'Test',
          quantity: 4,
          description: '',
          imagePath: 'picker/photo.jpg',
        ),
        throwsArgumentError,
      );
    }

    expect(images.persisted, isEmpty);
    expect(await service.products(), isEmpty);
  });

  test('rejects negative pricing values before update persistence', () async {
    final added = await service.add(
      barcode: '123',
      name: 'Product',
      sellingPrice: 10,
      costPrice: 5,
      lowStockThreshold: 2,
      category: 'Test',
      quantity: 4,
      description: '',
    );
    images.persisted.clear();

    await expectLater(
      service.update(added.copyWith(costPrice: -1)),
      throwsArgumentError,
    );

    expect((await service.byId(added.id))!.costPrice, 5);
    expect(images.persisted, isEmpty);
  });

  test('rejects non-finite prices before update persistence', () async {
    final added = await service.add(
      barcode: '123',
      name: 'Product',
      sellingPrice: 10,
      costPrice: 5,
      category: 'Test',
      quantity: 4,
      description: '',
    );
    images.persisted.clear();
    final invalidPricing = <(double, double)>[
      (double.nan, 5),
      (double.infinity, 5),
      (10, double.nan),
      (10, double.infinity),
    ];

    for (final (sellingPrice, costPrice) in invalidPricing) {
      await expectLater(
        service.update(
          added.copyWith(sellingPrice: sellingPrice, costPrice: costPrice),
        ),
        throwsArgumentError,
      );
    }

    final stored = await service.byId(added.id);
    expect(stored!.sellingPrice, 10);
    expect(stored.costPrice, 5);
    expect(images.persisted, isEmpty);
  });

  test('add evaluates an initially low-stock product', () async {
    final added = await service.add(
      barcode: 'low-add',
      name: 'Low add',
      sellingPrice: 10,
      lowStockThreshold: 0,
      category: 'Test',
      quantity: 0,
      description: '',
    );

    expect(gateway.shown, [added.id]);
    expect((await service.byId(added.id))!.lowStockNotified, isTrue);
  });

  test(
    'update evaluates a threshold edit that crosses into low stock',
    () async {
      final added = await service.add(
        barcode: 'threshold-edit',
        name: 'Threshold edit',
        sellingPrice: 10,
        lowStockThreshold: 3,
        category: 'Test',
        quantity: 4,
        description: '',
      );

      final updated = await service.update(
        added.copyWith(lowStockThreshold: 5),
      );

      expect(gateway.shown, [updated.id]);
      expect((await service.byId(updated.id))!.lowStockNotified, isTrue);
    },
  );

  test(
    'stock adjustment evaluates against persisted state rather than stale input',
    () async {
      final added = await service.add(
        barcode: 'stale-adjustment',
        name: 'Stale adjustment',
        sellingPrice: 10,
        lowStockThreshold: 5,
        category: 'Test',
        quantity: 6,
        description: '',
      );

      final adjusted = await service.adjustStock(
        added.copyWith(quantity: 99),
        -1,
        reason: 'Sale',
      );

      expect(adjusted.quantity, 5);
      expect(gateway.shown, [added.id]);
      expect((await service.byId(added.id))!.lowStockNotified, isTrue);
    },
  );

  test(
    'a gateway failure cannot roll back a committed stock adjustment',
    () async {
      final failingService = ProductService(
        repository,
        imageStorage: images,
        lowStockNotifications: LowStockNotificationService(
          repository,
          gateway: _RecordingLowStockGateway(shouldFail: true),
        ),
      );
      final added = await failingService.add(
        barcode: 'failing-gateway',
        name: 'Failing gateway',
        sellingPrice: 10,
        lowStockThreshold: 5,
        category: 'Test',
        quantity: 6,
        description: '',
      );

      final adjusted = await failingService.adjustStock(
        added,
        -1,
        reason: 'Sale',
      );

      expect(adjusted.quantity, 5);
      expect((await failingService.byId(added.id))!.lowStockNotified, isFalse);
    },
  );

  test('archive clears low-stock notification state after commit', () async {
    final added = await service.add(
      barcode: 'archive-low',
      name: 'Archive low',
      sellingPrice: 10,
      lowStockThreshold: 5,
      category: 'Test',
      quantity: 5,
      description: '',
    );
    expect((await repository.getById(added.id))!.lowStockNotified, isTrue);

    final archived = await service.archive(added);

    expect(archived.isLowStock, isFalse);
    expect((await repository.getById(added.id))!.lowStockNotified, isFalse);
  });

  test(
    'restore evaluates an archived low-stock product after commit',
    () async {
      final timestamp = DateTime.utc(2026, 8, 19);
      final archived = Product(
        id: 'restore-low',
        barcode: 'restore-low',
        name: 'Restore low',
        sellingPrice: 10,
        category: 'Test',
        description: '',
        quantity: 5,
        lowStockThreshold: 5,
        archivedAt: timestamp,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      await repository.add(archived);

      final restored = await service.restore(archived);

      expect(restored.isLowStock, isTrue);
      expect(gateway.shown, [archived.id]);
      expect((await repository.getById(archived.id))!.lowStockNotified, isTrue);
    },
  );

  test(
    'notification lookup failure after add keeps the committed managed image',
    () async {
      final failingService = ProductService(
        repository,
        imageStorage: images,
        lowStockNotifications: LowStockNotificationService(
          _FailingNotificationLookupRepository(database),
          gateway: gateway,
        ),
      );

      final added = await failingService.add(
        barcode: 'post-commit-add',
        name: 'Post-commit add',
        sellingPrice: 10,
        category: 'Test',
        quantity: 0,
        description: '',
        imagePath: 'picker/add.png',
      );

      expect(added.imagePath, 'managed/picker/add.png');
      expect((await repository.getById(added.id))!.imagePath, added.imagePath);
      expect(images.deleted, isNot(contains(added.imagePath)));
    },
  );

  test(
    'notification lookup failure after update keeps the committed replacement image',
    () async {
      final added = await service.add(
        barcode: 'post-commit-update',
        name: 'Post-commit update',
        sellingPrice: 10,
        category: 'Test',
        quantity: 10,
        description: '',
        imagePath: 'picker/original.png',
      );
      images.deleted.clear();
      final failingService = ProductService(
        repository,
        imageStorage: images,
        lowStockNotifications: LowStockNotificationService(
          _FailingNotificationLookupRepository(database),
          gateway: gateway,
        ),
      );

      final updated = await failingService.update(
        added.copyWith(imagePath: 'picker/replacement.png'),
      );

      expect(updated.imagePath, 'managed/picker/replacement.png');
      expect(
        (await repository.getById(added.id))!.imagePath,
        updated.imagePath,
      );
      expect(images.deleted, isNot(contains(updated.imagePath)));
    },
  );

  test('CSV includes active and archived products with escaped text', () async {
    final product = await service.add(
      barcode: '123',
      name: 'Product, "Large"',
      sellingPrice: 10,
      costPrice: 6,
      lowStockThreshold: 2,
      category: 'Test',
      quantity: 0,
      description: 'Quoted "description"',
    );
    await service.archive(product);

    final csv = await service.inventoryCsv();
    expect(csv, contains('"selling_price","cost_price","low_stock_threshold"'));
    expect(csv, contains('"10.0","6.0","2"'));
    expect(csv, contains('"Product, ""Large"""'));
    expect(csv, contains('"archived"'));
  });
}
