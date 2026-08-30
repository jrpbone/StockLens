import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/models/inventory_import.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/stock_transaction.dart';
import 'package:stocklens/repositories/inventory_import_repository.dart';
import 'package:stocklens/repositories/product_repository.dart';
import 'package:stocklens/screens/inventory/data_management_screen.dart';
import 'package:stocklens/services/inventory_file_service.dart';
import 'package:stocklens/services/inventory_import_service.dart';
import 'package:stocklens/services/product_service.dart';

class _ProductRepository implements ProductRepository {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> add(Product product) async {}
  @override
  Future<void> update(Product product) async {}
  @override
  Future<Product> adjustStock({
    required String productId,
    required int delta,
    required String reason,
    required String note,
    String source = 'manual',
    String? sourceId,
  }) => throw UnimplementedError();
  @override
  Future<void> setLowStockNotified(String productId, bool value) async {}
  @override
  Future<void> deletePermanently(String productId) async {}
  @override
  Future<Map<String, Object?>> createBackup() async => const {};
  @override
  Future<List<Product>> getArchivedProducts({String query = ''}) async => [];
  @override
  Future<List<Product>> getLowStockProducts() async => [];
  @override
  Future<List<StockTransaction>> getStockTransactions(String productId) async =>
      [];
  @override
  Future<Product> setArchived(String productId, {required bool archived}) =>
      throw UnimplementedError();
  @override
  Future<void> restoreBackup(Map<String, Object?> backup) async {}
  @override
  Future<List<String>> getCategories() async => [];
  @override
  Future<Product?> getByBarcode(String barcode) async => null;
  @override
  Future<Product?> getById(String id) async => null;
  @override
  Future<List<Product>> getProducts({
    String query = '',
    String? category,
    ProductSort sort = ProductSort.nameAsc,
  }) async => [];
}

class _ImportRepository implements InventoryImportRepository {
  @override
  Future<List<Product>> getByBarcodes(Iterable<String> barcodes) async => [];
  @override
  Future<List<InventoryImportProductChange>> apply(
    InventoryImportPreview preview, {
    required DateTime appliedAt,
  }) async => [];
}

class _ImportService extends InventoryImportService {
  _ImportService() : super(_ImportRepository());

  @override
  Future<InventoryImportPreview> preview(String csvContent) async =>
      InventoryImportPreview(
        importId: 'id',
        rows: [
          InventoryImportRowPreview(
            candidate: const InventoryImportCandidate(
              rowNumber: 2,
              barcode: '111',
              name: 'Picked product',
            ),
            before: null,
            after: Product(
              id: 'new',
              barcode: '111',
              name: 'Picked product',
              sellingPrice: 0,
              category: 'Uncategorized',
              description: '',
              quantity: 0,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
            productDetailsChanged: true,
            stockChanged: false,
          ),
        ],
        blockingErrors: const [],
      );
}

class _PickedCsvFileService extends InventoryFileService {
  const _PickedCsvFileService();

  @override
  Future<String?> pickCsv() async => 'barcode,name\n111,Picked product';
}

void main() {
  testWidgets('opens CSV preview from Data and Backups', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DataManagementScreen(
          service: ProductService(_ProductRepository()),
          importService: _ImportService(),
          fileService: const _PickedCsvFileService(),
        ),
      ),
    );

    expect(find.text('Import Inventory CSV'), findsOneWidget);
    await tester.tap(find.text('Import Inventory CSV'));
    await tester.pumpAndSettle();

    expect(find.text('Inventory Import'), findsOneWidget);
    expect(find.text('Picked product'), findsOneWidget);
  });

  test('pickCsv returns strict UTF-8 content for one CSV file', () async {
    final directory = await Directory.systemTemp.createTemp('stocklens-csv-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(
      '${directory.path}${Platform.pathSeparator}inventory.csv',
    );
    await file.writeAsString('barcode,name\n111,Café');
    final service = InventoryFileService(
      picker: () async => FilePickerResult([
        PlatformFile(
          path: file.path,
          name: 'inventory.csv',
          size: await file.length(),
        ),
      ]),
    );

    expect(await service.pickCsv(), 'barcode,name\n111,Café');
  });

  test('pickCsv rejects files larger than 20 MB', () async {
    final directory = await Directory.systemTemp.createTemp('stocklens-csv-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}large.csv');
    await file.open(mode: FileMode.write).then((handle) async {
      await handle.truncate(20 * 1024 * 1024 + 1);
      await handle.close();
    });
    final service = InventoryFileService(
      picker: () async => FilePickerResult([
        PlatformFile(
          path: file.path,
          name: 'large.csv',
          size: await file.length(),
        ),
      ]),
    );

    await expectLater(
      service.pickCsv(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'CSV file is larger than 20 MB.',
        ),
      ),
    );
  });

  test('pickCsv rejects invalid UTF-8 and a non-CSV extension', () async {
    final directory = await Directory.systemTemp.createTemp('stocklens-csv-');
    addTearDown(() => directory.delete(recursive: true));
    final invalid = File(
      '${directory.path}${Platform.pathSeparator}invalid.csv',
    );
    await invalid.writeAsBytes(Uint8List.fromList([0xC3, 0x28]));
    final invalidUtf8 = InventoryFileService(
      picker: () async => FilePickerResult([
        PlatformFile(path: invalid.path, name: 'invalid.csv', size: 2),
      ]),
    );
    await expectLater(invalidUtf8.pickCsv(), throwsFormatException);

    final wrongExtension = InventoryFileService(
      picker: () async => FilePickerResult([
        PlatformFile(path: invalid.path, name: 'invalid.txt', size: 2),
      ]),
    );
    await expectLater(wrongExtension.pickCsv(), throwsFormatException);
  });
}
