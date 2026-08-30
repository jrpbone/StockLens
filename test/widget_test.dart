import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:stocklens/app.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/sale_order.dart';
import 'package:stocklens/models/stock_transaction.dart';
import 'package:stocklens/repositories/product_repository.dart';
import 'package:stocklens/services/product_service.dart';

class _FakeRepository implements ProductRepository {
  _FakeRepository({this.product});

  final Product? product;

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
  }) => throw UnimplementedError();
  @override
  Future<void> deletePermanently(String productId) async {}
  @override
  Future<Map<String, Object?>> createBackup() async => {
    'format': 'stocklens-backup',
    'schema_version': 1,
    'products': <Object?>[],
    'stock_transactions': <Object?>[],
  };
  @override
  Future<List<Product>> getArchivedProducts({String query = ''}) async => [];
  @override
  Future<List<StockTransaction>> getStockTransactions(String productId) async =>
      [];
  @override
  Future<SaleOrder> completeSale(List<SaleRequestItem> items) =>
      throw UnimplementedError();
  @override
  Future<List<SaleOrder>> getOrders() async => [];
  @override
  Future<Product> setArchived(String productId, {required bool archived}) =>
      throw UnimplementedError();
  @override
  Future<void> restoreBackup(Map<String, Object?> backup) async {}
  @override
  Future<List<String>> getCategories() async => [];
  @override
  Future<Product?> getByBarcode(String barcode) async =>
      product?.barcode == barcode ? product : null;
  @override
  Future<Product?> getById(String id) async =>
      product?.id == id ? product : null;
  @override
  Future<List<Product>> getProducts({
    String query = '',
    String? category,
    ProductSort sort = ProductSort.nameAsc,
  }) async => [];
}

class _FakeMobileScannerPlatform extends MobileScannerPlatform {
  final _barcodes = StreamController<BarcodeCapture>.broadcast();
  bool isRunning = false;
  int startCalls = 0;
  int stopCalls = 0;
  int overlappingStarts = 0;

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodes.stream;

  @override
  Stream<TorchState> get torchStateStream =>
      Stream.value(TorchState.unavailable);

  @override
  Stream<double> get zoomScaleStateStream => Stream.value(1);

  @override
  Widget buildCameraView() => const SizedBox.square(dimension: 100);

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    startCalls++;
    if (isRunning) overlappingStarts++;
    isRunning = true;
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(200, 200),
      numberOfCameras: 1,
    );
  }

  @override
  Future<void> stop() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    stopCalls++;
    isRunning = false;
  }

  @override
  Future<void> dispose() => _barcodes.close();
}

void main() {
  testWidgets('shows the StockLens dashboard actions', (tester) async {
    await tester.pumpWidget(
      StockLensApp(productService: ProductService(_FakeRepository())),
    );
    await tester.pump();

    expect(find.text('StockLens'), findsOneWidget);
    expect(find.text('Scan. Search. Manage.'), findsOneWidget);
    expect(find.text('Scan Barcode'), findsOneWidget);
    expect(find.text('Inventory'), findsWidgets);
    expect(find.text('Add Product'), findsOneWidget);
  });

  testWidgets('cancelling manual barcode entry closes without an error', (
    tester,
  ) async {
    MobileScannerPlatform.instance = _FakeMobileScannerPlatform();
    await tester.pumpWidget(
      StockLensApp(productService: ProductService(_FakeRepository())),
    );
    await tester.pump();

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Enter barcode manually'));
    await tester.pumpAndSettle();

    expect(find.text('Enter Barcode'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Enter Barcode'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('POS manual entry adds repeated products up to available stock', (
    tester,
  ) async {
    MobileScannerPlatform.instance = _FakeMobileScannerPlatform();
    final now = DateTime(2026, 8, 14);
    final product = Product(
      id: 'product-1',
      barcode: 'COKE001',
      name: 'Coca-Cola',
      price: 75,
      category: 'Beverages',
      description: '',
      quantity: 2,
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      StockLensApp(
        productService: ProductService(_FakeRepository(product: product)),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('POS'));
    await tester.pumpAndSettle();
    final input = find.widgetWithText(TextField, 'Barcode / SKU');
    await tester.enterText(input, 'COKE001');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(input, 'COKE001');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Coca-Cola'), findsOneWidget);
    expect(find.text('₱75.00 × 2'), findsOneWidget);
    expect(find.text('₱150.00'), findsWidgets);

    await tester.enterText(input, 'COKE001');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Only 2 units are currently available.'), findsOneWidget);
  });

  testWidgets('Scan and POS serialize ownership of the camera', (tester) async {
    final scannerPlatform = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = scannerPlatform;
    await tester.pumpWidget(
      StockLensApp(productService: ProductService(_FakeRepository())),
    );
    await tester.pump();

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Scan Barcode'), findsOneWidget);
    expect(scannerPlatform.isRunning, isTrue);

    await tester.tap(find.text('POS'));
    await tester.pumpAndSettle();
    expect(find.text('Point of Sale'), findsOneWidget);
    expect(scannerPlatform.isRunning, isTrue);

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Scan Barcode'), findsOneWidget);
    expect(scannerPlatform.isRunning, isTrue);
    expect(scannerPlatform.startCalls, 3);
    expect(scannerPlatform.stopCalls, 2);
    expect(scannerPlatform.overlappingStarts, 0);
  });
}
