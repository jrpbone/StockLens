import '../models/inventory_report.dart';
import '../repositories/inventory_report_repository.dart';

class InventoryReportService {
  const InventoryReportService(this._repository);

  final InventoryReportRepository _repository;

  Future<InventoryReport> load(ReportRange range) async {
    final results = await Future.wait<Object>([
      _repository.getValuation(),
      _repository.getMovementSummary(range),
      _repository.getCategoryValuations(),
      _repository.getFastMovers(range),
      _repository.getInactiveProducts(range),
    ]);

    return InventoryReport(
      range: range,
      valuation: results[0] as InventoryValuation,
      movement: results[1] as MovementSummary,
      categories: results[2] as List<CategoryValuation>,
      fastMovers: results[3] as List<ProductMovementRank>,
      inactiveProducts: results[4] as List<ProductMovementRank>,
    );
  }
}
