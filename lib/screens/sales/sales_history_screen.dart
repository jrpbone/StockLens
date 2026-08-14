import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state.dart';
import '../../models/sale_order.dart';
import '../../services/product_service.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key, required this.service});

  final ProductService service;

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  List<SaleOrder> _orders = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final orders = await widget.service.orders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Map<String, List<SaleOrder>> get _grouped {
    final groups = <String, List<SaleOrder>>{};
    for (final order in _orders) {
      groups.putIfAbsent(order.transactionDate, () => []).add(order);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sales / Orders')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? ErrorState(
            message: 'Sales history could not be loaded.',
            onRetry: _load,
          )
        : _orders.isEmpty
        ? const _EmptySalesHistory()
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                for (final group in _grouped.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                    child: Text(
                      _formatDate(group.key),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  for (final order in group.value) ...[
                    _OrderCard(order: order),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
          ),
  );

  String _formatDate(String value) {
    final date = DateTime.tryParse(value);
    return date == null ? value : DateFormat('MMMM d, y').format(date);
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final SaleOrder order;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Text(
        order.orderNumber,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${formatCentavos(order.totalAmountCents)} • '
        '${DateFormat('h:mm a').format(order.createdAt)}',
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${DateFormat('MMMM d, y').format(order.createdAt)} — '
            '${DateFormat('h:mm a').format(order.createdAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Items',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < order.items.length; index++) ...[
          _OrderItemRow(item: order.items[index]),
          if (index != order.items.length - 1) const Divider(height: 18),
        ],
        const Divider(height: 24),
        _TotalRow(label: 'Different Items', value: '${order.totalItems}'),
        _TotalRow(label: 'Total Quantity', value: '${order.totalQuantity}'),
        _TotalRow(
          label: 'TOTAL',
          value: formatCentavos(order.totalAmountCents),
          emphasized: true,
        ),
      ],
    ),
  );
}

class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({required this.item});

  final SaleOrderItem item;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.productName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              'SKU: ${item.sku}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text('${item.quantity} × ${formatCentavos(item.unitPriceCents)}'),
          ],
        ),
      ),
      Text(
        formatCentavos(item.subtotalCents),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasized
                ? const TextStyle(fontWeight: FontWeight.w800)
                : null,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasized ? 18 : null,
            fontWeight: FontWeight.w800,
            color: emphasized ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
      ],
    ),
  );
}

class _EmptySalesHistory extends StatelessWidget {
  const _EmptySalesHistory();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'No completed sales yet.',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text('Completed POS orders will appear here.'),
        ],
      ),
    ),
  );
}
