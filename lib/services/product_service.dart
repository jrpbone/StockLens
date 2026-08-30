import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../models/stock_transaction.dart';
import '../repositories/product_repository.dart';
import 'low_stock_notification_service.dart';
import 'product_image_storage.dart';

class ProductService {
  ProductService(
    this._repository, {
    ProductImageStorage? imageStorage,
    this.lowStockNotifications,
  }) : _imageStorage = imageStorage ?? LocalProductImageStorage();
  final ProductRepository _repository;
  final ProductImageStorage _imageStorage;
  final LowStockNotificationService? lowStockNotifications;

  Future<void> initialize() => _repository.initialize();
  Future<List<Product>> products({
    String query = '',
    String? category,
    ProductSort sort = ProductSort.nameAsc,
  }) => _repository.getProducts(query: query, category: category, sort: sort);
  Future<List<Product>> lowStockProducts() => _repository.getLowStockProducts();
  Future<Product?> byId(String id) => _repository.getById(id);
  Future<Product?> byBarcode(String barcode) =>
      _repository.getByBarcode(barcode);
  Future<List<String>> categories() => _repository.getCategories();
  Future<List<Product>> archivedProducts({String query = ''}) =>
      _repository.getArchivedProducts(query: query);
  Future<List<StockTransaction>> stockTransactions(String productId) =>
      _repository.getStockTransactions(productId);

  Future<Product> add({
    required String barcode,
    required String name,
    double? sellingPrice,
    double? price,
    double costPrice = 0,
    int lowStockThreshold = 5,
    required String category,
    required int quantity,
    required String description,
    String? imagePath,
  }) async {
    final resolvedSellingPrice = sellingPrice ?? price;
    if (resolvedSellingPrice == null) {
      throw ArgumentError.notNull('sellingPrice');
    }
    _validatePricing(
      sellingPrice: resolvedSellingPrice,
      costPrice: costPrice,
      lowStockThreshold: lowStockThreshold,
    );
    final now = DateTime.now();
    final permanentImage = await _imageStorage.persist(imagePath);
    final product = Product(
      id: const Uuid().v4(),
      barcode: barcode.trim(),
      name: name.trim(),
      sellingPrice: resolvedSellingPrice,
      costPrice: costPrice,
      lowStockThreshold: lowStockThreshold,
      category: category.trim().isEmpty ? 'Uncategorized' : category.trim(),
      description: description.trim(),
      quantity: quantity,
      imagePath: permanentImage,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await _repository.add(product);
    } catch (_) {
      if (permanentImage != imagePath) {
        await _imageStorage.delete(permanentImage);
      }
      rethrow;
    }
    await lowStockNotifications?.evaluate(after: product);
    return product;
  }

  Future<Product> update(Product product) async {
    _validatePricing(
      sellingPrice: product.sellingPrice,
      costPrice: product.costPrice,
      lowStockThreshold: product.lowStockThreshold,
    );
    final current = await _repository.getById(product.id);
    if (current == null) throw StateError('Product not found.');
    final permanentImage = await _imageStorage.persist(product.imagePath);
    final updated = product.copyWith(
      quantity: current.quantity,
      lowStockNotified: current.lowStockNotified,
      imagePath: permanentImage,
      updatedAt: DateTime.now(),
    );
    try {
      await _repository.update(updated);
    } catch (_) {
      if (permanentImage != product.imagePath) {
        await _imageStorage.delete(permanentImage);
      }
      rethrow;
    }
    await lowStockNotifications?.evaluate(before: current, after: updated);
    if (current.imagePath != permanentImage) {
      try {
        await _imageStorage.delete(current.imagePath);
      } catch (_) {
        // The update has committed; stale-image cleanup is best effort.
      }
    }
    return updated;
  }

  Future<Product> adjustStock(
    Product product,
    int delta, {
    required String reason,
    String note = '',
    String source = 'manual',
    String? sourceId,
  }) async {
    final before = await _repository.getById(product.id);
    final adjusted = await _repository.adjustStock(
      productId: product.id,
      delta: delta,
      reason: reason,
      note: note,
      source: source,
      sourceId: sourceId,
    );
    await lowStockNotifications?.evaluate(before: before, after: adjusted);
    return adjusted;
  }

  Future<void> setLowStockNotified(String productId, bool value) =>
      _repository.setLowStockNotified(productId, value);

  Future<Product> archive(Product product) =>
      _setArchived(product, archived: true);

  Future<Product> restore(Product product) =>
      _setArchived(product, archived: false);

  Future<Product> _setArchived(
    Product product, {
    required bool archived,
  }) async {
    final before = await _repository.getById(product.id);
    if (before == null) throw StateError('Product not found.');
    final after = await _repository.setArchived(product.id, archived: archived);
    await lowStockNotifications?.evaluate(before: before, after: after);
    return after;
  }

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
        'selling_price',
        'cost_price',
        'low_stock_threshold',
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
            product['cost_price'],
            product['low_stock_threshold'],
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

  void _validatePricing({
    required double sellingPrice,
    required double costPrice,
    required int lowStockThreshold,
  }) {
    if (!sellingPrice.isFinite || sellingPrice < 0) {
      throw ArgumentError.value(
        sellingPrice,
        'sellingPrice',
        'Selling price must be finite and nonnegative.',
      );
    }
    if (!costPrice.isFinite || costPrice < 0) {
      throw ArgumentError.value(
        costPrice,
        'costPrice',
        'Cost price must be finite and nonnegative.',
      );
    }
    if (lowStockThreshold < 0) {
      throw ArgumentError.value(
        lowStockThreshold,
        'lowStockThreshold',
        'Low-stock threshold cannot be negative.',
      );
    }
  }
}
