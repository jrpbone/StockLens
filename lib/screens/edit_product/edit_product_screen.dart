import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../services/product_service.dart';
import '../add_product/product_form.dart';

class EditProductScreen extends StatelessWidget {
  const EditProductScreen({
    super.key,
    required this.service,
    required this.product,
  });
  final ProductService service;
  final Product product;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit Product')),
    body: ProductForm(service: service, product: product),
  );
}
