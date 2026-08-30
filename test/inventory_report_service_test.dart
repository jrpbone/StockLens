import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/models/inventory_report.dart';
import 'package:stocklens/repositories/inventory_report_repository.dart';
import 'package:stocklens/services/inventory_report_service.dart';

class _RecordingRepository implements InventoryReportRepository {
  final historicalRanges = <ReportRange>[];

  @override
  Future<List<CategoryValuation>> getCategoryValuations() async => const [
    CategoryValuation(category: 'Beverages', totalUnits: 5),
  ];

  @override
  Future<List<ProductMovementRank>> getFastMovers(ReportRange range) async {
    historicalRanges.add(range);
    return const [
      ProductMovementRank(productId: 'cola', productName: 'Cola', unitsSold: 3),
    ];
  }

  @override
  Future<List<ProductMovementRank>> getInactiveProducts(
    ReportRange range,
  ) async {
    historicalRanges.add(range);
    return const [
      ProductMovementRank(
        productId: 'water',
        productName: 'Water',
        unitsOnHand: 4,
      ),
    ];
  }

  @override
  Future<MovementSummary> getMovementSummary(ReportRange range) async {
    historicalRanges.add(range);
    return const MovementSummary(unitsSold: 3, recordedRevenue: 60);
  }

  @override
  Future<InventoryValuation> getValuation() async =>
      const InventoryValuation(totalUnits: 9, retailValue: 150);
}

void main() {
  test('combines repository aggregates for the requested range', () async {
    final repository = _RecordingRepository();
    final service = InventoryReportService(repository);
    final range = ReportRange.last30Days(DateTime(2026, 8, 19));

    final report = await service.load(range);

    expect(report.range, same(range));
    expect(report.valuation.totalUnits, 9);
    expect(report.movement.unitsSold, 3);
    expect(report.categories.single.category, 'Beverages');
    expect(report.fastMovers.single.productId, 'cola');
    expect(report.inactiveProducts.single.productId, 'water');
    expect(repository.historicalRanges, [
      same(range),
      same(range),
      same(range),
    ]);
  });
}
