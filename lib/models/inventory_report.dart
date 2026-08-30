enum ReportRangePreset { today, last7Days, last30Days, custom, allTime }

class ReportRange {
  const ReportRange._({
    required this.preset,
    required this.startInclusive,
    required this.endExclusive,
  });

  const ReportRange.allTime()
    : preset = ReportRangePreset.allTime,
      startInclusive = null,
      endExclusive = null;

  factory ReportRange.today([DateTime? now]) =>
      ReportRange._preset(ReportRangePreset.today, 1, now ?? DateTime.now());

  factory ReportRange.last7Days([DateTime? now]) => ReportRange._preset(
    ReportRangePreset.last7Days,
    7,
    now ?? DateTime.now(),
  );

  factory ReportRange.last30Days([DateTime? now]) => ReportRange._preset(
    ReportRangePreset.last30Days,
    30,
    now ?? DateTime.now(),
  );

  factory ReportRange.custom(DateTime startDate, DateTime endDate) {
    final start = _localDay(startDate);
    final inclusiveEnd = _localDay(endDate);
    if (inclusiveEnd.isBefore(start)) {
      throw ArgumentError.value(
        endDate,
        'endDate',
        'The end date cannot be before the start date.',
      );
    }
    return ReportRange._(
      preset: ReportRangePreset.custom,
      startInclusive: start,
      endExclusive: _nextLocalDay(inclusiveEnd),
    );
  }

  factory ReportRange._preset(
    ReportRangePreset preset,
    int inclusiveDayCount,
    DateTime now,
  ) {
    final today = _localDay(now);
    return ReportRange._(
      preset: preset,
      startInclusive: DateTime(
        today.year,
        today.month,
        today.day - inclusiveDayCount + 1,
      ),
      endExclusive: _nextLocalDay(today),
    );
  }

  final ReportRangePreset preset;

  /// Inclusive local-midnight lower bound used by historical report queries.
  /// It is null only for [ReportRangePreset.allTime].
  final DateTime? startInclusive;

  /// Exclusive local-midnight upper bound used by historical report queries.
  /// It is null only for [ReportRangePreset.allTime].
  final DateTime? endExclusive;

  DateTime? get endInclusive {
    final end = endExclusive;
    return end == null ? null : DateTime(end.year, end.month, end.day - 1);
  }

  static DateTime _localDay(DateTime value) {
    final local = value.isUtc ? value.toLocal() : value;
    return DateTime(local.year, local.month, local.day);
  }

  static DateTime _nextLocalDay(DateTime value) =>
      DateTime(value.year, value.month, value.day + 1);
}

class InventoryValuation {
  const InventoryValuation({
    this.totalUnits = 0,
    this.costValue = 0,
    this.retailValue = 0,
    this.lowStockCount = 0,
    this.outOfStockCount = 0,
  }) : assert(totalUnits >= 0),
       assert(costValue >= 0),
       assert(retailValue >= 0),
       assert(lowStockCount >= 0),
       assert(outOfStockCount >= 0);

  final int totalUnits;
  final double costValue;
  final double retailValue;
  final int lowStockCount;
  final int outOfStockCount;

  double get potentialMargin => retailValue - costValue;
}

class MovementSummary {
  const MovementSummary({
    this.unitsSold = 0,
    this.recordedRevenue = 0,
    this.recordedCost = 0,
    this.damagedUnits = 0,
    this.expiredUnits = 0,
    this.netMovement = 0,
    this.legacySaleUnits = 0,
  }) : assert(unitsSold >= 0),
       assert(recordedRevenue >= 0),
       assert(recordedCost >= 0),
       assert(damagedUnits >= 0),
       assert(expiredUnits >= 0),
       assert(legacySaleUnits >= 0);

  final int unitsSold;
  final double recordedRevenue;
  final double recordedCost;
  final int damagedUnits;
  final int expiredUnits;
  final int netMovement;
  final int legacySaleUnits;

  double get estimatedGrossProfit => recordedRevenue - recordedCost;
}

class ProductMovementRank {
  const ProductMovementRank({
    required this.productId,
    required this.productName,
    this.unitsSold = 0,
    this.unitsOnHand = 0,
  }) : assert(unitsSold >= 0),
       assert(unitsOnHand >= 0);

  final String productId;
  final String productName;
  final int unitsSold;
  final int unitsOnHand;
}

class CategoryValuation {
  const CategoryValuation({
    required this.category,
    this.totalUnits = 0,
    this.costValue = 0,
    this.retailValue = 0,
  }) : assert(totalUnits >= 0),
       assert(costValue >= 0),
       assert(retailValue >= 0);

  final String category;
  final int totalUnits;
  final double costValue;
  final double retailValue;

  double get potentialMargin => retailValue - costValue;
}

class InventoryReport {
  InventoryReport({
    required this.range,
    required this.valuation,
    required this.movement,
    List<CategoryValuation> categories = const [],
    List<ProductMovementRank> fastMovers = const [],
    List<ProductMovementRank> inactiveProducts = const [],
  }) : categories = List.unmodifiable(categories),
       fastMovers = List.unmodifiable(fastMovers),
       inactiveProducts = List.unmodifiable(inactiveProducts);

  final ReportRange range;
  final InventoryValuation valuation;
  final MovementSummary movement;
  final List<CategoryValuation> categories;
  final List<ProductMovementRank> fastMovers;
  final List<ProductMovementRank> inactiveProducts;
}
