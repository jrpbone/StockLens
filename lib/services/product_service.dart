import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../repositories/product_repository.dart';

class ProductService {
  ProductService(this._repository);
  final ProductRepository _repository;

  Future<void> initialize() => _repository.initialize();
  Future<List<Product>> products({
    String query = '',
    String? category,
    ProductSort sort = ProductSort.nameAsc,
  }) => _repository.getProducts(query: query, category: category, sort: sort);
  Future<Product?> byId(String id) => _repository.getById(id);
  Future<Product?> byBarcode(String barcode) =>
      _repository.getByBarcode(barcode);
  Future<List<String>> categories() => _repository.getCategories();

  Future<Product> add({
    required String barcode,
    required String name,
    required double price,
    required String category,
    required int quantity,
    required String description,
    String? imagePath,
  }) async {
    final now = DateTime.now();
    final product = Product(
      id: const Uuid().v4(),
      barcode: barcode.trim(),
      name: name.trim(),
      price: price,
      category: category.trim().isEmpty ? 'Uncategorized' : category.trim(),
      description: description.trim(),
      quantity: quantity,
      imagePath: imagePath,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.add(product);
    return product;
  }

  Future<Product> update(Product product) async {
    final updated = product.copyWith(updatedAt: DateTime.now());
    await _repository.update(updated);
    return updated;
  }

  Future<Product> adjustStock(Product product, int delta) {
    final quantity = product.quantity + delta;
    if (quantity < 0) throw ArgumentError('Stock cannot be negative.');
    return update(product.copyWith(quantity: quantity));
  }
}
