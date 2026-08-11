import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state.dart';
import '../../models/product.dart';
import '../../models/stock_transaction.dart';
import '../../services/product_service.dart';
import '../../widgets/product_image.dart';
import '../../widgets/stock_badge.dart';
import '../edit_product/edit_product_screen.dart';
import '../stock_adjustment/stock_adjustment_dialog.dart';

class ProductDetailsScreen extends StatefulWidget {
  const ProductDetailsScreen({
    super.key,
    required this.service,
    required this.productId,
  });
  final ProductService service;
  final String productId;

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  Product? _product;
  List<StockTransaction> _transactions = [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.service.byId(widget.productId),
        widget.service.stockTransactions(widget.productId),
      ]);
      if (!mounted) return;
      final product = results[0] as Product?;
      setState(() {
        _product = product;
        _transactions = results[1] as List<StockTransaction>;
        _error = product == null ? 'not found' : null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _archive(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive product?'),
        content: Text(
          '${product.name} will leave the active inventory but can be restored later with its history intact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.service.archive(product);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _restore(Product product) async {
    final restored = await widget.service.restore(product);
    if (!mounted) return;
    setState(() => _product = restored);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Product restored.')));
  }

  Future<void> _deletePermanently(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          '${product.name} and its complete stock history will be deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.service.deletePermanently(product);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          product?.archivedAt == null ? 'Product Details' : 'Archived Product',
        ),
        actions: [
          if (product != null && product.archivedAt == null)
            IconButton(
              onPressed: () => _archive(product),
              icon: const Icon(Icons.archive_outlined),
              tooltip: 'Archive product',
            ),
        ],
      ),
      body: _error != null
          ? ErrorState(message: 'Product could not be loaded.', onRetry: _load)
          : product == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                if (product.archivedAt != null) ...[
                  Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: const ListTile(
                      leading: Icon(Icons.archive_outlined),
                      title: Text('This product is archived'),
                      subtitle: Text(
                        'Restore it to return it to active inventory.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                Center(
                  child: ProductImage(
                    path: product.imagePath,
                    size: 210,
                    borderRadius: 24,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 10),
                    StockBadge(quantity: product.quantity),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  pesoFormat.format(product.price),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 22),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        _Info(
                          icon: Icons.qr_code,
                          label: 'Barcode',
                          value: product.barcode,
                        ),
                        const Divider(height: 28),
                        _Info(
                          icon: Icons.category_outlined,
                          label: 'Category',
                          value: product.category,
                        ),
                        const Divider(height: 28),
                        _Info(
                          icon: Icons.inventory_2_outlined,
                          label: 'Stock',
                          value: '${product.quantity} units',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Description',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  product.description.isEmpty
                      ? 'No description provided.'
                      : product.description,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 26),
                Text(
                  'Stock history',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (_transactions.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'No stock adjustments have been recorded yet.',
                      ),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < _transactions.length; i++) ...[
                          _TransactionTile(transaction: _transactions[i]),
                          if (i != _transactions.length - 1)
                            const Divider(height: 1, indent: 16, endIndent: 16),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 28),
                if (product.archivedAt == null) ...[
                  FilledButton.icon(
                    onPressed: () async {
                      final changed = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditProductScreen(
                            service: widget.service,
                            product: product,
                          ),
                        ),
                      );
                      if (changed != null) _load();
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Product'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final updated = await showDialog<Product>(
                        context: context,
                        builder: (_) => StockAdjustmentDialog(
                          service: widget.service,
                          product: product,
                        ),
                      );
                      if (updated != null) await _load();
                    },
                    icon: const Icon(Icons.swap_vert),
                    label: const Text('Adjust Stock'),
                  ),
                ] else ...[
                  FilledButton.icon(
                    onPressed: () => _restore(product),
                    icon: const Icon(Icons.unarchive_outlined),
                    label: const Text('Restore Product'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () => _deletePermanently(product),
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Delete Permanently'),
                  ),
                ],
              ],
            ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction});
  final StockTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final added = transaction.delta >= 0;
    final amount = '${added ? '+' : ''}${transaction.delta}';
    return ListTile(
      leading: CircleAvatar(child: Icon(added ? Icons.add : Icons.remove)),
      title: Row(
        children: [
          Expanded(child: Text(transaction.reason)),
          Text(
            amount,
            style: TextStyle(
              color: added
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      subtitle: Text(
        [
          '${transaction.previousQuantity} → ${transaction.resultingQuantity}',
          DateFormat('MMM d, yyyy • h:mm a').format(transaction.occurredAt),
          if (transaction.note.isNotEmpty) transaction.note,
        ].join('\n'),
      ),
      isThreeLine: transaction.note.isNotEmpty,
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ],
  );
}
