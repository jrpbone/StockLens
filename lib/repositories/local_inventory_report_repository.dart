import '../data/local/app_database.dart';
import '../models/inventory_report.dart';
import 'inventory_report_repository.dart';

class LocalInventoryReportRepository implements InventoryReportRepository {
  LocalInventoryReportRepository(this._database);

  final AppDatabase _database;

  @override
  Future<InventoryValuation> getValuation() async {
    final rows = await (await _database.database).rawQuery('''
      SELECT
        COALESCE(SUM(quantity), 0) AS total_units,
        COALESCE(SUM(quantity * cost_price), 0) AS cost_value,
        COALESCE(SUM(quantity * price), 0) AS retail_value,
        COALESCE(SUM(
          CASE WHEN quantity <= low_stock_threshold THEN 1 ELSE 0 END
        ), 0) AS low_stock_count,
        COALESCE(SUM(CASE WHEN quantity = 0 THEN 1 ELSE 0 END), 0)
          AS out_of_stock_count
      FROM products
      WHERE archived_at IS NULL
    ''');
    final row = rows.single;
    return InventoryValuation(
      totalUnits: _int(row['total_units']),
      costValue: _double(row['cost_value']),
      retailValue: _double(row['retail_value']),
      lowStockCount: _int(row['low_stock_count']),
      outOfStockCount: _int(row['out_of_stock_count']),
    );
  }

  @override
  Future<List<CategoryValuation>> getCategoryValuations() async {
    final rows = await (await _database.database).rawQuery('''
      SELECT
        category,
        COALESCE(SUM(quantity), 0) AS total_units,
        COALESCE(SUM(quantity * cost_price), 0) AS cost_value,
        COALESCE(SUM(quantity * price), 0) AS retail_value
      FROM products
      WHERE archived_at IS NULL
      GROUP BY category
      ORDER BY retail_value DESC, category COLLATE NOCASE ASC
    ''');
    return rows
        .map(
          (row) => CategoryValuation(
            category: row['category'] as String,
            totalUnits: _int(row['total_units']),
            costValue: _double(row['cost_value']),
            retailValue: _double(row['retail_value']),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<MovementSummary> getMovementSummary(ReportRange range) async {
    final filter = _rangeFilter(range, column: 'occurred_at');
    final where = filter.clause.isEmpty ? '' : 'WHERE ${filter.clause}';
    final rows = await (await _database.database).rawQuery('''
      SELECT
        COALESCE(SUM(CASE
          WHEN reason = 'Sale' AND delta < 0 THEN ABS(delta) ELSE 0
        END), 0) AS units_sold,
        COALESCE(SUM(CASE
          WHEN reason = 'Sale' AND delta < 0
            AND selling_price_snapshot IS NOT NULL
            AND cost_price_snapshot IS NOT NULL
          THEN ABS(delta) * selling_price_snapshot ELSE 0
        END), 0) AS recorded_revenue,
        COALESCE(SUM(CASE
          WHEN reason = 'Sale' AND delta < 0
            AND selling_price_snapshot IS NOT NULL
            AND cost_price_snapshot IS NOT NULL
          THEN ABS(delta) * cost_price_snapshot ELSE 0
        END), 0) AS recorded_cost,
        COALESCE(SUM(CASE
          WHEN reason = 'Damaged Item' AND delta < 0 THEN ABS(delta) ELSE 0
        END), 0) AS damaged_units,
        COALESCE(SUM(CASE
          WHEN reason = 'Expired Item' AND delta < 0 THEN ABS(delta) ELSE 0
        END), 0) AS expired_units,
        COALESCE(SUM(delta), 0) AS net_movement,
        COALESCE(SUM(CASE
          WHEN reason = 'Sale' AND delta < 0
            AND (selling_price_snapshot IS NULL OR cost_price_snapshot IS NULL)
          THEN ABS(delta) ELSE 0
        END), 0) AS legacy_sale_units
      FROM stock_transactions
      $where
    ''', filter.args);
    final row = rows.single;
    return MovementSummary(
      unitsSold: _int(row['units_sold']),
      recordedRevenue: _double(row['recorded_revenue']),
      recordedCost: _double(row['recorded_cost']),
      damagedUnits: _int(row['damaged_units']),
      expiredUnits: _int(row['expired_units']),
      netMovement: _int(row['net_movement']),
      legacySaleUnits: _int(row['legacy_sale_units']),
    );
  }

  @override
  Future<List<ProductMovementRank>> getFastMovers(ReportRange range) async {
    final filter = _rangeFilter(range, column: 't.occurred_at');
    final rangeClause = filter.clause.isEmpty ? '' : 'AND ${filter.clause}';
    final rows = await (await _database.database).rawQuery('''
      SELECT
        p.id AS product_id,
        p.name AS product_name,
        p.quantity AS units_on_hand,
        SUM(ABS(t.delta)) AS units_sold
      FROM stock_transactions t
      INNER JOIN products p ON p.id = t.product_id
      WHERE t.reason = 'Sale' AND t.delta < 0
      $rangeClause
      GROUP BY p.id, p.name, p.quantity
      ORDER BY units_sold DESC, p.name COLLATE NOCASE ASC, p.id ASC
    ''', filter.args);
    return rows.map(_productRank).toList(growable: false);
  }

  @override
  Future<List<ProductMovementRank>> getInactiveProducts(
    ReportRange range,
  ) async {
    final filter = _rangeFilter(range, column: 't.occurred_at');
    final rangeClause = filter.clause.isEmpty ? '' : 'AND ${filter.clause}';
    final rows = await (await _database.database).rawQuery('''
      SELECT
        p.id AS product_id,
        p.name AS product_name,
        p.quantity AS units_on_hand,
        0 AS units_sold
      FROM products p
      WHERE p.archived_at IS NULL
        AND p.quantity > 0
        AND NOT EXISTS (
          SELECT 1
          FROM stock_transactions t
          WHERE t.product_id = p.id
          $rangeClause
        )
      ORDER BY p.quantity DESC, p.name COLLATE NOCASE ASC, p.id ASC
    ''', filter.args);
    return rows.map(_productRank).toList(growable: false);
  }

  ProductMovementRank _productRank(Map<String, Object?> row) =>
      ProductMovementRank(
        productId: row['product_id'] as String,
        productName: row['product_name'] as String,
        unitsSold: _int(row['units_sold']),
        unitsOnHand: _int(row['units_on_hand']),
      );

  _RangeFilter _rangeFilter(ReportRange range, {required String column}) {
    final start = range.startInclusive;
    final end = range.endExclusive;
    if (start == null && end == null) return const _RangeFilter('', []);
    if (start == null || end == null) {
      throw ArgumentError.value(
        range,
        'range',
        'A bounded report range requires both boundaries.',
      );
    }
    return _RangeFilter('$column >= ? AND $column < ?', [
      start.toIso8601String(),
      end.toIso8601String(),
    ]);
  }

  int _int(Object? value) => (value as num?)?.toInt() ?? 0;
  double _double(Object? value) => (value as num?)?.toDouble() ?? 0;
}

class _RangeFilter {
  const _RangeFilter(this.clause, this.args);

  final String clause;
  final List<Object?> args;
}
