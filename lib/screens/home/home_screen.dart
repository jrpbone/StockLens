import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../services/product_service.dart';
import '../add_product/add_product_screen.dart';
import '../alerts/low_stock_alerts_screen.dart';
import '../product_details/product_details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.service,
    required this.onSelectTab,
    this.onEnableLowStockNotifications,
    this.onLowStockNotificationsEnabled,
    this.onOpenLowStockNotificationSettings,
  });
  final ProductService service;
  final ValueChanged<int> onSelectTab;
  final Future<bool> Function()? onEnableLowStockNotifications;
  final Future<bool> Function()? onLowStockNotificationsEnabled;
  final Future<bool> Function()? onOpenLowStockNotificationSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final products = await widget.service.products();
      if (mounted) {
        setState(() {
          _products = products;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowStock = _products.where((product) => product.isLowStock).length;
    final outOfStock = _products
        .where((product) => product.quantity == 0)
        .length;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.document_scanner_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'StockLens',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Scan. Search. Manage.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: 'Products',
                      value: _loading ? '—' : '${_products.length}',
                    ),
                  ),
                  Container(width: 1, height: 44, color: Colors.white24),
                  Expanded(
                    child: _Stat(
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => LowStockAlertsScreen(
                              service: widget.service,
                              onEnableNotifications:
                                  widget.onEnableLowStockNotifications,
                              onNotificationsEnabled:
                                  widget.onLowStockNotificationsEnabled,
                              onOpenNotificationSettings:
                                  widget.onOpenLowStockNotificationSettings,
                            ),
                          ),
                        );
                        if (!mounted) return;
                        await _load();
                      },
                      label: 'Low stock',
                      value: _loading ? '—' : '$lowStock',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Out of stock'),
                const SizedBox(width: 8),
                Text(_loading ? 'Loading' : '$outOfStock'),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              'Quick actions',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [
                _ActionCard(
                  icon: Icons.qr_code_scanner,
                  title: 'Scan Barcode',
                  onTap: () => widget.onSelectTab(1),
                ),
                _ActionCard(
                  icon: Icons.search,
                  title: 'Search Product',
                  onTap: () => widget.onSelectTab(4),
                ),
                _ActionCard(
                  icon: Icons.inventory_2_outlined,
                  title: 'Inventory',
                  onTap: () => widget.onSelectTab(3),
                ),
                _ActionCard(
                  icon: Icons.add_box_outlined,
                  title: 'Add Product',
                  onTap: () async {
                    final id = await Navigator.of(context).push<String>(
                      MaterialPageRoute(
                        builder: (_) =>
                            AddProductScreen(service: widget.service),
                      ),
                    );
                    if (!context.mounted || id == null) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProductDetailsScreen(
                          service: widget.service,
                          productId: id,
                        ),
                      ),
                    );
                    _load();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    ),
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}
