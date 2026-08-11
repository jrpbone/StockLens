import '../models/product.dart';

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
  Future<Product?> getById(String id);
  Future<Product?> getByBarcode(String barcode);
  Future<List<String>> getCategories();
  Future<void> add(Product product);
  Future<void> update(Product product);
}

class DuplicateBarcodeException implements Exception {
  const DuplicateBarcodeException();
  @override
  String toString() => 'Barcode already exists.';
}
