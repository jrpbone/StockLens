import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/sale_order.dart';
import 'package:stocklens/models/stock_transaction.dart';
import 'package:stocklens/repositories/product_repository.dart';
import 'package:stocklens/screens/product_details/product_details_screen.dart';
import 'package:stocklens/services/product_service.dart';

void main() {
  testWidgets('shows product pricing and inventory valuation', (tester) async {
    final product = Product(
      id: 'product-1',
      barcode: '123',
      name: 'Coffee',
      sellingPrice: 20,
      costPrice: 12,
      lowStockThreshold: 3,
      category: 'Drinks',
      description: '',
      quantity: 4,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final service = ProductService(_ProductRepository(product));

    await tester.pumpWidget(
      MaterialApp(
        home: ProductDetailsScreen(service: service, productId: product.id),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selling Price'), findsOneWidget);
    expect(find.text('Cost Price'), findsOneWidget);
    expect(find.text('Unit Margin'), findsOneWidget);
    expect(find.text('Current Cost Value'), findsOneWidget);
    expect(find.text('Potential Retail Value'), findsOneWidget);
    expect(find.text('₱20.00'), findsNWidgets(2));
    expect(find.text('₱12.00'), findsOneWidget);
    expect(find.text('₱8.00'), findsOneWidget);
    expect(find.text('₱48.00'), findsOneWidget);
    expect(find.text('₱80.00'), findsOneWidget);
  });
}

class _ProductRepository implements ProductRepository {
  _ProductRepository(this.product);

  final Product product;

  @override
  Future<void> add(Product product) async {}
  @override
  Future<SaleOrder> completeSale(List<SaleRequestItem> items) =>
      throw UnimplementedError();

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
  Future<List<SaleOrder>> getOrders() async => [];

  @override
  Future<List<Product>> getLowStockProducts() async => [];

  @override
  Future<Product?> getByBarcode(String barcode) async => null;

  @override
  Future<Product?> getById(String id) async =>
      product.id == id ? product : null;

  @override
  Future<List<String>> getCategories() async => [];

  @override
  Future<List<Product>> getProducts({
    String query = '',
    String? category,
    ProductSort sort = ProductSort.nameAsc,
  }) async => [product];

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
