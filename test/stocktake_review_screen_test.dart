import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stocklens/data/local/app_database.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/stocktake_session.dart';
import 'package:stocklens/repositories/local_product_repository.dart';
import 'package:stocklens/repositories/local_stocktake_repository.dart';
import 'package:stocklens/screens/stocktake/stocktake_review_screen.dart';
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

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'stocklens-stocktake-review-screen-',
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
    session = await stocktakeService.create(
      name: 'Morning count',
      productIds: const ['cola'],
      scopeDescription: 'Category: Beverages',
    );
    await stocktakeService.setCount(session.id, 'cola', 7);
    await products.adjustStock(
      productId: 'cola',
      delta: -1,
      reason: 'Sale',
      note: '',
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<void> openReview(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StocktakeReviewScreen(
          stocktakeService: stocktakeService,
          productService: productService,
          sessionId: session.id,
        ),
      ),
    );
    await _waitFor(tester, () => find.text('Cola').evaluate().isNotEmpty);
  }

  testWidgets(
    'shows latest quantities, conflicts, and completes after confirmation',
    (tester) async {
      await openReview(tester);

      expect(find.text('Changed during count'), findsOneWidget);
      expect(find.text('Expected 10'), findsOneWidget);
      expect(find.text('Current 9'), findsOneWidget);
      expect(find.text('Counted 7'), findsOneWidget);
      expect(find.text('Variance -2'), findsOneWidget);

      await tester.tap(find.text('Complete stocktake'));
      await tester.pumpAndSettle();
      expect(find.text('Apply these inventory corrections?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Complete'));
      await _waitFor(
        tester,
        () => find.text('Stocktake completed').evaluate().isNotEmpty,
      );

      final completedProduct = await tester.runAsync(
        () => products.getById('cola'),
      );
      final completedSession = await tester.runAsync(
        () => stocktakeService.session(session.id),
      );
      expect(completedProduct!.quantity, 7);
      expect(completedSession!.status, StocktakeStatus.completed);
    },
  );

  testWidgets('keeps the session open and reloads a stale completion preview', (
    tester,
  ) async {
    await openReview(tester);
    await tester.runAsync(
      () => products.adjustStock(
        productId: 'cola',
        delta: -1,
        reason: 'Sale',
        note: '',
      ),
    );

    await tester.tap(find.text('Complete stocktake'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Complete'));
    await _waitFor(
      tester,
      () => find
          .text('Inventory changed again. Review the latest quantities.')
          .evaluate()
          .isNotEmpty,
    );

    final staleSession = await tester.runAsync(
      () => stocktakeService.session(session.id),
    );
    expect(staleSession!.status, StocktakeStatus.inProgress);
    expect(find.text('Current 8'), findsOneWidget);
    expect(find.text('Variance -1'), findsOneWidget);
  });
}
