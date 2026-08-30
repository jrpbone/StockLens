import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/local/app_database.dart';
import '../models/inventory_import.dart';
import '../models/product.dart';
import '../models/stock_transaction.dart';
import 'inventory_import_repository.dart';

class LocalInventoryImportRepository implements InventoryImportRepository {
  LocalInventoryImportRepository(this._database);

  final AppDatabase _database;

  @override
  Future<List<Product>> getByBarcodes(Iterable<String> barcodes) async {
    final values = barcodes.toSet().toList(growable: false);
    if (values.isEmpty) return const [];
    final placeholders = List.filled(values.length, '?').join(', ');
    final rows = await (await _database.database).query(
      'products',
      where: 'barcode IN ($placeholders)',
      whereArgs: values,
    );
    return List.unmodifiable(rows.map(Product.fromJson));
  }

  @override
  Future<List<InventoryImportProductChange>> apply(
    InventoryImportPreview preview, {
    required DateTime appliedAt,
  }) async {
    if (!preview.canApply) {
      throw StateError('An import with blocking errors cannot be applied.');
    }
    final db = await _database.database;
    return db.transaction((transaction) async {
      final currentByBarcode = <String, Product?>{};
      final seenBarcodes = <String>{};
      for (final row in preview.rows) {
        if (!seenBarcodes.add(row.candidate.barcode)) {
          throw const StaleInventoryImportException();
        }
        final current = await _byBarcode(transaction, row.candidate.barcode);
        currentByBarcode[row.candidate.barcode] = current;
        final before = row.before;
        if (before == null) {
          if (current != null) throw const StaleInventoryImportException();
        } else if (current == null ||
            current.archivedAt != null ||
            current.id != before.id ||
            current.updatedAt != before.updatedAt ||
            current.quantity != before.quantity) {
          throw const StaleInventoryImportException();
        }
        _validateCandidate(row.candidate, isNew: before == null);
      }

      final changes = <InventoryImportProductChange>[];
      for (final row in preview.rows) {
        final before = currentByBarcode[row.candidate.barcode];
        final after = before == null
            ? _newProduct(row, appliedAt)
            : _updatedProduct(before, row.candidate, appliedAt);
        _requireMatchingPreview(row, after);

        if (before == null) {
          await transaction.insert('products', after.toJson());
        } else if (_changed(before, after)) {
          await transaction.update(
            'products',
            _explicitUpdate(row.candidate, after),
            where: 'id = ? AND archived_at IS NULL',
            whereArgs: [before.id],
          );
        }

        final previousQuantity = before?.quantity ?? 0;
        final delta = after.quantity - previousQuantity;
        if (delta != 0) {
          await transaction.insert(
            'stock_transactions',
            StockTransaction(
              id: const Uuid().v4(),
              productId: after.id,
              delta: delta,
              reason: 'Inventory Correction',
              note: '',
              previousQuantity: previousQuantity,
              resultingQuantity: after.quantity,
              occurredAt: appliedAt,
              sellingPriceSnapshot: after.sellingPrice,
              costPriceSnapshot: after.costPrice,
              source: 'csv_import',
              sourceId: preview.importId,
            ).toJson(),
          );
        }
        if (before == null || _changed(before, after)) {
          changes.add(
            InventoryImportProductChange(before: before, after: after),
          );
        }
      }
      return List.unmodifiable(changes);
    });
  }

  Future<Product?> _byBarcode(DatabaseExecutor db, String barcode) async {
    final rows = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    return rows.isEmpty ? null : Product.fromJson(rows.single);
  }

  void _validateCandidate(
    InventoryImportCandidate candidate, {
    required bool isNew,
  }) {
    if (candidate.barcode.trim().isEmpty ||
        candidate.barcode != candidate.barcode.trim() ||
        (isNew && (candidate.name == null || candidate.name!.trim().isEmpty)) ||
        (candidate.sellingPrice != null &&
            (!candidate.sellingPrice!.isFinite ||
                candidate.sellingPrice! < 0)) ||
        (candidate.costPrice != null &&
            (!candidate.costPrice!.isFinite || candidate.costPrice! < 0)) ||
        (candidate.quantity != null && candidate.quantity! < 0) ||
        (candidate.lowStockThreshold != null &&
            candidate.lowStockThreshold! < 0)) {
      throw const StaleInventoryImportException();
    }
  }

  Product _newProduct(InventoryImportRowPreview row, DateTime appliedAt) {
    final candidate = row.candidate;
    return Product(
      id: row.after.id,
      barcode: candidate.barcode,
      name: candidate.name!,
      sellingPrice: candidate.sellingPrice ?? 0,
      costPrice: candidate.costPrice ?? 0,
      lowStockThreshold: candidate.lowStockThreshold ?? 5,
      category: candidate.category ?? 'Uncategorized',
      description: candidate.description ?? '',
      quantity: candidate.quantity ?? 0,
      createdAt: appliedAt,
      updatedAt: appliedAt,
    );
  }

  Product _updatedProduct(
    Product current,
    InventoryImportCandidate candidate,
    DateTime appliedAt,
  ) {
    final updated = current.copyWith(
      name: candidate.name,
      sellingPrice: candidate.sellingPrice,
      costPrice: candidate.costPrice,
      lowStockThreshold: candidate.lowStockThreshold,
      category: candidate.category,
      description: candidate.description,
      quantity: candidate.quantity,
    );
    return _changed(current, updated)
        ? updated.copyWith(updatedAt: appliedAt)
        : current;
  }

  Map<String, Object?> _explicitUpdate(
    InventoryImportCandidate candidate,
    Product after,
  ) => {
    if (candidate.name != null) 'name': after.name,
    if (candidate.sellingPrice != null) 'price': after.sellingPrice,
    if (candidate.costPrice != null) 'cost_price': after.costPrice,
    if (candidate.lowStockThreshold != null)
      'low_stock_threshold': after.lowStockThreshold,
    if (candidate.category != null) 'category': after.category,
    if (candidate.description != null) 'description': after.description,
    if (candidate.quantity != null) 'quantity': after.quantity,
    'updated_at': after.updatedAt.toIso8601String(),
  };

  void _requireMatchingPreview(
    InventoryImportRowPreview row,
    Product calculated,
  ) {
    final expected = row.after;
    if (calculated.id != expected.id ||
        calculated.barcode != expected.barcode ||
        calculated.name != expected.name ||
        calculated.sellingPrice != expected.sellingPrice ||
        calculated.costPrice != expected.costPrice ||
        calculated.lowStockThreshold != expected.lowStockThreshold ||
        calculated.category != expected.category ||
        calculated.description != expected.description ||
        calculated.quantity != expected.quantity ||
        calculated.imagePath != expected.imagePath ||
        calculated.archivedAt != expected.archivedAt) {
      throw const StaleInventoryImportException();
    }
  }

  bool _changed(Product before, Product after) =>
      before.name != after.name ||
      before.sellingPrice != after.sellingPrice ||
      before.costPrice != after.costPrice ||
      before.lowStockThreshold != after.lowStockThreshold ||
      before.category != after.category ||
      before.description != after.description ||
      before.quantity != after.quantity;
}
