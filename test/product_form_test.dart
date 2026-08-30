import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/stock_transaction.dart';
import 'package:stocklens/repositories/product_repository.dart';
import 'package:stocklens/screens/add_product/product_form.dart';
import 'package:stocklens/services/product_service.dart';

void main() {
  testWidgets('shows pricing and threshold fields and validates cost price', (
    tester,
  ) async {
    final service = ProductService(_ProductRepository());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProductForm(service: service)),
      ),
    );

    expect(find.byKey(const Key('selling-price-field')), findsOneWidget);
    expect(find.byKey(const Key('cost-price-field')), findsOneWidget);
    expect(find.byKey(const Key('low-stock-threshold-field')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('cost-price-field')), '-1');
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pump();
    await tester.tap(find.text('Save Product'));
    await tester.pump();

    expect(find.text('Enter a valid cost price of 0 or more.'), findsOneWidget);
  });
}

class _ProductRepository implements ProductRepository {
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
  Future<List<Product>> getLowStockProducts() async => [];

  @override
  Future<Product?> getByBarcode(String barcode) async => null;

  @override
  Future<Product?> getById(String id) async => null;

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
  Future<Product> setArchived(String productId, {required bool archived}) =>
      throw UnimplementedError();

  @override
  Future<void> setLowStockNotified(String productId, bool value) async {}

  @override
  Future<void> update(Product product) async {}
}
