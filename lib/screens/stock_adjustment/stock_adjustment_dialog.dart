import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product.dart';
import '../../services/product_service.dart';

class StockAdjustmentDialog extends StatefulWidget {
  const StockAdjustmentDialog({
    super.key,
    required this.service,
    required this.product,
  });
  final ProductService service;
  final Product product;

  @override
  State<StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<StockAdjustmentDialog> {
  final _amount = TextEditingController(text: '1');
  String _reason = 'Restock';
  bool _adding = true;
  bool _saving = false;
  static const reasons = [
    'Restock',
    'Sale',
    'Damaged Item',
    'Expired Item',
    'Inventory Correction',
    'Other',
  ];

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final amount = int.tryParse(_amount.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an adjustment greater than zero.')),
      );
      return;
    }
    final delta = _adding ? amount : -amount;
    if (widget.product.quantity + delta < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock cannot become negative.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await widget.service.adjustStock(widget.product, delta);
      if (mounted) Navigator.pop(context, updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock could not be updated.')),
        );
      }
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Adjust Stock'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current stock', style: Theme.of(context).textTheme.labelLarge),
          Text(
            '${widget.product.quantity} units',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.remove),
                label: Text('Remove'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.add),
                label: Text('Add'),
              ),
            ],
            selected: {_adding},
            onSelectionChanged: (v) => setState(() => _adding = v.first),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Quantity',
              prefixIcon: Icon(Icons.numbers),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            decoration: const InputDecoration(
              labelText: 'Reason',
              prefixIcon: Icon(Icons.assignment_outlined),
            ),
            items: reasons
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) => setState(() => _reason = v!),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _confirm,
        child: const Text('Confirm'),
      ),
    ],
  );
}
