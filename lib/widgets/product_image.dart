import 'dart:io';

import 'package:flutter/material.dart';

class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    this.path,
    this.size = 64,
    this.borderRadius = 14,
  });
  final String? path;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: size,
        height: size,
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: file != null && file.existsSync()
            ? Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _placeholder(context),
              )
            : _placeholder(context),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => Icon(
    Icons.inventory_2_outlined,
    size: size * .42,
    color: Theme.of(context).colorScheme.onSecondaryContainer,
  );
}
