import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/app.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/stock_transaction.dart';
import 'package:stocklens/repositories/product_repository.dart';
import 'package:stocklens/services/product_service.dart';

void main() {
  testWidgets('opens Product Details for an available notification product', (
    tester,
  ) async {
    final product = Product(
      id: 'product-1',
      barcode: '4801234567890',
      name: 'Coffee',
      sellingPrice: 20,
      category: 'Drinks',
      description: '',
      quantity: 3,
      lowStockThreshold: 5,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final service = ProductService(_ProductRepository(product));
    final navigationController = AppNavigationController(
      productService: service,
    );

    await tester.pumpWidget(
      StockLensApp(
        productService: service,
        navigationController: navigationController,
      ),
    );
    await tester.pumpAndSettle();

    navigationController.openLowStockProduct('product-1');
    await tester.pumpAndSettle();

    expect(find.text('Product Details'), findsOneWidget);
  });

  testWidgets('opens a queued payload after the app navigator is ready', (
    tester,
  ) async {
    final product = Product(
      id: 'product-1',
      barcode: '4801234567890',
      name: 'Coffee',
      sellingPrice: 20,
      category: 'Drinks',
      description: '',
      quantity: 3,
      lowStockThreshold: 5,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final service = ProductService(_ProductRepository(product));
    final navigationController = AppNavigationController(
      productService: service,
    );

    await navigationController.openLowStockProduct(product.id);
    await tester.pumpWidget(
      StockLensApp(
        productService: service,
        navigationController: navigationController,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Product Details'), findsOneWidget);
  });

  testWidgets('opens the alert center for a missing notification product', (
    tester,
  ) async {
    final service = ProductService(_ProductRepository(null));
    final navigationController = AppNavigationController(
      productService: service,
    );

    await tester.pumpWidget(
      StockLensApp(
        productService: service,
        navigationController: navigationController,
      ),
    );
    await tester.pumpAndSettle();

    await navigationController.openLowStockProduct('deleted-product');
    await tester.pumpAndSettle();

    expect(find.text('Low-stock alerts'), findsOneWidget);
    expect(find.text('No low-stock products right now.'), findsOneWidget);
  });

  testWidgets('does not request notification permission during app startup', (
    tester,
  ) async {
    var permissionRequests = 0;
    final service = ProductService(_ProductRepository(null));

    await tester.pumpWidget(
      StockLensApp(
        productService: service,
        requestLowStockNotificationPermission: () async {
          permissionRequests++;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(permissionRequests, 0);
  });

  testWidgets('forwards the permission hook only after alert-center action', (
    tester,
  ) async {
    var permissionRequests = 0;
    final service = ProductService(_ProductRepository(null));
    final navigationController = AppNavigationController(
      productService: service,
    );

    await tester.pumpWidget(
      StockLensApp(
        productService: service,
        navigationController: navigationController,
        requestLowStockNotificationPermission: () async {
          permissionRequests++;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    navigationController.openLowStockAlertCenter();
    await tester.pumpAndSettle();
    expect(permissionRequests, 0);

    await tester.tap(find.text('Enable notifications'));
    await tester.pumpAndSettle();

    expect(permissionRequests, 1);
  });

  testWidgets('forwards notification status and settings recovery hooks', (
    tester,
  ) async {
    var permissionRequests = 0;
    var statusChecks = 0;
    var settingsRequests = 0;
    final service = ProductService(_ProductRepository(null));
    final navigationController = AppNavigationController(
      productService: service,
    );

    await tester.pumpWidget(
      StockLensApp(
        productService: service,
        navigationController: navigationController,
        requestLowStockNotificationPermission: () async {
          permissionRequests++;
          return false;
        },
        lowStockNotificationsEnabled: () async {
          statusChecks++;
          return false;
        },
        openLowStockNotificationSettings: () async {
          settingsRequests++;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    navigationController.openLowStockAlertCenter();
    await tester.pumpAndSettle();

    expect(statusChecks, 1);
    expect(permissionRequests, 0);
    expect(find.text('Open settings'), findsOneWidget);

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    expect(settingsRequests, 1);
    expect(find.text('No low-stock products right now.'), findsOneWidget);
  });
}

class _ProductRepository implements ProductRepository {
  _ProductRepository(this.product);

  final Product? product;

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
  Future<Product?> getById(String id) async =>
      product?.id == id ? product : null;

  @override
  Future<List<String>> getCategories() async => [];

  @override
  Future<List<Product>> getProducts({
    String query = '',
    String? category,
    ProductSort sort = ProductSort.nameAsc,
  }) async => product == null ? [] : [product!];

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
