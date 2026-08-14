import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../models/pos_cart_item.dart';
import '../models/sale_order.dart';
import '../models/stock_transaction.dart';
import '../repositories/product_repository.dart';
import 'product_image_storage.dart';

class ProductService {
  ProductService(this._repository, {ProductImageStorage? imageStorage})
    : _imageStorage = imageStorage ?? LocalProductImageStorage();
  final ProductRepository _repository;
  final ProductImageStorage _imageStorage;

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
  Future<List<Product>> archivedProducts({String query = ''}) =>
      _repository.getArchivedProducts(query: query);
  Future<List<StockTransaction>> stockTransactions(String productId) =>
      _repository.getStockTransactions(productId);
  Future<List<SaleOrder>> orders() => _repository.getOrders();

  Future<List<PosCartItem>> revalidateSale(List<PosCartItem> cart) async {
    if (cart.isEmpty) throw const EmptySaleException();
    final refreshed = <PosCartItem>[];
    for (final item in cart) {
      final product = await _repository.getById(item.productId);
      if (product == null || product.archivedAt != null) {
        throw ProductMissingForSaleException(item.productId);
      }
      if (!product.price.isFinite || product.price < 0) {
        throw InvalidProductPriceException(product.name);
      }
      if (product.quantity < item.quantity) {
        throw ProductUnavailableException(product.name, product.quantity);
      }
      refreshed.add(PosCartItem.fromProduct(product, quantity: item.quantity));
    }
    return refreshed;
  }

  Future<SaleOrder> completeSale(List<PosCartItem> cart) =>
      _repository.completeSale([
        for (final item in cart)
          SaleRequestItem(productId: item.productId, quantity: item.quantity),
      ]);

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
    final permanentImage = await _imageStorage.persist(imagePath);
    final product = Product(
      id: const Uuid().v4(),
      barcode: barcode.trim(),
      name: name.trim(),
      price: price,
      category: category.trim().isEmpty ? 'Uncategorized' : category.trim(),
      description: description.trim(),
      quantity: quantity,
      imagePath: permanentImage,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await _repository.add(product);
      return product;
    } catch (_) {
      if (permanentImage != imagePath) {
        await _imageStorage.delete(permanentImage);
      }
      rethrow;
    }
  }

  Future<Product> update(Product product) async {
    final current = await _repository.getById(product.id);
    if (current == null) throw StateError('Product not found.');
    final permanentImage = await _imageStorage.persist(product.imagePath);
    final updated = product.copyWith(
      quantity: current.quantity,
      imagePath: permanentImage,
      updatedAt: DateTime.now(),
    );
    try {
      await _repository.update(updated);
      if (current.imagePath != permanentImage) {
        await _imageStorage.delete(current.imagePath);
      }
      return updated;
    } catch (_) {
      if (permanentImage != product.imagePath) {
        await _imageStorage.delete(permanentImage);
      }
      rethrow;
    }
  }

  Future<Product> adjustStock(
    Product product,
    int delta, {
    required String reason,
    String note = '',
  }) => _repository.adjustStock(
    productId: product.id,
    delta: delta,
    reason: reason,
    note: note,
  );

  Future<Product> archive(Product product) =>
      _repository.setArchived(product.id, archived: true);

  Future<Product> restore(Product product) =>
      _repository.setArchived(product.id, archived: false);

  Future<void> deletePermanently(Product product) async {
    await _repository.deletePermanently(product.id);
    try {
      await _imageStorage.delete(product.imagePath);
    } catch (_) {
      // The database deletion has committed; stale-image cleanup is best effort.
    }
  }

  Future<Map<String, Object?>> createBackup() async {
    final backup = await _repository.createBackup();
    final rawProducts = backup['products']! as List;
    final portableProducts = <Map<String, Object?>>[];
    for (final value in rawProducts) {
      final product = Map<String, Object?>.from(value as Map);
      final imagePath = product['image_path'] as String?;
      product['image_path'] = null;
      if (imagePath != null) {
        final file = File(imagePath);
        if (await file.exists()) {
          product['image_extension'] = p.extension(imagePath);
          product['image_data_base64'] = base64Encode(await file.readAsBytes());
        }
      }
      portableProducts.add(product);
    }
    return {...backup, 'products': portableProducts};
  }

  Future<void> restoreBackup(Map<String, Object?> backup) async {
    final current = await _repository.createBackup();
    final currentImagePaths = (current['products']! as List)
        .map((value) => Map<String, Object?>.from(value as Map)['image_path'])
        .whereType<String>()
        .toList();
    final restoredImagePaths = <String>[];
    final rawProducts = backup['products'];
    if (rawProducts is! List) {
      throw const FormatException('Backup does not contain products.');
    }
    final restoredProducts = <Map<String, Object?>>[];
    try {
      for (final value in rawProducts) {
        if (value is! Map) throw const FormatException('Invalid product data.');
        final product = Map<String, Object?>.from(value);
        product['image_path'] = null;
        final encoded = product.remove('image_data_base64');
        final extension = product.remove('image_extension');
        if (encoded is String && encoded.isNotEmpty) {
          final imagePath = await _imageStorage.persistBytes(
            base64Decode(encoded),
            extension: extension is String ? extension : '.img',
          );
          restoredImagePaths.add(imagePath);
          product['image_path'] = imagePath;
        }
        restoredProducts.add(product);
      }
      await _repository.restoreBackup({
        ...backup,
        'products': restoredProducts,
      });
    } catch (_) {
      for (final imagePath in restoredImagePaths) {
        await _imageStorage.delete(imagePath);
      }
      rethrow;
    }
    for (final imagePath in currentImagePaths) {
      try {
        await _imageStorage.delete(imagePath);
      } catch (_) {
        // Restore has committed; an orphan is safer than deleting restored data.
      }
    }
  }

  Future<String> inventoryCsv() async {
    final backup = await _repository.createBackup();
    final rows = <List<Object?>>[
      [
        'barcode',
        'name',
        'price',
        'category',
        'quantity',
        'status',
        'description',
      ],
      for (final value in backup['products']! as List)
        (() {
          final product = Map<String, Object?>.from(value as Map);
          return [
            product['barcode'],
            product['name'],
            product['price'],
            product['category'],
            product['quantity'],
            product['archived_at'] == null ? 'active' : 'archived',
            product['description'],
          ];
        })(),
    ];
    return rows.map((row) => row.map(_csvCell).join(',')).join('\r\n');
  }

  String _csvCell(Object? value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }
}
