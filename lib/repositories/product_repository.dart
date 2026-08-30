import '../models/product.dart';
import '../models/stock_transaction.dart';

enum ProductSort {
  nameAsc,
  nameDesc,
  priceAsc,
  priceDesc,
  stockAsc,
  stockDesc,
  newest,
}

abstract interface class ProductRepository {
  Future<void> initialize();
  Future<List<Product>> getProducts({
    String query,
    String? category,
    ProductSort sort,
  });
  Future<List<Product>> getArchivedProducts({String query});
  Future<List<Product>> getLowStockProducts();
  Future<Product?> getById(String id);
  Future<Product?> getByBarcode(String barcode);
  Future<List<String>> getCategories();
  Future<void> add(Product product);
  Future<void> update(Product product);
  Future<Product> adjustStock({
    required String productId,
    required int delta,
    required String reason,
    required String note,
    String source = 'manual',
    String? sourceId,
  });
  Future<void> setLowStockNotified(String productId, bool value);
  Future<List<StockTransaction>> getStockTransactions(String productId);
  Future<Product> setArchived(String productId, {required bool archived});
  Future<void> deletePermanently(String productId);
  Future<Map<String, Object?>> createBackup();
  Future<void> restoreBackup(Map<String, Object?> backup);
}

class StockCannotBeNegativeException implements Exception {
  const StockCannotBeNegativeException();
  @override
  String toString() => 'Stock cannot be negative.';
}

class DuplicateBarcodeException implements Exception {
  const DuplicateBarcodeException();
  @override
  String toString() => 'Barcode already exists.';
}

class ProductReferencedByInProgressStocktakeException implements Exception {
  const ProductReferencedByInProgressStocktakeException();
  @override
  String toString() => 'Product is referenced by an in-progress stocktake.';
}
