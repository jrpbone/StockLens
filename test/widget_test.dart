import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/app.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/stock_transaction.dart';
import 'package:stocklens/repositories/product_repository.dart';
import 'package:stocklens/services/product_service.dart';

class _FakeRepository implements ProductRepository {
  _FakeRepository({this.products = const []});

  final List<Product> products;
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
  Future<Map<String, Object?>> createBackup() async => {
    'format': 'stocklens-backup',
    'schema_version': 1,
    'products': <Object?>[],
    'stock_transactions': <Object?>[],
  };
  @override
  Future<List<Product>> getArchivedProducts({String query = ''}) async => [];
  @override
  Future<List<Product>> getLowStockProducts() async =>
      products.where((product) => product.isLowStock).toList();
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
  }) async => products;
}

class _ReloadingRepository extends _FakeRepository {
  _ReloadingRepository(this.productResponses);

  final List<List<Product>> productResponses;
  int productRequests = 0;
  List<Product> _latestProducts = const [];

  @override
  Future<List<Product>> getProducts({
    String query = '',
    String? category,
    ProductSort sort = ProductSort.nameAsc,
  }) async {
    _latestProducts = productResponses[productRequests++];
    return _latestProducts;
  }

  @override
  Future<List<Product>> getLowStockProducts() async =>
      _latestProducts.where((product) => product.isLowStock).toList();
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

  testWidgets(
    'uses product thresholds for the tappable low-stock dashboard card',
    (tester) async {
      final products = [
        _product('low', 'Threshold-qualified', quantity: 6, threshold: 6),
        _product('out', 'No stock', quantity: 0, threshold: 3),
        _product('healthy', 'Healthy', quantity: 5, threshold: 4),
      ];
      await tester.pumpWidget(
        StockLensApp(
          productService: ProductService(_FakeRepository(products: products)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);
      expect(find.text('Out of stock'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.text('Low stock'));
      await tester.pumpAndSettle();

      expect(find.text('Low-stock alerts'), findsOneWidget);
      expect(find.text('Threshold-qualified'), findsOneWidget);
    },
  );

  testWidgets('returning from the alert center reloads the dashboard', (
    tester,
  ) async {
    final repository = _ReloadingRepository([
      [_product('low', 'Low product', quantity: 2, threshold: 5)],
      [_product('healthy', 'Healthy product', quantity: 6, threshold: 5)],
    ]);

    await tester.pumpWidget(
      StockLensApp(productService: ProductService(repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Low stock'));
    await tester.pumpAndSettle();
    expect(find.text('Low-stock alerts'), findsOneWidget);
    expect(repository.productRequests, 1);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(repository.productRequests, 2);
  });
}

Product _product(
  String id,
  String name, {
  required int quantity,
  required int threshold,
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
