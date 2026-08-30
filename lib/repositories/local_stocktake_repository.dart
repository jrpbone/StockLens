import 'package:uuid/uuid.dart';

import '../data/local/app_database.dart';
import '../models/product.dart';
import '../models/stock_transaction.dart';
import '../models/stocktake_item.dart';
import '../models/stocktake_session.dart';
import 'stocktake_repository.dart';

class LocalStocktakeRepository implements StocktakeRepository {
  LocalStocktakeRepository(this._database);

  final AppDatabase _database;

  @override
  Future<void> create(
    StocktakeSession session,
    List<StocktakeItem> items,
  ) async {
    if (items.isEmpty) throw ArgumentError.value(items, 'items');
    if (items.any((item) => item.sessionId != session.id)) {
      throw ArgumentError.value(
        items,
        'items',
        'Items must belong to session.',
      );
    }
    final productIds = items.map((item) => item.productId).toSet();
    if (productIds.length != items.length) {
      throw ArgumentError.value(items, 'items', 'Product IDs must be unique.');
    }
    await (await _database.database).transaction((txn) async {
      await txn.insert('stocktake_sessions', session.toJson());
      for (final item in items) {
        await txn.insert('stocktake_items', item.toJson());
      }
    });
  }

  @override
  Future<StocktakeSession?> getById(String sessionId) async {
    final db = await _database.database;
    final rows = await db.query(
      'stocktake_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final itemRows = await db.query(
      'stocktake_items',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'product_id ASC',
    );
    return StocktakeSession.fromJson(rows.single).copyWith(
      items: itemRows.map(StocktakeItem.fromJson).toList(growable: false),
    );
  }

  @override
  Future<List<StocktakeSession>> getSessions() async {
    final db = await _database.database;
    final sessionRows = await db.query(
      'stocktake_sessions',
      orderBy:
          "CASE status WHEN 'in_progress' THEN 0 ELSE 1 END, "
          'created_at DESC',
    );
    final sessions = <StocktakeSession>[];
    for (final row in sessionRows) {
      final session = StocktakeSession.fromJson(row);
      final itemRows = await db.query(
        'stocktake_items',
        where: 'session_id = ?',
        whereArgs: [session.id],
        orderBy: 'product_id ASC',
      );
      sessions.add(
        session.copyWith(
          items: itemRows.map(StocktakeItem.fromJson).toList(growable: false),
        ),
      );
    }
    return List.unmodifiable(sessions);
  }

  @override
  Future<void> setCount({
    required String sessionId,
    required String productId,
    required int countedQuantity,
    required DateTime updatedAt,
  }) async {
    final changed = await (await _database.database).update(
      'stocktake_items',
      {
        'counted_quantity': countedQuantity,
        'updated_at': updatedAt.toIso8601String(),
      },
      where: '''session_id = ? AND product_id = ? AND EXISTS (
        SELECT 1 FROM stocktake_sessions
        WHERE id = ? AND status = 'in_progress'
      )''',
      whereArgs: [sessionId, productId, sessionId],
    );
    if (changed != 1) throw StateError('Stocktake item cannot be updated.');
  }

  @override
  Future<void> incrementCount({
    required String sessionId,
    required String productId,
    required DateTime updatedAt,
  }) async {
    final changed = await (await _database.database).rawUpdate(
      '''UPDATE stocktake_items
      SET counted_quantity = COALESCE(counted_quantity, 0) + 1,
          updated_at = ?
      WHERE session_id = ? AND product_id = ? AND EXISTS (
        SELECT 1 FROM stocktake_sessions
        WHERE id = ? AND status = 'in_progress'
      )''',
      [updatedAt.toIso8601String(), sessionId, productId, sessionId],
    );
    if (changed != 1) throw StateError('Stocktake item cannot be updated.');
  }

  @override
  Future<void> setRemainingToZero({
    required String sessionId,
    required DateTime updatedAt,
  }) async {
    await (await _database.database).update(
      'stocktake_items',
      {'counted_quantity': 0, 'updated_at': updatedAt.toIso8601String()},
      where: '''session_id = ? AND counted_quantity IS NULL AND EXISTS (
        SELECT 1 FROM stocktake_sessions
        WHERE id = ? AND status = 'in_progress'
      )''',
      whereArgs: [sessionId, sessionId],
    );
  }

  @override
  Future<List<StocktakeProductChange>> complete({
    required String sessionId,
    required List<AcceptedStocktakeLine> acceptedLines,
    required DateTime completedAt,
  }) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final sessionRows = await txn.query(
        'stocktake_sessions',
        columns: ['status'],
        where: 'id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      if (sessionRows.isEmpty) {
        throw StateError('Stocktake session not found.');
      }
      if (sessionRows.single['status'] != 'in_progress') {
        throw StateError('Completed stocktakes cannot be changed.');
      }

      final itemRows = await txn.query(
        'stocktake_items',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'product_id ASC',
      );
      final items = itemRows
          .map(StocktakeItem.fromJson)
          .toList(growable: false);
      if (items.isEmpty || items.any((item) => item.countedQuantity == null)) {
        throw const IncompleteStocktakeException();
      }

      final acceptedByProduct = <String, AcceptedStocktakeLine>{};
      for (final line in acceptedLines) {
        if (line.sessionId != sessionId ||
            line.productId.trim().isEmpty ||
            line.productId != line.productId.trim() ||
            line.countedQuantity < 0 ||
            line.currentQuantity < 0 ||
            acceptedByProduct.containsKey(line.productId)) {
          throw const StaleStocktakeCompletionException();
        }
        acceptedByProduct[line.productId] = line;
      }
      if (acceptedByProduct.length != items.length) {
        throw const StaleStocktakeCompletionException();
      }

      final reconciliations = <(Product, Product)>[];
      for (final item in items) {
        final accepted = acceptedByProduct[item.productId];
        if (accepted == null ||
            accepted.countedQuantity != item.countedQuantity) {
          throw const StaleStocktakeCompletionException();
        }
        final productRows = await txn.query(
          'products',
          where: 'id = ? AND archived_at IS NULL',
          whereArgs: [item.productId],
          limit: 1,
        );
        if (productRows.isEmpty) {
          throw const StaleStocktakeCompletionException();
        }
        final current = Product.fromJson(productRows.single);
        if (current.quantity != accepted.currentQuantity) {
          throw const StaleStocktakeCompletionException();
        }
        final updated = current.copyWith(
          quantity: item.countedQuantity!,
          updatedAt: completedAt,
        );
        reconciliations.add((current, updated));
      }

      final changes = <StocktakeProductChange>[];
      for (final (before, after) in reconciliations) {
        final delta = after.quantity - before.quantity;
        if (delta == 0) continue;
        final updated = await txn.update(
          'products',
          {
            'quantity': after.quantity,
            'updated_at': after.updatedAt.toIso8601String(),
          },
          where: 'id = ? AND archived_at IS NULL',
          whereArgs: [before.id],
        );
        if (updated != 1) {
          throw const StaleStocktakeCompletionException();
        }
        await txn.insert(
          'stock_transactions',
          StockTransaction(
            id: const Uuid().v4(),
            productId: before.id,
            delta: delta,
            reason: 'Inventory Correction',
            note: '',
            previousQuantity: before.quantity,
            resultingQuantity: after.quantity,
            occurredAt: completedAt,
            sellingPriceSnapshot: before.sellingPrice,
            costPriceSnapshot: before.costPrice,
            source: 'stocktake',
            sourceId: sessionId,
          ).toJson(),
        );
        changes.add(StocktakeProductChange(before: before, after: after));
      }

      final completed = await txn.update(
        'stocktake_sessions',
        {'status': 'completed', 'completed_at': completedAt.toIso8601String()},
        where: "id = ? AND status = 'in_progress'",
        whereArgs: [sessionId],
      );
      if (completed != 1) {
        throw const StaleStocktakeCompletionException();
      }
      return List.unmodifiable(changes);
    });
  }
}
