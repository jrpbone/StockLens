import 'product.dart';

class InventoryImportCandidate {
  const InventoryImportCandidate({
    required this.rowNumber,
    required this.barcode,
    this.name,
    this.sellingPrice,
    this.costPrice,
    this.category,
    this.quantity,
    this.lowStockThreshold,
    this.description,
  });

  final int rowNumber;
  final String barcode;
  final String? name;
  final double? sellingPrice;
  final double? costPrice;
  final String? category;
  final int? quantity;
  final int? lowStockThreshold;
  final String? description;

  bool get hasExplicitName => name != null;
  bool get hasExplicitSellingPrice => sellingPrice != null;
  bool get hasExplicitCostPrice => costPrice != null;
  bool get hasExplicitCategory => category != null;
  bool get hasExplicitQuantity => quantity != null;
  bool get hasExplicitLowStockThreshold => lowStockThreshold != null;
  bool get hasExplicitDescription => description != null;
}

class InventoryImportError {
  const InventoryImportError({
    required this.rowNumber,
    required this.field,
    required this.message,
  });

  final int rowNumber;
  final String field;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is InventoryImportError &&
      other.rowNumber == rowNumber &&
      other.field == field &&
      other.message == message;

  @override
  int get hashCode => Object.hash(rowNumber, field, message);

  @override
  String toString() => rowNumber > 0 ? 'Row $rowNumber: $message' : message;
}

class InventoryImportFormatException implements Exception {
  InventoryImportFormatException(List<InventoryImportError> errors)
    : errors = List.unmodifiable(errors);

  final List<InventoryImportError> errors;

  @override
  String toString() => errors.map((error) => error.toString()).join('\n');
}

class InventoryImportRowPreview {
  const InventoryImportRowPreview({
    required this.candidate,
    required this.before,
    required this.after,
    required this.productDetailsChanged,
    required this.stockChanged,
  });

  final InventoryImportCandidate candidate;
  final Product? before;
  final Product after;
  final bool productDetailsChanged;
  final bool stockChanged;

  bool get isNew => before == null;
  int get beforeQuantity => before?.quantity ?? 0;
  int get afterQuantity => after.quantity;
}

class InventoryImportPreview {
  InventoryImportPreview({
    required this.importId,
    required List<InventoryImportRowPreview> rows,
    required List<InventoryImportError> blockingErrors,
  }) : rows = List.unmodifiable(rows),
       blockingErrors = List.unmodifiable(blockingErrors);

  final String importId;
  final List<InventoryImportRowPreview> rows;
  final List<InventoryImportError> blockingErrors;

  List<InventoryImportRowPreview> get newProducts =>
      List.unmodifiable(rows.where((row) => row.isNew));

  List<InventoryImportRowPreview> get productUpdates => List.unmodifiable(
    rows.where((row) => !row.isNew && row.productDetailsChanged),
  );

  List<InventoryImportRowPreview> get stockChanges =>
      List.unmodifiable(rows.where((row) => !row.isNew && row.stockChanged));

  List<InventoryImportRowPreview> get unchangedRows => List.unmodifiable(
    rows.where(
      (row) => !row.isNew && !row.productDetailsChanged && !row.stockChanged,
    ),
  );

  bool get canApply => blockingErrors.isEmpty;
}

class StaleInventoryImportException implements Exception {
  const StaleInventoryImportException();

  @override
  String toString() => 'Inventory changed after this import was previewed.';
}
