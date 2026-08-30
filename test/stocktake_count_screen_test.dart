import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stocklens/data/local/app_database.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/stocktake_session.dart';
import 'package:stocklens/repositories/local_product_repository.dart';
import 'package:stocklens/repositories/local_stocktake_repository.dart';
import 'package:stocklens/screens/stocktake/stocktake_count_screen.dart';
import 'package:stocklens/screens/stocktake/stocktake_scan_screen.dart';
import 'package:stocklens/screens/stocktake/stocktake_sessions_screen.dart';
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
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temporaryDirectory;
  late AppDatabase database;
  late LocalProductRepository products;
  late ProductService productService;
  late StocktakeService stocktakeService;
  late StocktakeSession session;

  Future<void> addProduct(
    String id,
    String barcode,
    String name,
    int quantity,
  ) {
    final now = DateTime.utc(2026, 8, 19);
    return products.add(
      Product(
        id: id,
        barcode: barcode,
        name: name,
        sellingPrice: 20,
        category: 'Beverages',
        description: '',
        quantity: quantity,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'stocklens-stocktake-count-screen-',
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
    await addProduct('cola', '111', 'Cola', 10);
    await addProduct('water', '222', 'Water', 4);
    await addProduct('outside', '333', 'Outside product', 8);
    session = await stocktakeService.create(
      name: 'Morning count',
      productIds: const ['cola', 'water'],
      scopeDescription: 'Category: Beverages',
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  testWidgets('autosaves manual counts and confirms zero-fill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StocktakeCountScreen(
          stocktakeService: stocktakeService,
          productService: productService,
          sessionId: session.id,
        ),
      ),
    );
    await _waitFor(tester, () => find.text('Cola').evaluate().isNotEmpty);

    expect(find.text('0 counted'), findsOneWidget);
    expect(find.text('2 remaining'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('count-cola')), '7');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _waitFor(
      tester,
      () => find.text('1 remaining').evaluate().isNotEmpty,
    );

    final afterManualSave = await tester.runAsync(
      () => stocktakeService.session(session.id),
    );
    expect(
      afterManualSave!.items
          .singleWhere((item) => item.productId == 'cola')
          .countedQuantity,
      7,
    );
    expect(find.text('1 counted'), findsOneWidget);
    expect(find.text('Variance -3'), findsOneWidget);

    await tester.tap(find.text('Set remaining to zero'));
    await tester.pumpAndSettle();
    expect(find.text('Set 1 remaining item to zero?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Set to zero'));
    await _waitFor(
      tester,
      () => find.text('0 remaining').evaluate().isNotEmpty,
    );

    final zeroFilled = await tester.runAsync(
      () => stocktakeService.session(session.id),
    );
    expect(zeroFilled!.items.map((item) => item.countedQuantity), [7, 0]);
    expect(find.widgetWithText(FilledButton, 'Review changes'), findsOneWidget);
  });

  testWidgets('scanner cools down duplicates and rejects out-of-scope codes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StocktakeScanScreen(
          stocktakeService: stocktakeService,
          sessionId: session.id,
          scannerBuilder: (onBarcode) => Column(
            children: [
              FilledButton(
                onPressed: () => onBarcode('111'),
                child: const Text('Scan cola'),
              ),
              FilledButton(
                onPressed: () => onBarcode('333'),
                child: const Text('Scan outside'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Scan cola'));
    await _waitFor(tester, () => find.text('Counted 1').evaluate().isNotEmpty);
    await tester.tap(find.text('Scan cola'));
    await tester.pump();

    final afterDuplicate = await tester.runAsync(
      () => stocktakeService.session(session.id),
    );
    expect(afterDuplicate!.items.first.countedQuantity, 1);

    await tester.tap(find.text('Scan outside'));
    await _waitFor(
      tester,
      () => find
          .text('This product is not part of this stocktake.')
          .evaluate()
          .isNotEmpty,
    );
    final afterOutside = await tester.runAsync(
      () => stocktakeService.session(session.id),
    );
    expect(afterOutside!.items.first.countedQuantity, 1);
  });

  testWidgets('session list opens an active count and resumes saved values', (
    tester,
  ) async {
    await tester.runAsync(
      () => stocktakeService.setCount(session.id, 'cola', 6),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StocktakeSessionsScreen(
          stocktakeService: stocktakeService,
          productService: productService,
        ),
      ),
    );
    await _waitFor(
      tester,
      () => find.text('Morning count').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Morning count'));
    await _waitFor(tester, () => find.text('Cola').evaluate().isNotEmpty);

    expect(find.byKey(const Key('count-cola')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('count-cola')))
          .controller!
          .text,
      '6',
    );
    expect(find.text('1 counted'), findsOneWidget);
  });
}
