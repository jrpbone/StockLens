import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/models/inventory_import.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/repositories/inventory_import_repository.dart';
import 'package:stocklens/screens/inventory/inventory_import_screen.dart';
import 'package:stocklens/services/inventory_import_service.dart';

class _UnusedRepository implements InventoryImportRepository {
  @override
  Future<List<Product>> getByBarcodes(Iterable<String> barcodes) async => [];

  @override
  Future<List<InventoryImportProductChange>> apply(
    InventoryImportPreview preview, {
    required DateTime appliedAt,
  }) => throw UnimplementedError();
}

class _FakeImportService extends InventoryImportService {
  _FakeImportService(this.previews, {this.staleFirstApply = false})
    : super(_UnusedRepository());

  final List<InventoryImportPreview> previews;
  final bool staleFirstApply;
  var _previewIndex = 0;
  var _applyCalls = 0;

  @override
  Future<InventoryImportPreview> preview(String csvContent) async {
    final index = _previewIndex.clamp(0, previews.length - 1);
    _previewIndex++;
    return previews[index];
  }

  @override
  Future<void> apply(InventoryImportPreview preview) async {
    _applyCalls++;
    if (staleFirstApply && _applyCalls == 1) {
      throw const StaleInventoryImportException();
    }
  }
}

Product _product(String id, String barcode, String name, {int quantity = 1}) =>
    Product(
      id: id,
      barcode: barcode,
      name: name,
      sellingPrice: 10,
      costPrice: 4,
      category: 'Test',
      description: '',
      quantity: quantity,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
    );

InventoryImportRowPreview _newRow(String name) {
  final after = _product('new', '111', name);
  return InventoryImportRowPreview(
    candidate: InventoryImportCandidate(
      rowNumber: 2,
      barcode: after.barcode,
      name: after.name,
      sellingPrice: after.sellingPrice,
      costPrice: after.costPrice,
      quantity: after.quantity,
      category: after.category,
      description: after.description,
    ),
    before: null,
    after: after,
    productDetailsChanged: true,
    stockChanged: true,
  );
}

InventoryImportPreview _preview({
  String newName = 'New item',
  bool includeExistingGroups = false,
  List<InventoryImportError> errors = const [],
}) {
  final rows = <InventoryImportRowPreview>[_newRow(newName)];
  if (includeExistingGroups) {
    final before = _product('existing', '222', 'Existing', quantity: 5);
    rows.add(
      InventoryImportRowPreview(
        candidate: const InventoryImportCandidate(
          rowNumber: 3,
          barcode: '222',
          name: 'Updated item',
          quantity: 0,
        ),
        before: before,
        after: before.copyWith(name: 'Updated item', quantity: 0),
        productDetailsChanged: true,
        stockChanged: true,
      ),
    );
    final unchanged = _product('unchanged', '333', 'Unchanged');
    rows.add(
      InventoryImportRowPreview(
        candidate: const InventoryImportCandidate(rowNumber: 4, barcode: '333'),
        before: unchanged,
        after: unchanged,
        productDetailsChanged: false,
        stockChanged: false,
      ),
    );
  }
  return InventoryImportPreview(
    importId: 'import-id',
    rows: rows,
    blockingErrors: errors,
  );
}

Future<void> _load(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('shows preview groups and disables apply for blocking errors', (
    tester,
  ) async {
    final service = _FakeImportService([
      _preview(
        includeExistingGroups: true,
        errors: const [
          InventoryImportError(
            rowNumber: 5,
            field: 'barcode',
            message: 'Duplicate barcode 123.',
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: InventoryImportScreen(service: service, csvContent: 'csv'),
      ),
    );
    await _load(tester);

    expect(find.text('1 new product'), findsOneWidget);
    expect(find.text('1 product update'), findsOneWidget);
    expect(find.text('1 stock change'), findsOneWidget);
    expect(find.text('1 unchanged row'), findsOneWidget);
    expect(find.text('1 blocking error'), findsOneWidget);
    expect(find.text('Row 5: Duplicate barcode 123.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Apply Import'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('confirms and applies a valid preview', (tester) async {
    final service = _FakeImportService([_preview()]);
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryImportScreen(service: service, csvContent: 'csv'),
      ),
    );
    await _load(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Apply Import'));
    await tester.pumpAndSettle();
    expect(find.text('Apply inventory import?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Inventory import applied.'), findsOneWidget);
  });

  testWidgets('refreshes a stale preview while retaining selected CSV', (
    tester,
  ) async {
    final service = _FakeImportService([
      _preview(newName: 'Original preview'),
      _preview(newName: 'Fresh preview'),
    ], staleFirstApply: true);
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryImportScreen(service: service, csvContent: 'kept csv'),
      ),
    );
    await _load(tester);
    expect(find.text('Original preview'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Apply Import'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Fresh preview'), findsOneWidget);
    expect(
      find.text('Inventory changed. Review the refreshed preview.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Apply Import'),
          )
          .onPressed,
      isNotNull,
    );
  });
}
