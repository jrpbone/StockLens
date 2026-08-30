import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/models/inventory_report.dart';

void main() {
  group('ReportRange', () {
    test('custom dates become local half-open query boundaries', () {
      final range = ReportRange.custom(
        DateTime(2026, 8, 1, 14, 30),
        DateTime(2026, 8, 3, 9),
      );

      expect(range.preset, ReportRangePreset.custom);
      expect(range.startInclusive, DateTime(2026, 8, 1));
      expect(range.endExclusive, DateTime(2026, 8, 4));
    });

    test('preset ranges use inclusive local calendar days', () {
      final now = DateTime(2026, 8, 19, 18, 45);

      final today = ReportRange.today(now);
      final last7Days = ReportRange.last7Days(now);
      final last30Days = ReportRange.last30Days(now);

      expect(today.startInclusive, DateTime(2026, 8, 19));
      expect(today.endExclusive, DateTime(2026, 8, 20));
      expect(last7Days.startInclusive, DateTime(2026, 8, 13));
      expect(last7Days.endExclusive, DateTime(2026, 8, 20));
      expect(last30Days.startInclusive, DateTime(2026, 7, 21));
      expect(last30Days.endExclusive, DateTime(2026, 8, 20));
    });

    test('all-time has no SQL boundaries and invalid custom ranges fail', () {
      const allTime = ReportRange.allTime();

      expect(allTime.preset, ReportRangePreset.allTime);
      expect(allTime.startInclusive, isNull);
      expect(allTime.endExclusive, isNull);
      expect(
        () => ReportRange.custom(DateTime(2026, 8, 4), DateTime(2026, 8, 3)),
        throwsArgumentError,
      );
    });
  });

  test('valuation and movement values expose derived totals', () {
    const valuation = InventoryValuation(
      totalUnits: 12,
      costValue: 100,
      retailValue: 160,
      lowStockCount: 2,
      outOfStockCount: 1,
    );
    const movement = MovementSummary(
      unitsSold: 5,
      recordedRevenue: 90,
      recordedCost: 54,
      damagedUnits: 2,
      expiredUnits: 1,
      netMovement: -8,
      legacySaleUnits: 3,
    );

    expect(valuation.potentialMargin, 60);
    expect(movement.estimatedGrossProfit, 36);
  });

  test('rank and category values retain report-ready fields', () {
    const rank = ProductMovementRank(
      productId: 'cola',
      productName: 'Cola',
      unitsSold: 8,
      unitsOnHand: 4,
    );
    const category = CategoryValuation(
      category: 'Beverages',
      totalUnits: 12,
      costValue: 100,
      retailValue: 160,
    );

    expect(rank.productId, 'cola');
    expect(rank.productName, 'Cola');
    expect(rank.unitsSold, 8);
    expect(rank.unitsOnHand, 4);
    expect(category.potentialMargin, 60);
  });

  test('InventoryReport defensively freezes aggregate lists', () {
    final categories = <CategoryValuation>[
      const CategoryValuation(category: 'Beverages'),
    ];
    final fastMovers = <ProductMovementRank>[
      const ProductMovementRank(
        productId: 'cola',
        productName: 'Cola',
        unitsSold: 8,
      ),
    ];
    final inactiveProducts = <ProductMovementRank>[
      const ProductMovementRank(
        productId: 'water',
        productName: 'Water',
        unitsOnHand: 4,
      ),
    ];

    final report = InventoryReport(
      range: const ReportRange.allTime(),
      valuation: const InventoryValuation(),
      movement: const MovementSummary(),
      categories: categories,
      fastMovers: fastMovers,
      inactiveProducts: inactiveProducts,
    );
    categories.clear();
    fastMovers.clear();
    inactiveProducts.clear();

    expect(report.categories, hasLength(1));
    expect(report.fastMovers, hasLength(1));
    expect(report.inactiveProducts, hasLength(1));
    expect(
      () => report.categories.add(const CategoryValuation(category: 'Food')),
      throwsUnsupportedError,
    );
  });
}
