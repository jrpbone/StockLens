import '../models/inventory_report.dart';

abstract interface class InventoryReportRepository {
  Future<InventoryValuation> getValuation();
  Future<List<CategoryValuation>> getCategoryValuations();
  Future<MovementSummary> getMovementSummary(ReportRange range);
  Future<List<ProductMovementRank>> getFastMovers(ReportRange range);
  Future<List<ProductMovementRank>> getInactiveProducts(ReportRange range);
}
