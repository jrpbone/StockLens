import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stocklens/data/local/app_database.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/stocktake_session.dart';
import 'package:stocklens/repositories/local_product_repository.dart';
import 'package:stocklens/repositories/local_stocktake_repository.dart';
import 'package:stocklens/screens/stocktake/create_stocktake_screen.dart';
import 'package:stocklens/services/low_stock_notification_service.dart';
import 'package:stocklens/services/product_service.dart';
import 'package:stocklens/services/stocktake_service.dart';

class _NoopGateway implements LowStockNotificationGateway {
  @override
  Future<void> showLowStock(Product product) async {}
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 30 && !condition(); attempt++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _addProduct(
  LocalProductRepository products,
  String id,
  String barcode,
  String name,
  String category,
) async {
  final now = DateTime.utc(2026, 8, 19);
  await products.add(
    Product(
      id: id,
      barcode: barcode,
      name: name,
      sellingPrice: 20,
      category: category,
      description: '',
      quantity: 10,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temporaryDirectory;
  late AppDatabase database;
  late LocalProductRepository products;
  late ProductService productService;
  late StocktakeService stocktakeService;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'stocklens-create-stocktake-screen-',
    );
    database = AppDatabase.forTesting(
      '${temporaryDirectory.path}${Platform.pathSeparator}stocklens.db',
    );
    products = LocalProductRepository(database);
    productService = ProductService(products);
    stocktakeService = StocktakeService(
      LocalStocktakeRepository(database),
      products,
      lowStockNotifications: LowStockNotificationService(
        products,
        gateway: _NoopGateway(),
      ),
    );
    await _addProduct(products, 'cola', '111', 'Cola', 'Beverages');
    await _addProduct(products, 'water', '222', 'Water', 'Beverages');
    await _addProduct(products, 'rice', '333', 'Rice', 'Food');
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  testWidgets('creates a category-scoped stocktake', (tester) async {
    StocktakeSession? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await Navigator.push<StocktakeSession>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateStocktakeScreen(
                      stocktakeService: stocktakeService,
                      productService: productService,
                    ),
                  ),
                );
              },
              child: const Text('Open creator'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open creator'));
    await _waitFor(tester, () => find.text('Categories').evaluate().isNotEmpty);

    expect(find.text('3 products selected'), findsOneWidget);
    await tester.tap(find.text('Categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beverages'));
    await tester.pump();

    expect(find.text('2 products selected'), findsOneWidget);
    await tester.tap(find.text('Start Stocktake'));
    await _waitFor(tester, () => result != null);

    expect(result, isNotNull);
    expect(result!.name, 'Beverages count');
    expect(result!.scopeDescription, 'Category: Beverages');
    expect(result!.items.map((item) => item.productId), ['cola', 'water']);
  });

  testWidgets('supports individually selected product scope', (tester) async {
    StocktakeSession? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await Navigator.push<StocktakeSession>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateStocktakeScreen(
                      stocktakeService: stocktakeService,
                      productService: productService,
                    ),
                  ),
                );
              },
              child: const Text('Open creator'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open creator'));
    await _waitFor(tester, () => find.text('Products').evaluate().isNotEmpty);

    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cola'));
    await tester.pump();

    expect(find.text('1 product selected'), findsOneWidget);
    await tester.tap(find.text('Start Stocktake'));
    await _waitFor(tester, () => result != null);

    expect(result, isNotNull);
    expect(result!.name, 'Selected products count');
    expect(result!.scopeDescription, 'Selected products: 1');
    expect(result!.items.single.productId, 'cola');
  });
}
