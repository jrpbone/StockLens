import 'package:flutter/material.dart';

import '../../services/inventory_file_service.dart';
import '../../services/product_service.dart';

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key, required this.service});
  final ProductService service;

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  final _files = const InventoryFileService();
  bool _working = false;

  Future<void> _run(Future<void> Function() action, String failure) async {
    setState(() => _working = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure)));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text(
          'The selected backup will replace all current products and stock history. Export a fresh backup first if you may need the current data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose Backup'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () async {
        final restored = await _files.pickAndRestoreBackup(widget.service);
        if (restored && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup restored successfully.')),
          );
        }
      },
      'The backup could not be restored. Check that it is a valid StockLens backup.',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Data & Backups')),
    body: Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  ListTile(
                    enabled: !_working,
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('Export Complete Backup'),
                    subtitle: const Text(
                      'Products, images, archives, and stock history',
                    ),
                    trailing: const Icon(Icons.share_outlined),
                    onTap: () => _run(
                      () => _files.shareBackup(widget.service),
                      'The backup could not be exported.',
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    enabled: !_working,
                    leading: const Icon(Icons.restore),
                    title: const Text('Restore Backup'),
                    subtitle: const Text(
                      'Replace current data from a StockLens backup',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _restore,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                enabled: !_working,
                leading: const Icon(Icons.table_view_outlined),
                title: const Text('Export Inventory CSV'),
                subtitle: const Text('Share active and archived product data'),
                trailing: const Icon(Icons.share_outlined),
                onTap: () => _run(
                  () => _files.shareCsv(widget.service),
                  'The CSV export could not be created.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Backup files can contain product photos and business information. Store them somewhere private.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        if (_working) const LinearProgressIndicator(minHeight: 3),
      ],
    ),
  );
}
