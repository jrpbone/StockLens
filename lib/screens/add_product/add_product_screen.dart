import 'package:flutter/material.dart';

import '../../services/product_service.dart';
import 'product_form.dart';

class AddProductScreen extends StatelessWidget {
  const AddProductScreen({
    super.key,
    required this.service,
    this.initialBarcode,
  });
  final ProductService service;
  final String? initialBarcode;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add Product')),
    body: ProductForm(service: service, initialBarcode: initialBarcode),
  );
}
