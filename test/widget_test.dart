import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/app.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/repositories/product_repository.dart';
import 'package:stocklens/services/product_service.dart';

class _FakeRepository implements ProductRepository {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> add(Product product) async {}
  @override
  Future<void> update(Product product) async {}
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
}
