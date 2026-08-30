import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../services/product_service.dart';
import '../product_details/product_details_screen.dart';

class LowStockAlertsScreen extends StatefulWidget {
  const LowStockAlertsScreen({
    super.key,
    required this.service,
    this.onEnableNotifications,
    this.onNotificationsEnabled,
    this.onOpenNotificationSettings,
  });

  final ProductService service;
  final Future<bool> Function()? onEnableNotifications;
  final Future<bool> Function()? onNotificationsEnabled;
  final Future<bool> Function()? onOpenNotificationSettings;

  @override
  State<LowStockAlertsScreen> createState() => _LowStockAlertsScreenState();
}

class _LowStockAlertsScreenState extends State<LowStockAlertsScreen> {
  List<Product>? _products;
  Object? _error;
  bool? _notificationsEnabled;
  bool _showSettingsRecovery = false;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshNotificationStatus();
  }

  Future<void> _load() async {
    try {
      final products = await widget.service.lowStockProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _enableNotifications() async {
    final request = widget.onEnableNotifications;
    if (request == null) return;
    try {
      final granted = await request();
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = granted;
        _showSettingsRecovery = !granted;
      });
      if (granted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications were not enabled.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = false;
        _showSettingsRecovery = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications could not be enabled.')),
      );
    }
  }

  Future<void> _refreshNotificationStatus() async {
    final check = widget.onNotificationsEnabled;
    if (check == null) return;
    try {
      final enabled = await check();
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = enabled;
        if (enabled) _showSettingsRecovery = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = false;
        _showSettingsRecovery = true;
      });
    }
  }

  Future<void> _openNotificationSettings() async {
    final open = widget.onOpenNotificationSettings;
    if (open == null) return;
    try {
      final opened = await open();
      if (!mounted || opened) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification settings could not open.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification settings could not open.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Low-stock alerts')),
    body: _body(context),
  );

  Widget _body(BuildContext context) {
    final products = _products;
    if (products == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && products == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load low-stock alerts.'),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if ((widget.onEnableNotifications != null ||
                  widget.onOpenNotificationSettings != null) &&
              _notificationsEnabled != true)
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.onEnableNotifications != null)
                    OutlinedButton.icon(
                      onPressed: _enableNotifications,
                      icon: const Icon(Icons.notifications_outlined),
                      label: const Text('Enable notifications'),
                    ),
                  if (widget.onOpenNotificationSettings != null &&
                      (_notificationsEnabled == false ||
                          _showSettingsRecovery ||
                          widget.onEnableNotifications == null))
                    TextButton.icon(
                      onPressed: _openNotificationSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Open settings'),
                    ),
                ],
              ),
            ),
          if (products!.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: Text('No low-stock products right now.')),
            )
          else
            for (final product in products)
              _AlertProductTile(
                service: widget.service,
                product: product,
                onReturn: _load,
              ),
        ],
      ),
    );
  }
}

class _AlertProductTile extends StatelessWidget {
  const _AlertProductTile({
    required this.service,
    required this.product,
    required this.onReturn,
  });

  final ProductService service;
  final Product product;
  final Future<void> Function() onReturn;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(product.name),
      subtitle: Text(product.quantity == 0 ? 'Out of stock' : 'Low stock'),
      trailing: Text('${product.quantity} in stock'),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ProductDetailsScreen(service: service, productId: product.id),
          ),
        );
        if (!context.mounted) return;
        await onReturn();
      },
    ),
  );
}
