import '../models/inventory_import.dart';
import '../models/product.dart';

class InventoryImportProductChange {
  const InventoryImportProductChange({this.before, required this.after});

  final Product? before;
  final Product after;
}

abstract interface class InventoryImportRepository {
  Future<List<Product>> getByBarcodes(Iterable<String> barcodes);

  Future<List<InventoryImportProductChange>> apply(
    InventoryImportPreview preview, {
    required DateTime appliedAt,
  });
}
