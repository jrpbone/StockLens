import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state.dart';
import '../../models/inventory_report.dart';
import '../../services/inventory_report_service.dart';

typedef CustomReportRangePicker =
    Future<DateTimeRange?> Function(BuildContext context);

class InventoryReportsScreen extends StatefulWidget {
  const InventoryReportsScreen({
    super.key,
    required this.service,
    this.nowProvider,
    this.customRangePicker,
  });

  final InventoryReportService service;
  final DateTime Function()? nowProvider;
  final CustomReportRangePicker? customRangePicker;

  @override
  State<InventoryReportsScreen> createState() => _InventoryReportsScreenState();
}

class _InventoryReportsScreenState extends State<InventoryReportsScreen> {
  late ReportRange _range;
  InventoryReport? _report;
  Object? _error;
  var _requestVersion = 0;

  DateTime get _now => widget.nowProvider?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _range = ReportRange.today(_now);
    _load();
  }

  Future<void> _load() async {
    final requestVersion = ++_requestVersion;
    setState(() {
      _report = null;
      _error = null;
    });
    try {
      final report = await widget.service.load(_range);
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() => _report = report);
    } catch (error) {
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() => _error = error);
    }
  }

  Future<void> _selectPreset(ReportRangePreset preset) async {
    final now = _now;
    final nextRange = switch (preset) {
      ReportRangePreset.today => ReportRange.today(now),
      ReportRangePreset.last7Days => ReportRange.last7Days(now),
      ReportRangePreset.last30Days => ReportRange.last30Days(now),
      ReportRangePreset.allTime => const ReportRange.allTime(),
      ReportRangePreset.custom => await _pickCustomRange(now),
    };
    if (nextRange == null || !mounted) return;
    setState(() => _range = nextRange);
    await _load();
  }

  Future<ReportRange?> _pickCustomRange(DateTime now) async {
    final selected = widget.customRangePicker == null
        ? await showDateRangePicker(
            context: context,
            firstDate: DateTime(2000),
            lastDate: DateTime(now.year, now.month, now.day),
            initialDateRange: DateTimeRange(
              start: DateTime(now.year, now.month, now.day - 29),
              end: DateTime(now.year, now.month, now.day),
            ),
          )
        : await widget.customRangePicker!(context);
    return selected == null
        ? null
        : ReportRange.custom(selected.start, selected.end);
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Reports'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh reports',
          ),
        ],
      ),
      body: Column(
        children: [
          _RangeSelector(selected: _range.preset, onSelected: _selectPreset),
          Expanded(
            child: report == null
                ? _error == null
                      ? const Center(child: CircularProgressIndicator())
                      : ErrorState(
                          message: 'Reports could not be loaded.',
                          onRetry: _load,
                        )
                : _ReportBody(report: report, onRefresh: _load),
          ),
        ],
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.selected, required this.onSelected});

  final ReportRangePreset selected;
  final ValueChanged<ReportRangePreset> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    child: Row(
      children: [
        for (final option in const [
          (ReportRangePreset.today, 'Today'),
          (ReportRangePreset.last7Days, '7 days'),
          (ReportRangePreset.last30Days, '30 days'),
          (ReportRangePreset.custom, 'Custom'),
          (ReportRangePreset.allTime, 'All time'),
        ]) ...[
          ChoiceChip(
            label: Text(option.$2),
            selected: selected == option.$1,
            onSelected: (_) => onSelected(option.$1),
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report, required this.onRefresh});

  final InventoryReport report;
  final Future<void> Function() onRefresh;

  bool get _isEmpty =>
      report.valuation.totalUnits == 0 &&
      report.valuation.costValue == 0 &&
      report.valuation.retailValue == 0 &&
      report.valuation.lowStockCount == 0 &&
      report.valuation.outOfStockCount == 0 &&
      report.movement.unitsSold == 0 &&
      report.movement.damagedUnits == 0 &&
      report.movement.expiredUnits == 0 &&
      report.movement.netMovement == 0 &&
      report.categories.isEmpty &&
      report.fastMovers.isEmpty &&
      report.inactiveProducts.isEmpty;

  @override
  Widget build(BuildContext context) {
    if (_isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 150),
            Icon(Icons.analytics_outlined, size: 54),
            SizedBox(height: 16),
            Text(
              'No inventory or movement data to report.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final valuation = report.valuation;
    final movement = report.movement;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const _SectionTitle('Current inventory'),
          const SizedBox(height: 8),
          _MetricGrid(
            metrics: [
              ('Units on hand', '${valuation.totalUnits}'),
              ('Inventory cost value', pesoFormat.format(valuation.costValue)),
              (
                'Potential retail value',
                pesoFormat.format(valuation.retailValue),
              ),
              (
                'Potential gross margin',
                pesoFormat.format(valuation.potentialMargin),
              ),
              ('Low stock', '${valuation.lowStockCount}'),
              ('Out of stock', '${valuation.outOfStockCount}'),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Movement'),
          const SizedBox(height: 8),
          _MetricGrid(
            metrics: [
              ('Units sold', '${movement.unitsSold}'),
              ('Recorded revenue', pesoFormat.format(movement.recordedRevenue)),
              ('Recorded cost', pesoFormat.format(movement.recordedCost)),
              (
                'Estimated gross profit',
                pesoFormat.format(movement.estimatedGrossProfit),
              ),
              ('Damaged units', '${movement.damagedUnits}'),
              ('Expired units', '${movement.expiredUnits}'),
              ('Net movement', _signed(movement.netMovement)),
            ],
          ),
          if (movement.legacySaleUnits > 0) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(_legacyDisclosure(movement.legacySaleUnits)),
                subtitle: const Text(
                  'Revenue, cost, and profit exclude those units.',
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const _SectionTitle('Category valuation'),
          const SizedBox(height: 8),
          if (report.categories.isEmpty)
            const _EmptySection('No active product categories.')
          else
            for (final category in report.categories)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(category.category),
                  subtitle: Text(
                    '${category.totalUnits} units | '
                    'Cost ${pesoFormat.format(category.costValue)} | '
                    'Retail ${pesoFormat.format(category.retailValue)}',
                  ),
                  trailing: Text(pesoFormat.format(category.potentialMargin)),
                ),
              ),
          const SizedBox(height: 16),
          const _SectionTitle('Fast movers'),
          const SizedBox(height: 8),
          if (report.fastMovers.isEmpty)
            const _EmptySection('No sales in this range.')
          else
            for (final product in report.fastMovers)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.trending_up),
                  title: Text(product.productName),
                  subtitle: Text('${product.unitsOnHand} units on hand'),
                  trailing: Text('${product.unitsSold} sold'),
                ),
              ),
          const SizedBox(height: 16),
          const _SectionTitle('Inactive stock'),
          const SizedBox(height: 8),
          if (report.inactiveProducts.isEmpty)
            const _EmptySection('Every stocked product moved in this range.')
          else
            for (final product in report.inactiveProducts)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.pause_circle_outline),
                  title: Text(product.productName),
                  trailing: Text('${product.unitsOnHand} on hand'),
                ),
              ),
        ],
      ),
    );
  }

  static String _signed(int value) => value > 0 ? '+$value' : '$value';

  static String _legacyDisclosure(int units) => units == 1
      ? '1 sold unit has no historical prices.'
      : '$units sold units have no historical prices.';
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<(String, String)> metrics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - 8) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final metric in metrics)
            SizedBox(
              width: width,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metric.$1,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        metric.$2,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleLarge);
}

class _EmptySection extends StatelessWidget {
  const _EmptySection(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(message),
  );
}
