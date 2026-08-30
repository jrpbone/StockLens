import 'package:uuid/uuid.dart';

import '../models/inventory_import.dart';
import '../models/product.dart';
import '../repositories/inventory_import_repository.dart';
import 'inventory_csv_parser.dart';
import 'low_stock_notification_service.dart';

class InventoryImportService {
  InventoryImportService(
    this._repository, {
    this._parser = const InventoryCsvParser(),
    this.lowStockNotifications,
    DateTime Function()? nowProvider,
  }) : _nowProvider = nowProvider ?? DateTime.now;

  final InventoryImportRepository _repository;
  final InventoryCsvParser _parser;
  final LowStockNotificationService? lowStockNotifications;
  final DateTime Function() _nowProvider;

  Future<InventoryImportPreview> preview(String csvContent) async {
    final importId = const Uuid().v4();
    late final List<InventoryImportCandidate> candidates;
    try {
      candidates = _parser.parse(csvContent);
    } on InventoryImportFormatException catch (error) {
      return InventoryImportPreview(
        importId: importId,
        rows: const [],
        blockingErrors: error.errors,
      );
    }

    final products = await _repository.getByBarcodes(
      candidates.map((candidate) => candidate.barcode),
    );
    final productsByBarcode = {
      for (final product in products) product.barcode: product,
    };
    final rows = <InventoryImportRowPreview>[];
    final errors = <InventoryImportError>[];
    final previewedAt = _nowProvider();
    for (final candidate in candidates) {
      final existing = productsByBarcode[candidate.barcode];
      if (existing?.archivedAt != null) {
        errors.add(
          InventoryImportError(
            rowNumber: candidate.rowNumber,
            field: 'barcode',
            message:
                'Barcode ${candidate.barcode} belongs to an archived product.',
          ),
        );
        continue;
      }
      if (existing == null && candidate.name == null) {
        errors.add(
          InventoryImportError(
            rowNumber: candidate.rowNumber,
            field: 'name',
            message: 'Name is required for a new product.',
          ),
        );
        continue;
      }

      final after = existing == null
          ? _newProduct(candidate, previewedAt)
          : _updatedProduct(existing, candidate, previewedAt);
      final detailsChanged =
          existing == null || _detailsChanged(existing, after);
      final stockChanged = (existing?.quantity ?? 0) != after.quantity;
      rows.add(
        InventoryImportRowPreview(
          candidate: candidate,
          before: existing,
          after: after,
          productDetailsChanged: detailsChanged,
          stockChanged: stockChanged,
        ),
      );
    }

    return InventoryImportPreview(
      importId: importId,
      rows: rows,
      blockingErrors: errors,
    );
  }

  Future<void> apply(InventoryImportPreview preview) async {
    if (!preview.canApply) {
      throw StateError('An import with blocking errors cannot be applied.');
    }
    final changes = await _repository.apply(preview, appliedAt: _nowProvider());
    await lowStockNotifications?.evaluateAll(
      changes.map(
        (change) =>
            LowStockProductChange(before: change.before, after: change.after),
      ),
    );
  }

  Product _newProduct(InventoryImportCandidate candidate, DateTime now) =>
      Product(
        id: const Uuid().v4(),
        barcode: candidate.barcode,
        name: candidate.name!,
        sellingPrice: candidate.sellingPrice ?? 0,
        costPrice: candidate.costPrice ?? 0,
        lowStockThreshold: candidate.lowStockThreshold ?? 5,
        category: candidate.category ?? 'Uncategorized',
        description: candidate.description ?? '',
        quantity: candidate.quantity ?? 0,
        createdAt: now,
        updatedAt: now,
      );

  Product _updatedProduct(
    Product product,
    InventoryImportCandidate candidate,
    DateTime now,
  ) {
    final updated = product.copyWith(
      name: candidate.name,
      sellingPrice: candidate.sellingPrice,
      costPrice: candidate.costPrice,
      lowStockThreshold: candidate.lowStockThreshold,
      category: candidate.category,
      description: candidate.description,
      quantity: candidate.quantity,
    );
    return _detailsChanged(product, updated) ||
            product.quantity != updated.quantity
        ? updated.copyWith(updatedAt: now)
        : product;
  }

  bool _detailsChanged(Product before, Product after) =>
      before.name != after.name ||
      before.sellingPrice != after.sellingPrice ||
      before.costPrice != after.costPrice ||
      before.lowStockThreshold != after.lowStockThreshold ||
      before.category != after.category ||
      before.description != after.description;
}
