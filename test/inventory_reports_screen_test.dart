import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/app.dart';
import 'package:stocklens/core/utils/formatters.dart';
import 'package:stocklens/models/inventory_report.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/stock_transaction.dart';
import 'package:stocklens/repositories/inventory_report_repository.dart';
import 'package:stocklens/repositories/product_repository.dart';
import 'package:stocklens/screens/reports/inventory_reports_screen.dart';
import 'package:stocklens/services/inventory_report_service.dart';
import 'package:stocklens/services/product_service.dart';

class _ReportRepository implements InventoryReportRepository {
  _ReportRepository({this.failFirstValuation = false, this.empty = false});

  final bool failFirstValuation;
  final bool empty;
  int valuationCalls = 0;
  final requestedRanges = <ReportRange>[];

  @override
  Future<InventoryValuation> getValuation() async {
    valuationCalls++;
    if (failFirstValuation && valuationCalls == 1) {
      throw StateError('forced report failure');
    }
    return empty
        ? const InventoryValuation()
        : const InventoryValuation(
            totalUnits: 12,
            costValue: 100,
            retailValue: 160,
            lowStockCount: 2,
            outOfStockCount: 1,
          );
  }

  @override
  Future<List<CategoryValuation>> getCategoryValuations() async => empty
      ? const []
      : const [
          CategoryValuation(
            category: 'Beverages',
            totalUnits: 12,
            costValue: 100,
            retailValue: 160,
          ),
        ];

  @override
  Future<List<ProductMovementRank>> getFastMovers(ReportRange range) async =>
      empty
      ? const []
      : const [
          ProductMovementRank(
            productId: 'cola',
            productName: 'Cola',
            unitsSold: 5,
            unitsOnHand: 4,
          ),
        ];

  @override
  Future<List<ProductMovementRank>> getInactiveProducts(
    ReportRange range,
  ) async => empty
      ? const []
      : const [
          ProductMovementRank(
            productId: 'water',
            productName: 'Water',
            unitsOnHand: 7,
          ),
        ];

  @override
  Future<MovementSummary> getMovementSummary(ReportRange range) async {
    requestedRanges.add(range);
    return empty
        ? const MovementSummary()
        : const MovementSummary(
            unitsSold: 5,
            recordedRevenue: 90,
            recordedCost: 54,
            damagedUnits: 2,
            expiredUnits: 1,
            netMovement: -3,
            legacySaleUnits: 2,
          );
  }
}

class _ProductRepository implements ProductRepository {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> add(Product product) async {}
  @override
  Future<void> update(Product product) async {}
  @override
  Future<Product> adjustStock({
    required String productId,
    required int delta,
    required String reason,
    required String note,
    String source = 'manual',
    String? sourceId,
  }) => throw UnimplementedError();
  @override
  Future<void> setLowStockNotified(String productId, bool value) async {}
  @override
  Future<void> deletePermanently(String productId) async {}
  @override
  Future<Map<String, Object?>> createBackup() async => const {};
  @override
  Future<List<Product>> getArchivedProducts({String query = ''}) async => [];
  @override
  Future<List<Product>> getLowStockProducts() async => [];
  @override
  Future<List<StockTransaction>> getStockTransactions(String productId) async =>
      [];
  @override
  Future<Product> setArchived(String productId, {required bool archived}) =>
      throw UnimplementedError();
  @override
  Future<void> restoreBackup(Map<String, Object?> backup) async {}
  @override
  Future<List<String>> getCategories() async => [];
  @override
  Future<Product?> getByBarcode(String barcode) async => null;
  @override
  Future<Product?> getById(String id) async => null;
  @override
  Future<List<Product>> getProducts({
    String query = '',
    String? category,
    ProductSort sort = ProductSort.nameAsc,
  }) async => [];
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 30 && !condition(); attempt++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  testWidgets('shows report totals, lists, disclosure, and preset changes', (
    tester,
  ) async {
    final repository = _ReportRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryReportsScreen(
          service: InventoryReportService(repository),
          nowProvider: () => DateTime(2026, 8, 19, 12),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _waitFor(
      tester,
      () => find.text('Inventory cost value').evaluate().isNotEmpty,
    );

    expect(find.text('Inventory cost value'), findsOneWidget);
    expect(find.text(pesoFormat.format(100)), findsOneWidget);
    expect(find.text('Estimated gross profit'), findsOneWidget);
    expect(find.text(pesoFormat.format(36)), findsOneWidget);
    await tester.tap(find.text('30 days'));
    await _waitFor(tester, () => repository.requestedRanges.length >= 2);
    expect(
      repository.requestedRanges.last.preset,
      ReportRangePreset.last30Days,
    );

    final reportScroll = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('2 sold units have no historical prices.'),
      300,
      scrollable: reportScroll,
    );
    expect(
      find.text('2 sold units have no historical prices.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Beverages'),
      300,
      scrollable: reportScroll,
    );
    expect(find.text('Beverages'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Fast movers'),
      300,
      scrollable: reportScroll,
    );
    expect(find.text('Fast movers'), findsOneWidget);
    expect(find.text('Cola'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Inactive stock'),
      300,
      scrollable: reportScroll,
    );
    expect(find.text('Inactive stock'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Water'),
      300,
      scrollable: reportScroll,
    );
    expect(find.text('Water'), findsOneWidget);
  });

  testWidgets('custom selection converts inclusive dates before loading', (
    tester,
  ) async {
    final repository = _ReportRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryReportsScreen(
          service: InventoryReportService(repository),
          nowProvider: () => DateTime(2026, 8, 19),
          customRangePicker: (_) async => DateTimeRange(
            start: DateTime(2026, 8, 1),
            end: DateTime(2026, 8, 3),
          ),
        ),
      ),
    );
    await _waitFor(tester, () => find.text('Custom').evaluate().isNotEmpty);

    await tester.tap(find.text('Custom'));
    await _waitFor(tester, () => repository.requestedRanges.length >= 2);

    final range = repository.requestedRanges.last;
    expect(range.preset, ReportRangePreset.custom);
    expect(range.startInclusive, DateTime(2026, 8, 1));
    expect(range.endExclusive, DateTime(2026, 8, 4));
  });

  testWidgets('shows a retryable error followed by an empty report', (
    tester,
  ) async {
    final repository = _ReportRepository(failFirstValuation: true, empty: true);
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryReportsScreen(
          service: InventoryReportService(repository),
        ),
      ),
    );
    await _waitFor(
      tester,
      () => find.text('Reports could not be loaded.').evaluate().isNotEmpty,
    );

    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await _waitFor(
      tester,
      () => find
          .text('No inventory or movement data to report.')
          .evaluate()
          .isNotEmpty,
    );

    expect(repository.valuationCalls, 2);
  });

  testWidgets('opens Reports from the Inventory app bar', (tester) async {
    final productService = ProductService(_ProductRepository());
    final reportService = InventoryReportService(_ReportRepository());

    await tester.pumpWidget(
      StockLensApp(
        productService: productService,
        reportService: reportService,
      ),
    );
    await _waitFor(tester, () => find.text('StockLens').evaluate().isNotEmpty);
    await tester.tap(find.text('Inventory').last);
    await _waitFor(
      tester,
      () => find.byTooltip('Reports').evaluate().isNotEmpty,
    );

    await tester.tap(find.byTooltip('Reports'));
    await _waitFor(
      tester,
      () => find.text('Inventory Reports').evaluate().isNotEmpty,
    );

    expect(find.text('Inventory cost value'), findsOneWidget);
  });
}
