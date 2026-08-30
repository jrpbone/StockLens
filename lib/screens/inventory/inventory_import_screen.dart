import 'package:flutter/material.dart';

import '../../core/widgets/async_state.dart';
import '../../models/inventory_import.dart';
import '../../services/inventory_import_service.dart';

class InventoryImportScreen extends StatefulWidget {
  const InventoryImportScreen({
    super.key,
    required this.service,
    required this.csvContent,
  });

  final InventoryImportService service;
  final String csvContent;

  @override
  State<InventoryImportScreen> createState() => _InventoryImportScreenState();
}

class _InventoryImportScreenState extends State<InventoryImportScreen> {
  InventoryImportPreview? _preview;
  Object? _error;
  var _loading = true;
  var _applying = false;
  var _applied = false;

  @override
  void initState() {
    super.initState();
    _refreshPreview();
  }

  Future<void> _refreshPreview() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preview = await widget.service.preview(widget.csvContent);
      if (!mounted) return;
      setState(() {
        _preview = preview;
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

  Future<void> _confirmApply() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply inventory import?'),
        content: const Text(
          'All listed product and stock changes will be saved together. This cannot be partially applied.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _apply();
  }

  Future<void> _apply() async {
    final preview = _preview;
    if (preview == null) return;
    setState(() => _applying = true);
    try {
      await widget.service.apply(preview);
      if (!mounted) return;
      setState(() {
        _applying = false;
        _applied = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inventory import applied.')),
      );
    } on StaleInventoryImportException {
      if (!mounted) return;
      setState(() => _applying = false);
      await _refreshPreview();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inventory changed. Review the refreshed preview.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The inventory import could not be applied.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inventory Import')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? ErrorState(
            message: 'The CSV preview could not be created.',
            onRetry: _refreshPreview,
          )
        : _PreviewBody(
            preview: _preview!,
            applying: _applying,
            applied: _applied,
            onApply: _confirmApply,
          ),
  );
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({
    required this.preview,
    required this.applying,
    required this.applied,
    required this.onApply,
  });

  final InventoryImportPreview preview;
  final bool applying;
  final bool applied;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryChip(preview.newProducts.length, 'new product'),
              _SummaryChip(preview.productUpdates.length, 'product update'),
              _SummaryChip(preview.stockChanges.length, 'stock change'),
              _SummaryChip(preview.unchangedRows.length, 'unchanged row'),
              _SummaryChip(preview.blockingErrors.length, 'blocking error'),
            ],
          ),
          if (preview.blockingErrors.isNotEmpty) ...[
            const _SectionTitle('Blocking errors'),
            for (final error in preview.blockingErrors)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(error.toString()),
                ),
              ),
          ],
          _Section(
            title: 'New products',
            rows: preview.newProducts,
            subtitle: (row) => 'Barcode ${row.after.barcode}',
          ),
          _Section(
            title: 'Product updates',
            rows: preview.productUpdates,
            subtitle: (row) => 'Row ${row.candidate.rowNumber}',
          ),
          _Section(
            title: 'Stock changes',
            rows: preview.stockChanges,
            subtitle: (row) =>
                '${row.beforeQuantity} to ${row.afterQuantity} units',
          ),
          _Section(
            title: 'Unchanged rows',
            rows: preview.unchangedRows,
            subtitle: (row) => 'No changes',
          ),
        ],
      ),
      Positioned(
        left: 16,
        right: 16,
        bottom: 16,
        child: SafeArea(
          top: false,
          child: FilledButton.icon(
            onPressed:
                preview.canApply &&
                    preview.rows.isNotEmpty &&
                    !applying &&
                    !applied
                ? onApply
                : null,
            icon: applying
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            label: Text(applied ? 'Import Applied' : 'Apply Import'),
          ),
        ),
      ),
    ],
  );
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip(this.count, this.label);

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Chip(label: Text('$count $label${count == 1 ? '' : 's'}'));
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.rows,
    required this.subtitle,
  });

  final String title;
  final List<InventoryImportRowPreview> rows;
  final String Function(InventoryImportRowPreview row) subtitle;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(title),
        for (final row in rows)
          Card(
            child: ListTile(
              title: Text(row.after.name),
              subtitle: Text(subtitle(row)),
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 4),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}
