import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/stock_transaction.dart';
import 'package:stocklens/repositories/product_repository.dart';
import 'package:stocklens/screens/alerts/low_stock_alerts_screen.dart';
import 'package:stocklens/services/product_service.dart';

void main() {
  testWidgets('shows alert products in the service order and opens details', (
    tester,
  ) async {
    final zeroProduct = product('zero', 'Zero Product', quantity: 0);
    final largestDeficit = product(
      'largest',
      'Largest Deficit',
      quantity: 1,
      threshold: 8,
    );
    final other = product('other', 'Other', quantity: 3, threshold: 5);
    final service = ProductService(
      _AlertsRepository(
        lowStockResponses: [
          [zeroProduct, largestDeficit, other],
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: LowStockAlertsScreen(service: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Out of stock'), findsOneWidget);
    expect(find.text('Low stock'), findsNWidgets(2));
    expect(
      productNames(tester),
      equals(['Zero Product', 'Largest Deficit', 'Other']),
    );

    await tester.tap(find.text('Zero Product'));
    await tester.pumpAndSettle();

    expect(find.text('Product Details'), findsOneWidget);
  });

  testWidgets('requests notification permission only after an explicit tap', (
    tester,
  ) async {
    var permissionRequests = 0;
    var settingsRequests = 0;
    final service = ProductService(
      _AlertsRepository(
        lowStockResponses: [
          [product('low', 'Low Product', quantity: 2)],
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LowStockAlertsScreen(
          service: service,
          onEnableNotifications: () async {
            permissionRequests++;
            return false;
          },
          onOpenNotificationSettings: () async {
            settingsRequests++;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(permissionRequests, 0);
    expect(find.text('Low Product'), findsOneWidget);

    await tester.tap(find.text('Enable notifications'));
    await tester.pumpAndSettle();

    expect(permissionRequests, 1);
    expect(find.text('Open settings'), findsOneWidget);
    expect(find.text('Low Product'), findsOneWidget);

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    expect(settingsRequests, 1);
    expect(find.text('Low Product'), findsOneWidget);
  });

  testWidgets(
    'permission callback failure offers notification settings recovery',
    (tester) async {
      final service = ProductService(
        _AlertsRepository(
          lowStockResponses: [
            [product('low', 'Low Product', quantity: 2)],
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LowStockAlertsScreen(
            service: service,
            onEnableNotifications: () async {
              throw StateError('permission service unavailable');
            },
            onOpenNotificationSettings: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enable notifications'));
      await tester.pumpAndSettle();

      expect(find.text('Open settings'), findsOneWidget);
      expect(find.text('Low Product'), findsOneWidget);
    },
  );

  testWidgets('screen opening checks status without requesting permission', (
    tester,
  ) async {
    var statusChecks = 0;
    var permissionRequests = 0;
    final service = ProductService(
      _AlertsRepository(
        lowStockResponses: [
          [product('low', 'Low Product', quantity: 2)],
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LowStockAlertsScreen(
          service: service,
          onNotificationsEnabled: () async {
            statusChecks++;
            return true;
          },
          onEnableNotifications: () async {
            permissionRequests++;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(statusChecks, 1);
    expect(permissionRequests, 0);
    expect(find.text('Enable notifications'), findsNothing);
    expect(find.text('Low Product'), findsOneWidget);
  });

  testWidgets('shows a retryable error and reloads the alert list', (
    tester,
  ) async {
    final service = ProductService(
      _AlertsRepository(
        lowStockResponses: [
          StateError('database unavailable'),
          [product('low', 'Recovered Product', quantity: 2)],
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: LowStockAlertsScreen(service: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load low-stock alerts.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Recovered Product'), findsOneWidget);
  });

  testWidgets('shows loading then an empty alert state', (tester) async {
    final pendingProducts = Completer<List<Product>>();
    final service = ProductService(
      _AlertsRepository(lowStockResponses: [pendingProducts.future]),
    );

    await tester.pumpWidget(
      MaterialApp(home: LowStockAlertsScreen(service: service)),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pendingProducts.complete([]);
    await tester.pumpAndSettle();

    expect(find.text('No low-stock products right now.'), findsOneWidget);
  });

  testWidgets('pulling to refresh reloads the alert list', (tester) async {
    final repository = _AlertsRepository(
      lowStockResponses: [
        [product('first', 'First Product', quantity: 2)],
        [product('second', 'Refreshed Product', quantity: 2)],
      ],
    );
    final service = ProductService(repository);

    await tester.pumpWidget(
      MaterialApp(home: LowStockAlertsScreen(service: service)),
    );
    await tester.pumpAndSettle();
    expect(find.text('First Product'), findsOneWidget);

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(repository.lowStockRequests, 2);
    expect(find.text('Refreshed Product'), findsOneWidget);
  });

  testWidgets('returning from Product Details reloads the alert list', (
    tester,
  ) async {
    final repository = _AlertsRepository(
      lowStockResponses: [
        [product('first', 'First Product', quantity: 2)],
        [product('second', 'After Details', quantity: 1)],
      ],
    );
    final service = ProductService(repository);

    await tester.pumpWidget(
      MaterialApp(home: LowStockAlertsScreen(service: service)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('First Product'));
    await tester.pumpAndSettle();
    expect(find.text('Product Details'), findsOneWidget);
    expect(repository.lowStockRequests, 1);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(repository.lowStockRequests, 2);
    expect(find.text('After Details'), findsOneWidget);
  });
}

List<String> productNames(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data)
    .whereType<String>()
    .where(
      (name) =>
          name == 'Zero Product' ||
          name == 'Largest Deficit' ||
          name == 'Other',
    )
    .toList();

Product product(
  String id,
  String name, {
  required int quantity,
  int threshold = 5,
}) => Product(
  id: id,
  barcode: '480$id',
  name: name,
  sellingPrice: 20,
  category: 'Test',
  description: '',
  quantity: quantity,
  lowStockThreshold: threshold,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _AlertsRepository implements ProductRepository {
  _AlertsRepository({required this.lowStockResponses});

  final List<Object> lowStockResponses;
  int lowStockRequests = 0;

  @override
  Future<List<Product>> getLowStockProducts() async {
    final response = lowStockResponses[lowStockRequests++];
    if (response is Future<List<Product>>) return response;
    if (response is List<Product>) return response;
    throw response;
  }

  @override
  Future<Product?> getById(String id) async {
    for (final response in lowStockResponses) {
      if (response is List<Product>) {
        for (final product in response) {
          if (product.id == id) return product;
        }
      }
    }
    return null;
  }

  @override
  Future<void> add(Product product) async {}
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
  Future<Map<String, Object?>> createBackup() async => const {};
  @override
  Future<void> deletePermanently(String productId) async {}
  @override
  Future<List<Product>> getArchivedProducts({String query = ''}) async => [];
  @override
  Future<Product?> getByBarcode(String barcode) async => null;
  @override
  Future<List<String>> getCategories() async => [];
  @override
  Future<List<Product>> getProducts({
    String query = '',
    String? category,
    ProductSort sort = ProductSort.nameAsc,
  }) async => [];
  @override
  Future<List<StockTransaction>> getStockTransactions(String productId) async =>
      [];
  @override
  Future<void> initialize() async {}
  @override
  Future<void> restoreBackup(Map<String, Object?> backup) async {}
  @override
  Future<void> setLowStockNotified(String productId, bool value) async {}
  @override
  Future<Product> setArchived(String productId, {required bool archived}) =>
      throw UnimplementedError();
  @override
  Future<void> update(Product product) async {}
}
