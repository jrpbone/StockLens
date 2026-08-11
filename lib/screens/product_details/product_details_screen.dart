import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/async_state.dart';
import '../../models/product.dart';
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
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final product = await widget.service.byId(widget.productId);
      if (mounted) {
        setState(() {
          _product = product;
          _error = product == null ? 'not found' : null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    return Scaffold(
      appBar: AppBar(title: const Text('Product Details')),
      body: _error != null
          ? ErrorState(message: 'Product could not be loaded.', onRetry: _load)
          : product == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
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
                const SizedBox(height: 28),
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
                    if (updated != null && mounted) {
                      setState(() => _product = updated);
                    }
                  },
                  icon: const Icon(Icons.swap_vert),
                  label: const Text('Adjust Stock'),
                ),
              ],
            ),
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
