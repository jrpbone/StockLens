import 'package:flutter/material.dart';

import '../../services/inventory_file_service.dart';
import '../../services/inventory_import_service.dart';
import '../../services/product_service.dart';
import 'inventory_import_screen.dart';

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({
    super.key,
    required this.service,
    this.importService,
    this.fileService = const InventoryFileService(),
  });
  final ProductService service;
  final InventoryImportService? importService;
  final InventoryFileService fileService;

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
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
        final restored = await widget.fileService.pickAndRestoreBackup(
          widget.service,
        );
        if (restored && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup restored successfully.')),
          );
        }
      },
      'The backup could not be restored. Check that it is a valid StockLens backup.',
    );
  }

  Future<void> _importCsv() async {
    setState(() => _working = true);
    try {
      final content = await widget.fileService.pickCsv();
      if (content == null || !mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => InventoryImportScreen(
            service: widget.importService!,
            csvContent: content,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The CSV file could not be opened. Choose a valid UTF-8 CSV up to 20 MB.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
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
                      () => widget.fileService.shareBackup(widget.service),
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
              child: Column(
                children: [
                  if (widget.importService != null) ...[
                    ListTile(
                      enabled: !_working,
                      leading: const Icon(Icons.upload_file_outlined),
                      title: const Text('Import Inventory CSV'),
                      subtitle: const Text(
                        'Preview and atomically apply product changes',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _importCsv,
                    ),
                    const Divider(height: 1),
                  ],
                  ListTile(
                    enabled: !_working,
                    leading: const Icon(Icons.table_view_outlined),
                    title: const Text('Export Inventory CSV'),
                    subtitle: const Text(
                      'Share active and archived product data',
                    ),
                    trailing: const Icon(Icons.share_outlined),
                    onTap: () => _run(
                      () => widget.fileService.shareCsv(widget.service),
                      'The CSV export could not be created.',
                    ),
                  ),
                ],
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
