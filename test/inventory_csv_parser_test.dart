import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/models/inventory_import.dart';
import 'package:stocklens/services/inventory_csv_parser.dart';

void main() {
  const parser = InventoryCsvParser();

  test('parses quoted commas, escaped quotes, and CRLF rows', () {
    final rows = parser.parse(
      'barcode,name,price,quantity,description\r\n'
      '" 123 ","Large, Red",10.50,0,"Says ""hello"""',
    );

    expect(rows, hasLength(1));
    expect(rows.single.rowNumber, 2);
    expect(rows.single.barcode, '123');
    expect(rows.single.name, 'Large, Red');
    expect(rows.single.sellingPrice, 10.5);
    expect(rows.single.quantity, 0);
    expect(rows.single.hasExplicitQuantity, isTrue);
    expect(rows.single.description, 'Says "hello"');
  });

  test('accepts case-insensitive headers and the legacy price alias', () {
    final rows = parser.parse(
      ' BARCODE ,Name,PRICE,COST_PRICE,LOW_STOCK_THRESHOLD\n'
      'ABC,Widget,12.25,4.75,3',
    );

    expect(rows.single.barcode, 'ABC');
    expect(rows.single.sellingPrice, 12.25);
    expect(rows.single.costPrice, 4.75);
    expect(rows.single.lowStockThreshold, 3);
  });

  test('preserves blank optional cells separately from explicit zero', () {
    final rows = parser.parse(
      'barcode,name,selling_price,cost_price,quantity,'
      'low_stock_threshold,category,description\n'
      'existing,,,,,,,\n'
      'zero,Zero,0,0,0,0,,',
    );

    final blank = rows.first;
    expect(blank.name, isNull);
    expect(blank.sellingPrice, isNull);
    expect(blank.costPrice, isNull);
    expect(blank.quantity, isNull);
    expect(blank.lowStockThreshold, isNull);
    expect(blank.category, isNull);
    expect(blank.description, isNull);
    expect(blank.hasExplicitQuantity, isFalse);

    final zero = rows.last;
    expect(zero.sellingPrice, 0);
    expect(zero.costPrice, 0);
    expect(zero.quantity, 0);
    expect(zero.lowStockThreshold, 0);
    expect(zero.hasExplicitQuantity, isTrue);
  });

  test('keeps barcode matching case-sensitive after trimming', () {
    final rows = parser.parse('barcode,name\n ABC ,Upper\nabc,Lower');

    expect(rows.map((row) => row.barcode), ['ABC', 'abc']);
  });

  test('rejects duplicate trimmed barcodes with the source row number', () {
    expect(
      () => parser.parse('barcode,name\n123,A\n 123 ,B'),
      throwsA(
        isA<InventoryImportFormatException>().having(
          (error) => error.errors,
          'errors',
          contains(
            const InventoryImportError(
              rowNumber: 3,
              field: 'barcode',
              message: 'Duplicate barcode 123.',
            ),
          ),
        ),
      ),
    );
  });

  test('reports missing required headers and row barcodes', () {
    expect(
      () => parser.parse('name,quantity\nWidget,2'),
      throwsA(
        isA<InventoryImportFormatException>().having(
          (error) => error.errors.single.message,
          'message',
          'Required barcode header is missing.',
        ),
      ),
    );
    expect(
      () => parser.parse('barcode,name\n,Widget'),
      throwsA(
        isA<InventoryImportFormatException>().having(
          (error) => error.errors.single.rowNumber,
          'row number',
          2,
        ),
      ),
    );
  });

  test('reports every invalid typed cell with its row and field', () {
    expect(
      () => parser.parse(
        'barcode,name,selling_price,cost_price,quantity,low_stock_threshold\n'
        'a,A,-1,NaN,1.5,2.2\n'
        'b,B,Infinity,2,-1,-3',
      ),
      throwsA(
        isA<InventoryImportFormatException>().having(
          (error) => error.errors,
          'errors',
          containsAll([
            const InventoryImportError(
              rowNumber: 2,
              field: 'selling_price',
              message: 'Selling price must be a nonnegative number.',
            ),
            const InventoryImportError(
              rowNumber: 2,
              field: 'cost_price',
              message: 'Cost price must be a nonnegative number.',
            ),
            const InventoryImportError(
              rowNumber: 2,
              field: 'quantity',
              message: 'Quantity must be a nonnegative integer.',
            ),
            const InventoryImportError(
              rowNumber: 2,
              field: 'low_stock_threshold',
              message: 'Low-stock threshold must be a nonnegative integer.',
            ),
            const InventoryImportError(
              rowNumber: 3,
              field: 'selling_price',
              message: 'Selling price must be a nonnegative number.',
            ),
            const InventoryImportError(
              rowNumber: 3,
              field: 'quantity',
              message: 'Quantity must be a nonnegative integer.',
            ),
            const InventoryImportError(
              rowNumber: 3,
              field: 'low_stock_threshold',
              message: 'Low-stock threshold must be a nonnegative integer.',
            ),
          ]),
        ),
      ),
    );
  });

  test('rejects duplicate canonical headers including aliases', () {
    expect(
      () => parser.parse('barcode,price,selling_price\n1,2,3'),
      throwsA(
        isA<InventoryImportFormatException>().having(
          (error) => error.errors.single.message,
          'message',
          'Header selling_price is duplicated.',
        ),
      ),
    );
  });
}
