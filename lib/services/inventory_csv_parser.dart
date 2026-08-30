import 'package:csv/csv.dart';

import '../models/inventory_import.dart';

class InventoryCsvParser {
  const InventoryCsvParser();

  static const _headers = {
    'barcode',
    'name',
    'selling_price',
    'cost_price',
    'category',
    'quantity',
    'low_stock_threshold',
    'description',
  };

  List<InventoryImportCandidate> parse(String content) {
    final decoded = Csv(autoDetect: false).decode(content);
    if (decoded.isEmpty) {
      throw InventoryImportFormatException([
        const InventoryImportError(
          rowNumber: 0,
          field: 'barcode',
          message: 'Required barcode header is missing.',
        ),
      ]);
    }

    final errors = <InventoryImportError>[];
    final headerIndexes = <String, int>{};
    for (var index = 0; index < decoded.first.length; index++) {
      final rawHeader = decoded.first[index].toString().trim().toLowerCase();
      final header = rawHeader == 'price' ? 'selling_price' : rawHeader;
      if (!_headers.contains(header)) continue;
      if (headerIndexes.containsKey(header)) {
        errors.add(
          InventoryImportError(
            rowNumber: 1,
            field: header,
            message: 'Header $header is duplicated.',
          ),
        );
      } else {
        headerIndexes[header] = index;
      }
    }
    if (!headerIndexes.containsKey('barcode')) {
      errors.add(
        const InventoryImportError(
          rowNumber: 0,
          field: 'barcode',
          message: 'Required barcode header is missing.',
        ),
      );
    }
    if (errors.isNotEmpty) throw InventoryImportFormatException(errors);

    final candidates = <InventoryImportCandidate>[];
    final seenBarcodes = <String>{};
    for (var index = 1; index < decoded.length; index++) {
      final rowNumber = index + 1;
      final row = decoded[index];
      final barcode = _cell(row, headerIndexes['barcode']).trim();
      if (barcode.isEmpty) {
        errors.add(
          InventoryImportError(
            rowNumber: rowNumber,
            field: 'barcode',
            message: 'Barcode is required.',
          ),
        );
        continue;
      }
      if (!seenBarcodes.add(barcode)) {
        errors.add(
          InventoryImportError(
            rowNumber: rowNumber,
            field: 'barcode',
            message: 'Duplicate barcode $barcode.',
          ),
        );
        continue;
      }

      final sellingPrice = _doubleCell(
        row,
        headerIndexes['selling_price'],
        rowNumber: rowNumber,
        field: 'selling_price',
        label: 'Selling price',
        errors: errors,
      );
      final costPrice = _doubleCell(
        row,
        headerIndexes['cost_price'],
        rowNumber: rowNumber,
        field: 'cost_price',
        label: 'Cost price',
        errors: errors,
      );
      final quantity = _integerCell(
        row,
        headerIndexes['quantity'],
        rowNumber: rowNumber,
        field: 'quantity',
        label: 'Quantity',
        errors: errors,
      );
      final threshold = _integerCell(
        row,
        headerIndexes['low_stock_threshold'],
        rowNumber: rowNumber,
        field: 'low_stock_threshold',
        label: 'Low-stock threshold',
        errors: errors,
      );
      candidates.add(
        InventoryImportCandidate(
          rowNumber: rowNumber,
          barcode: barcode,
          name: _optionalText(row, headerIndexes['name']),
          sellingPrice: sellingPrice,
          costPrice: costPrice,
          category: _optionalText(row, headerIndexes['category']),
          quantity: quantity,
          lowStockThreshold: threshold,
          description: _optionalText(row, headerIndexes['description']),
        ),
      );
    }

    if (errors.isNotEmpty) throw InventoryImportFormatException(errors);
    return List.unmodifiable(candidates);
  }

  String _cell(List<dynamic> row, int? index) =>
      index == null || index >= row.length ? '' : row[index].toString();

  String? _optionalText(List<dynamic> row, int? index) {
    final value = _cell(row, index).trim();
    return value.isEmpty ? null : value;
  }

  double? _doubleCell(
    List<dynamic> row,
    int? index, {
    required int rowNumber,
    required String field,
    required String label,
    required List<InventoryImportError> errors,
  }) {
    final text = _cell(row, index).trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value < 0) {
      errors.add(
        InventoryImportError(
          rowNumber: rowNumber,
          field: field,
          message: '$label must be a nonnegative number.',
        ),
      );
      return null;
    }
    return value;
  }

  int? _integerCell(
    List<dynamic> row,
    int? index, {
    required int rowNumber,
    required String field,
    required String label,
    required List<InventoryImportError> errors,
  }) {
    final text = _cell(row, index).trim();
    if (text.isEmpty) return null;
    final value = num.tryParse(text);
    if (value == null ||
        !value.isFinite ||
        value < 0 ||
        value.toInt() != value) {
      errors.add(
        InventoryImportError(
          rowNumber: rowNumber,
          field: field,
          message: '$label must be a nonnegative integer.',
        ),
      );
      return null;
    }
    return value.toInt();
  }
}
