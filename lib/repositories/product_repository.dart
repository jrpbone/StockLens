import '../models/product.dart';
import '../models/sale_order.dart';
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
  });
  Future<List<StockTransaction>> getStockTransactions(String productId);
  Future<SaleOrder> completeSale(List<SaleRequestItem> items);
  Future<List<SaleOrder>> getOrders();
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

class EmptySaleException implements Exception {
  const EmptySaleException();
  @override
  String toString() => 'A sale must contain at least one item.';
}

class ProductUnavailableException implements Exception {
  const ProductUnavailableException(this.productName, this.availableStock);

  final String productName;
  final int availableStock;

  @override
  String toString() =>
      'Insufficient stock for $productName. Available stock: $availableStock.';
}

class ProductMissingForSaleException implements Exception {
  const ProductMissingForSaleException(this.productId);

  final String productId;

  @override
  String toString() => 'A product in this sale is no longer available.';
}

class InvalidProductPriceException implements Exception {
  const InvalidProductPriceException(this.productName);

  final String productName;

  @override
  String toString() => '$productName has an invalid price.';
}
