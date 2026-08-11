import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stocklens/data/local/app_database.dart';
import 'package:stocklens/repositories/local_product_repository.dart';
import 'package:stocklens/services/product_image_storage.dart';
import 'package:stocklens/services/product_service.dart';

class _FakeImageStorage implements ProductImageStorage {
  final deleted = <String>[];

  @override
  Future<String?> persist(String? sourcePath) async {
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

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temporaryDirectory;
  late AppDatabase database;
  late ProductService service;
  late _FakeImageStorage images;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'stocklens-service-',
    );
    database = AppDatabase.forTesting(
      '${temporaryDirectory.path}${Platform.pathSeparator}stocklens.db',
    );
    images = _FakeImageStorage();
    service = ProductService(
      LocalProductRepository(database),
      imageStorage: images,
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

  test('CSV includes active and archived products with escaped text', () async {
    final product = await service.add(
      barcode: '123',
      name: 'Product, "Large"',
      price: 10,
      category: 'Test',
      quantity: 0,
      description: 'Quoted "description"',
    );
    await service.archive(product);

    final csv = await service.inventoryCsv();
    expect(csv, contains('"Product, ""Large"""'));
    expect(csv, contains('"archived"'));
  });
}
