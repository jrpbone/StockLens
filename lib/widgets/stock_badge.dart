import 'package:flutter/material.dart';

class StockBadge extends StatelessWidget {
  const StockBadge({super.key, required this.quantity});
  final int quantity;

  @override
  Widget build(BuildContext context) {
    final (label, color) = quantity == 0
        ? ('Out of Stock', Theme.of(context).colorScheme.error)
        : quantity <= 5
        ? ('Low Stock', Colors.orange.shade800)
        : ('In Stock', Colors.green.shade700);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
