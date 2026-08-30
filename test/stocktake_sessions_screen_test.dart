import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stocklens/app.dart';
import 'package:stocklens/data/local/app_database.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/stocktake_item.dart';
import 'package:stocklens/models/stocktake_session.dart';
import 'package:stocklens/repositories/local_product_repository.dart';
import 'package:stocklens/repositories/local_stocktake_repository.dart';
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
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temporaryDirectory;
  late AppDatabase database;
  late LocalProductRepository products;
  late LocalStocktakeRepository stocktakes;
  late ProductService productService;
  late StocktakeService stocktakeService;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'stocklens-stocktake-sessions-screen-',
    );
    database = AppDatabase.forTesting(
      '${temporaryDirectory.path}${Platform.pathSeparator}stocklens.db',
    );
    products = LocalProductRepository(database);
    stocktakes = LocalStocktakeRepository(database);
    productService = ProductService(products);
    stocktakeService = StocktakeService(
      stocktakes,
      products,
      lowStockNotifications: LowStockNotificationService(
        products,
        gateway: _NoopGateway(),
      ),
    );
    final now = DateTime.utc(2026, 8, 19);
    await products.add(
      Product(
        id: 'cola',
        barcode: '111',
        name: 'Cola',
        sellingPrice: 20,
        category: 'Beverages',
        description: '',
        quantity: 10,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await stocktakes.create(
      StocktakeSession(
        id: 'active-session',
        name: 'Morning count',
        status: StocktakeStatus.inProgress,
        scopeDescription: 'All active products',
        notes: '',
        createdAt: now,
      ),
      [
        StocktakeItem(
          sessionId: 'active-session',
          productId: 'cola',
          expectedQuantity: 10,
          updatedAt: now,
        ),
      ],
    );
    await stocktakes.create(
      StocktakeSession(
        id: 'completed-session',
        name: 'Previous count',
        status: StocktakeStatus.completed,
        scopeDescription: 'Category: Beverages',
        notes: '',
        createdAt: now.subtract(const Duration(days: 1)),
        completedAt: now,
      ),
      [
        StocktakeItem(
          sessionId: 'completed-session',
          productId: 'cola',
          expectedQuantity: 10,
          countedQuantity: 10,
          updatedAt: now,
        ),
      ],
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  testWidgets('shows in-progress and completed sessions and opens a session', (
    tester,
  ) async {
    String? openedSessionId;
    await tester.pumpWidget(
      MaterialApp(
        home: StocktakeSessionsScreen(
          stocktakeService: stocktakeService,
          productService: productService,
          onOpenSession: (session) async {
            openedSessionId = session.id;
          },
        ),
      ),
    );
    await _waitFor(
      tester,
      () => find.text('Morning count').evaluate().isNotEmpty,
    );

    expect(find.text('Stocktake'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Morning count'), findsOneWidget);
    expect(find.text('Previous count'), findsOneWidget);

    await tester.tap(find.text('Morning count'));
    await _waitFor(tester, () => openedSessionId != null);

    expect(openedSessionId, 'active-session');
  });

  testWidgets('opens Stocktake from the Inventory app bar', (tester) async {
    await tester.pumpWidget(
      StockLensApp(
        productService: productService,
        stocktakeService: stocktakeService,
      ),
    );
    await _waitFor(tester, () => find.text('StockLens').evaluate().isNotEmpty);

    await tester.tap(find.text('Inventory').last);
    await _waitFor(
      tester,
      () => find.byTooltip('Stocktake').evaluate().isNotEmpty,
    );
    await tester.tap(find.byTooltip('Stocktake'));
    await _waitFor(
      tester,
      () => find.text('Morning count').evaluate().isNotEmpty,
    );

    expect(find.text('Stocktake'), findsOneWidget);
    expect(find.text('Morning count'), findsOneWidget);
    expect(find.text('Previous count'), findsOneWidget);
  });
}
