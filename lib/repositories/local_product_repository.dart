import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/local/app_database.dart';
import '../models/product.dart';
import 'product_repository.dart';

class LocalProductRepository implements ProductRepository {
  LocalProductRepository(this._database);
  final AppDatabase _database;

  @override
  Future<void> initialize() async {
    final db = await _database.database;
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM products'),
        ) ??
        0;
    if (count != 0) return;
    final now = DateTime.now();
    final samples = [
      (
        '4801981111624',
        'Coca-Cola 1.5L',
        75.0,
        'Beverages',
        20,
        'Classic cola soft drink.',
      ),
      (
        '4807770274228',
        'Lucky Me Pancit Canton',
        18.0,
        'Food',
        50,
        'Instant stir-fried noodles.',
      ),
      (
        '4800016075030',
        'Safeguard Soap',
        45.0,
        'Personal Care',
        10,
        'Antibacterial bath soap.',
      ),
      (
        '748485102002',
        'Century Tuna',
        42.0,
        'Canned Goods',
        4,
        'Canned tuna flakes.',
      ),
    ];
    final batch = db.batch();
    for (final item in samples) {
      batch.insert(
        'products',
        Product(
          id: const Uuid().v4(),
          barcode: item.$1,
          name: item.$2,
          price: item.$3,
          category: item.$4,
          description: item.$6,
          quantity: item.$5,
          createdAt: now,
          updatedAt: now,
        ).toJson(),
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<List<Product>> getProducts({
    String query = '',
    String? category,
    ProductSort sort = ProductSort.nameAsc,
  }) async {
    final db = await _database.database;
    final where = <String>[];
    final args = <Object?>[];
    if (query.trim().isNotEmpty) {
      where.add('(name LIKE ? OR barcode LIKE ? OR category LIKE ?)');
      final term = '%${query.trim()}%';
      args.addAll([term, term, term]);
    }
    if (category != null && category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }
    final order = switch (sort) {
      ProductSort.nameAsc => 'name COLLATE NOCASE ASC',
      ProductSort.nameDesc => 'name COLLATE NOCASE DESC',
      ProductSort.priceAsc => 'price ASC',
      ProductSort.priceDesc => 'price DESC',
      ProductSort.stockAsc => 'quantity ASC',
      ProductSort.stockDesc => 'quantity DESC',
      ProductSort.newest => 'created_at DESC',
    };
    final rows = await db.query(
      'products',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: order,
    );
    return rows.map(Product.fromJson).toList();
  }

  @override
  Future<Product?> getById(String id) async {
    final rows = await (await _database.database).query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Product.fromJson(rows.first);
  }

  @override
  Future<Product?> getByBarcode(String barcode) async {
    final rows = await (await _database.database).query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode.trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : Product.fromJson(rows.first);
  }

  @override
  Future<List<String>> getCategories() async {
    final rows = await (await _database.database).rawQuery(
      'SELECT DISTINCT category FROM products ORDER BY category COLLATE NOCASE',
    );
    return rows.map((row) => row['category']! as String).toList();
  }

  @override
  Future<void> add(Product product) async {
    try {
      await (await _database.database).insert('products', product.toJson());
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const DuplicateBarcodeException();
      }
      rethrow;
    }
  }

  @override
  Future<void> update(Product product) async {
    try {
      await (await _database.database).update(
        'products',
        product.toJson(),
        where: 'id = ?',
        whereArgs: [product.id],
      );
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const DuplicateBarcodeException();
      }
      rethrow;
    }
  }
}
