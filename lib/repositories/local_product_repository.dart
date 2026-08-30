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
        45.0,
        'Beverages',
        20,
        'Classic cola soft drink.',
      ),
      (
        '4807770274228',
        'Lucky Me Pancit Canton',
        18.0,
        10.0,
        'Food',
        50,
        'Instant stir-fried noodles.',
      ),
      (
        '4800016075030',
        'Safeguard Soap',
        45.0,
        25.0,
        'Personal Care',
        10,
        'Antibacterial bath soap.',
      ),
      (
        '748485102002',
        'Century Tuna',
        42.0,
        22.0,
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
          sellingPrice: item.$3,
          costPrice: item.$4,
          category: item.$5,
          description: item.$7,
          quantity: item.$6,
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
            sellingPriceSnapshot: product.sellingPrice,
            costPriceSnapshot: product.costPrice,
            source: 'manual',
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
  Future<List<Product>> getLowStockProducts() async {
    final rows = await (await _database.database).query(
      'products',
      where: 'archived_at IS NULL AND quantity <= low_stock_threshold',
      orderBy:
          'CASE WHEN quantity = 0 THEN 0 ELSE 1 END ASC, '
          '(low_stock_threshold - quantity) DESC, name COLLATE NOCASE ASC',
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
              sellingPriceSnapshot: product.sellingPrice,
              costPriceSnapshot: product.costPrice,
              source: 'manual',
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
    String source = 'manual',
    String? sourceId,
  }) async {
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'Reason cannot be blank.');
    }
    final normalizedSource = source.trim();
    if (normalizedSource.isEmpty) {
      throw ArgumentError.value(source, 'source', 'Source cannot be blank.');
    }
    final trimmedSourceId = sourceId?.trim();
    final normalizedSourceId =
        trimmedSourceId == null || trimmedSourceId.isEmpty
        ? null
        : trimmedSourceId;
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
          reason: normalizedReason,
          note: note.trim(),
          previousQuantity: current.quantity,
          resultingQuantity: nextQuantity,
          occurredAt: now,
          sellingPriceSnapshot: current.sellingPrice,
          costPriceSnapshot: current.costPrice,
          source: normalizedSource,
          sourceId: normalizedSourceId,
        ).toJson(),
      );
      return updated;
    });
  }

  @override
  Future<void> setLowStockNotified(String productId, bool value) async {
    final updated = await (await _database.database).update(
      'products',
      {'low_stock_notified': value ? 1 : 0},
      where: 'id = ?',
      whereArgs: [productId],
    );
    if (updated == 0) throw StateError('Product not found.');
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
    await (await _database.database).transaction((txn) async {
      final products = await txn.query(
        'products',
        columns: ['archived_at'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (products.isEmpty || products.single['archived_at'] == null) {
        throw StateError('Only archived products can be deleted.');
      }
      final activeReferences = await txn.rawQuery(
        '''SELECT 1 FROM stocktake_items
        INNER JOIN stocktake_sessions
          ON stocktake_sessions.id = stocktake_items.session_id
        WHERE stocktake_items.product_id = ?
          AND stocktake_sessions.status = 'in_progress'
        LIMIT 1''',
        [productId],
      );
      if (activeReferences.isNotEmpty) {
        throw const ProductReferencedByInProgressStocktakeException();
      }
      await txn.delete('products', where: 'id = ?', whereArgs: [productId]);
    });
  }

  @override
  Future<Map<String, Object?>> createBackup() async {
    final db = await _database.database;
    return db.transaction((txn) async {
      return {
        'format': 'stocklens-backup',
        'schema_version': 2,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'products': await txn.query('products', orderBy: 'created_at ASC'),
        'stock_transactions': await txn.query(
          'stock_transactions',
          orderBy: 'occurred_at ASC',
        ),
        'stocktake_sessions': await txn.query(
          'stocktake_sessions',
          orderBy: 'created_at ASC',
        ),
        'stocktake_items': await txn.query(
          'stocktake_items',
          orderBy: 'session_id ASC, product_id ASC',
        ),
      };
    });
  }

  @override
  Future<void> restoreBackup(Map<String, Object?> backup) async {
    final schemaVersion = backup['schema_version'];
    if (backup['format'] != 'stocklens-backup' ||
        schemaVersion is! int ||
        (schemaVersion != 1 && schemaVersion != 2)) {
      throw const FormatException('Unsupported StockLens backup file.');
    }
    final rawProducts = backup['products'];
    final rawTransactions = backup['stock_transactions'];
    if (rawProducts is! List || rawTransactions is! List) {
      throw const FormatException('Backup data is incomplete.');
    }
    final rawStocktakeSessions = schemaVersion == 2
        ? backup['stocktake_sessions']
        : const [];
    final rawStocktakeItems = schemaVersion == 2
        ? backup['stocktake_items']
        : const [];
    if (rawStocktakeSessions is! List || rawStocktakeItems is! List) {
      throw const FormatException('Backup stocktake data is incomplete.');
    }
    final products = rawProducts.map((value) {
      if (value is! Map) throw const FormatException('Invalid product data.');
      final row = Map<String, Object?>.from(value);
      if (schemaVersion == 1) {
        row['cost_price'] = 0.0;
        row['low_stock_threshold'] = 5;
        row['low_stock_notified'] = 0;
      }
      if (!_isValidProductData(row)) {
        throw const FormatException('Invalid product data.');
      }
      // Low-stock alerts are local state and must never be restored.
      row['low_stock_notified'] = 0;
      final product = _productFromBackup(row);
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
      final row = Map<String, Object?>.from(value);
      if (schemaVersion == 1) {
        row['selling_price_snapshot'] = null;
        row['cost_price_snapshot'] = null;
        row['source'] = null;
        row['source_id'] = null;
      }
      if (!_isValidTransactionData(row)) {
        throw const FormatException('Invalid stock transaction data.');
      }
      final transaction = _transactionFromBackup(row);
      if (!productIds.contains(transaction.productId) ||
          transaction.id.isEmpty ||
          transaction.reason.trim().isEmpty ||
          transaction.previousQuantity < 0 ||
          transaction.resultingQuantity < 0 ||
          transaction.previousQuantity + transaction.delta !=
              transaction.resultingQuantity) {
        throw const FormatException('Invalid stock transaction data.');
      }
      return transaction;
    }).toList();
    final transactionIds = transactions
        .map((transaction) => transaction.id)
        .toSet();
    if (transactionIds.length != transactions.length) {
      throw const FormatException('Backup contains duplicate transaction IDs.');
    }
    final stocktakeSessions = rawStocktakeSessions.map((value) {
      if (value is! Map) {
        throw const FormatException('Invalid stocktake session data.');
      }
      final row = Map<String, Object?>.from(value);
      if (!_isValidStocktakeSession(row)) {
        throw const FormatException('Invalid stocktake session data.');
      }
      return row;
    }).toList();
    final sessionIds = stocktakeSessions
        .map((session) => session['id'] as String)
        .toSet();
    if (sessionIds.length != stocktakeSessions.length) {
      throw const FormatException(
        'Backup contains duplicate stocktake session IDs.',
      );
    }
    final stocktakeItems = rawStocktakeItems.map((value) {
      if (value is! Map) {
        throw const FormatException('Invalid stocktake item data.');
      }
      final row = Map<String, Object?>.from(value);
      if (!_isValidStocktakeItem(
        row,
        sessionIds: sessionIds,
        productIds: productIds,
      )) {
        throw const FormatException('Invalid stocktake item data.');
      }
      return row;
    }).toList();
    final stocktakeItemKeys = stocktakeItems
        .map((item) => '${item['session_id']}\u0000${item['product_id']}')
        .toSet();
    if (stocktakeItemKeys.length != stocktakeItems.length) {
      throw const FormatException('Backup contains duplicate stocktake items.');
    }

    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.delete('stocktake_items');
      await txn.delete('stocktake_sessions');
      await txn.delete('stock_transactions');
      await txn.delete('products');
      for (final product in products) {
        await txn.insert('products', product.toJson());
      }
      for (final transaction in transactions) {
        await txn.insert('stock_transactions', transaction.toJson());
      }
      for (final session in stocktakeSessions) {
        await txn.insert('stocktake_sessions', session);
      }
      for (final item in stocktakeItems) {
        await txn.insert('stocktake_items', item);
      }
    });
  }

  Product _productFromBackup(Map<String, Object?> row) {
    try {
      return Product.fromJson(row);
    } catch (_) {
      throw const FormatException('Invalid product data.');
    }
  }

  StockTransaction _transactionFromBackup(Map<String, Object?> row) {
    try {
      return StockTransaction.fromJson(row);
    } catch (_) {
      throw const FormatException('Invalid stock transaction data.');
    }
  }

  bool _isValidProductData(Map<String, Object?> row) =>
      _isNonEmptyString(row['id']) &&
      _isNonEmptyString(row['barcode']) &&
      _isNonEmptyString(row['name']) &&
      row['category'] is String &&
      row['description'] is String &&
      _isNonNegativeNumber(row['price']) &&
      _isNonNegativeNumber(row['cost_price']) &&
      _isNonNegativeInteger(row['quantity']) &&
      _isNonNegativeInteger(row['low_stock_threshold']) &&
      _isZeroOrOne(row['low_stock_notified']) &&
      _isIsoDate(row['created_at']) &&
      _isIsoDate(row['updated_at']) &&
      (row['archived_at'] == null || _isIsoDate(row['archived_at']));

  bool _isValidTransactionData(Map<String, Object?> row) =>
      _isFiniteInteger(row['delta']) &&
      _isFiniteInteger(row['previous_quantity']) &&
      _isFiniteInteger(row['resulting_quantity']) &&
      _isValidTransactionMetadata(row);

  bool _isValidTransactionMetadata(Map<String, Object?> row) =>
      _isNullableNonNegativeNumber(row['selling_price_snapshot']) &&
      _isNullableNonNegativeNumber(row['cost_price_snapshot']) &&
      _isNullableNonEmptyString(row['source']) &&
      _isNullableNonEmptyString(row['source_id']);

  bool _isValidStocktakeSession(Map<String, Object?> row) =>
      _isNonEmptyString(row['id']) &&
      _isNonEmptyString(row['name']) &&
      (row['status'] == 'in_progress' || row['status'] == 'completed') &&
      row['scope_description'] is String &&
      row['notes'] is String &&
      _isIsoDate(row['created_at']) &&
      (row['completed_at'] == null || _isIsoDate(row['completed_at']));

  bool _isValidStocktakeItem(
    Map<String, Object?> row, {
    required Set<String> sessionIds,
    required Set<String> productIds,
  }) =>
      row['session_id'] is String &&
      sessionIds.contains(row['session_id']) &&
      row['product_id'] is String &&
      productIds.contains(row['product_id']) &&
      _isNonNegativeInteger(row['expected_quantity']) &&
      (row['counted_quantity'] == null ||
          _isNonNegativeInteger(row['counted_quantity'])) &&
      _isIsoDate(row['updated_at']);

  bool _isNullableNonNegativeNumber(Object? value) =>
      value == null || _isNonNegativeNumber(value);

  bool _isNonNegativeNumber(Object? value) =>
      value is num && value >= 0 && (value is! double || value.isFinite);

  bool _isNullableNonEmptyString(Object? value) =>
      value == null || (value is String && value.trim().isNotEmpty);

  bool _isNonEmptyString(Object? value) =>
      value is String && value.trim().isNotEmpty;

  bool _isZeroOrOne(Object? value) =>
      value is int && (value == 0 || value == 1);

  bool _isNonNegativeInteger(Object? value) =>
      _isFiniteInteger(value) && (value as num) >= 0;

  bool _isFiniteInteger(Object? value) =>
      value is num &&
      (value is! double || value.isFinite) &&
      value.toInt() == value;

  bool _isIsoDate(Object? value) =>
      value is String && DateTime.tryParse(value) != null;
}
