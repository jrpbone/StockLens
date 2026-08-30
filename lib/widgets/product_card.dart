import 'package:flutter/material.dart';

import '../core/utils/formatters.dart';
import '../models/product.dart';
import 'product_image.dart';
import 'stock_badge.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ProductImage(path: product.imagePath),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    product.category,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        pesoFormat.format(product.sellingPrice),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${product.quantity}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(width: 6),
                      StockBadge(quantity: product.quantity),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
