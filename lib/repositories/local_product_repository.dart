import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/local/app_database.dart';
import '../models/product.dart';
import '../models/stock_transaction.dart';
import 'product_repository.dart';

class LocalProductRepository implements ProductRepository {
  LocalProductRepository(this._database);
  final AppDatabase _database;

  @override
  Future<void> initialize() async {
    final db = await _database.database;
    final initialized = await db.query(
      'app_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['samples_initialized'],
      limit: 1,
    );
    if (initialized.isNotEmpty) return;
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM products'),
        ) ??
        0;
    if (count != 0) {
      await db.insert('app_metadata', {
        'key': 'samples_initialized',
        'value': 'true',
      });
      return;
    }
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
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final item in samples) {
        final product = Product(
          id: const Uuid().v4(),
          barcode: item.$1,
          name: item.$2,
          price: item.$3,
          category: item.$4,
          description: item.$6,
          quantity: item.$5,
          createdAt: now,
          updatedAt: now,
        );
        batch.insert('products', product.toJson());
        batch.insert(
          'stock_transactions',
          StockTransaction(
            id: const Uuid().v4(),
            productId: product.id,
            delta: product.quantity,
            reason: 'Initial stock',
            note: 'Sample inventory created during first setup.',
            previousQuantity: 0,
            resultingQuantity: product.quantity,
            occurredAt: now,
          ).toJson(),
        );
      }
      await batch.commit(noResult: true);
      await txn.insert('app_metadata', {
        'key': 'samples_initialized',
        'value': 'true',
      });
    });
  }

  @override
  Future<List<Product>> getProducts({
    String query = '',
    String? category,
    ProductSort sort = ProductSort.nameAsc,
  }) async {
    final db = await _database.database;
    final where = <String>['archived_at IS NULL'];
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
  Future<List<Product>> getArchivedProducts({String query = ''}) async {
    final where = <String>['archived_at IS NOT NULL'];
    final args = <Object?>[];
    if (query.trim().isNotEmpty) {
      where.add('(name LIKE ? OR barcode LIKE ? OR category LIKE ?)');
      final term = '%${query.trim()}%';
      args.addAll([term, term, term]);
    }
    final rows = await (await _database.database).query(
      'products',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'archived_at DESC',
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
      where: 'barcode = ? AND archived_at IS NULL',
      whereArgs: [barcode.trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : Product.fromJson(rows.first);
  }

  @override
  Future<List<String>> getCategories() async {
    final rows = await (await _database.database).rawQuery(
      'SELECT DISTINCT category FROM products '
      'WHERE archived_at IS NULL ORDER BY category COLLATE NOCASE',
    );
    return rows.map((row) => row['category']! as String).toList();
  }

  @override
  Future<void> add(Product product) async {
    try {
      await (await _database.database).transaction((txn) async {
        await txn.insert('products', product.toJson());
        if (product.quantity > 0) {
          await txn.insert(
            'stock_transactions',
            StockTransaction(
              id: const Uuid().v4(),
              productId: product.id,
              delta: product.quantity,
              reason: 'Initial stock',
              note: '',
              previousQuantity: 0,
              resultingQuantity: product.quantity,
              occurredAt: product.createdAt,
            ).toJson(),
          );
        }
      });
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

  @override
  Future<Product> adjustStock({
    required String productId,
    required int delta,
    required String reason,
    required String note,
  }) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'products',
        where: 'id = ? AND archived_at IS NULL',
        whereArgs: [productId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Product not found.');
      final current = Product.fromJson(rows.first);
      final nextQuantity = current.quantity + delta;
      if (nextQuantity < 0) throw const StockCannotBeNegativeException();
      final now = DateTime.now();
      final updated = current.copyWith(quantity: nextQuantity, updatedAt: now);
      await txn.update(
        'products',
        updated.toJson(),
        where: 'id = ?',
        whereArgs: [productId],
      );
      await txn.insert(
        'stock_transactions',
        StockTransaction(
          id: const Uuid().v4(),
          productId: productId,
          delta: delta,
          reason: reason.trim(),
          note: note.trim(),
          previousQuantity: current.quantity,
          resultingQuantity: nextQuantity,
          occurredAt: now,
        ).toJson(),
      );
      return updated;
    });
  }

  @override
  Future<List<StockTransaction>> getStockTransactions(String productId) async {
    final rows = await (await _database.database).query(
      'stock_transactions',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'occurred_at DESC',
    );
    return rows.map(StockTransaction.fromJson).toList();
  }

  @override
  Future<Product> setArchived(
    String productId, {
    required bool archived,
  }) async {
    final db = await _database.database;
    final now = DateTime.now();
    await db.update(
      'products',
      {
        'archived_at': archived ? now.toIso8601String() : null,
        'updated_at': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
    final product = await getById(productId);
    if (product == null) throw StateError('Product not found.');
    return product;
  }

  @override
  Future<void> deletePermanently(String productId) async {
    final deleted = await (await _database.database).delete(
      'products',
      where: 'id = ? AND archived_at IS NOT NULL',
      whereArgs: [productId],
    );
    if (deleted == 0) {
      throw StateError('Only archived products can be deleted.');
    }
  }

  @override
  Future<Map<String, Object?>> createBackup() async {
    final db = await _database.database;
    return {
      'format': 'stocklens-backup',
      'schema_version': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'products': await db.query('products', orderBy: 'created_at ASC'),
      'stock_transactions': await db.query(
        'stock_transactions',
        orderBy: 'occurred_at ASC',
      ),
    };
  }

  @override
  Future<void> restoreBackup(Map<String, Object?> backup) async {
    if (backup['format'] != 'stocklens-backup' ||
        backup['schema_version'] != 1) {
      throw const FormatException('Unsupported StockLens backup file.');
    }
    final rawProducts = backup['products'];
    final rawTransactions = backup['stock_transactions'];
    if (rawProducts is! List || rawTransactions is! List) {
      throw const FormatException('Backup data is incomplete.');
    }
    final products = rawProducts.map((value) {
      if (value is! Map) throw const FormatException('Invalid product data.');
      final row = Map<String, Object?>.from(value);
      final product = Product.fromJson(row);
      if (product.id.isEmpty ||
          product.barcode.isEmpty ||
          product.name.isEmpty ||
          product.price < 0 ||
          product.quantity < 0) {
        throw const FormatException('Invalid product data.');
      }
      return product;
    }).toList();
    final productIds = products.map((product) => product.id).toSet();
    if (productIds.length != products.length) {
      throw const FormatException('Backup contains duplicate product IDs.');
    }
    final transactions = rawTransactions.map((value) {
      if (value is! Map) {
        throw const FormatException('Invalid stock transaction data.');
      }
      final transaction = StockTransaction.fromJson(
        Map<String, Object?>.from(value),
      );
      if (!productIds.contains(transaction.productId) ||
          transaction.reason.trim().isEmpty ||
          transaction.previousQuantity < 0 ||
          transaction.resultingQuantity < 0 ||
          transaction.previousQuantity + transaction.delta !=
              transaction.resultingQuantity) {
        throw const FormatException('Invalid stock transaction data.');
      }
      return transaction;
    }).toList();

    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.delete('stock_transactions');
      await txn.delete('products');
      for (final product in products) {
        await txn.insert('products', product.toJson());
      }
      for (final transaction in transactions) {
        await txn.insert('stock_transactions', transaction.toJson());
      }
    });
  }
}
