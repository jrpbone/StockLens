import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/product.dart';
import '../../repositories/product_repository.dart';
import '../../services/product_service.dart';
import '../../widgets/product_image.dart';

class ProductForm extends StatefulWidget {
  const ProductForm({
    super.key,
    required this.service,
    this.product,
    this.initialBarcode,
  });
  final ProductService service;
  final Product? product;
  final String? initialBarcode;

  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _barcode;
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _category;
  late final TextEditingController _quantity;
  late final TextEditingController _description;
  String? _imagePath;
  bool _saving = false;

  bool get _editing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _barcode = TextEditingController(
      text: p?.barcode ?? widget.initialBarcode ?? '',
    );
    _name = TextEditingController(text: p?.name ?? '');
    _price = TextEditingController(text: p?.price.toStringAsFixed(2) ?? '');
    _category = TextEditingController(text: p?.category ?? '');
    _quantity = TextEditingController(text: p?.quantity.toString() ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _imagePath = p?.imagePath;
  }

  @override
  void dispose() {
    for (final controller in [
      _barcode,
      _name,
      _price,
      _category,
      _quantity,
      _description,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value, String label) =>
      value == null || value.trim().isEmpty ? '$label is required.' : null;

  Future<void> _pickImage() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1600,
      );
      if (image != null && mounted) setState(() => _imagePath = image.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product image could not be selected.')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final old = widget.product;
    if (old != null && old.barcode != _barcode.text.trim()) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Change barcode?'),
          content: const Text(
            'The barcode identifies this product during scanning. Change it only if the current value is incorrect.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep current'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Change barcode'),
            ),
          ],
        ),
      );
      if (proceed != true) {
        _barcode.text = old.barcode;
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final Product saved;
      if (old == null) {
        saved = await widget.service.add(
          barcode: _barcode.text,
          name: _name.text,
          price: double.parse(_price.text),
          category: _category.text,
          quantity: int.parse(_quantity.text),
          description: _description.text,
          imagePath: _imagePath,
        );
      } else {
        saved = await widget.service.update(
          old.copyWith(
            barcode: _barcode.text.trim(),
            name: _name.text.trim(),
            price: double.parse(_price.text),
            category: _category.text.trim().isEmpty
                ? 'Uncategorized'
                : _category.text.trim(),
            quantity: int.parse(_quantity.text),
            description: _description.text.trim(),
            imagePath: _imagePath,
          ),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_editing ? 'Product updated.' : 'Product saved.'),
        ),
      );
      Navigator.pop(context, saved.id);
    } on DuplicateBarcodeException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Barcode already exists.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product could not be saved. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ProductImage(path: _imagePath, size: 132, borderRadius: 22),
              Positioned(
                right: -6,
                bottom: -6,
                child: IconButton.filled(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  tooltip: 'Choose image',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        TextFormField(
          controller: _barcode,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Barcode',
            prefixIcon: Icon(Icons.qr_code),
          ),
          validator: (v) => _required(v, 'Barcode'),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Product Name',
            prefixIcon: Icon(Icons.sell_outlined),
          ),
          validator: (v) => _required(v, 'Product name'),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          decoration: const InputDecoration(
            labelText: 'Price',
            prefixText: '₱ ',
          ),
          validator: (v) {
            final value = double.tryParse(v ?? '');
            return value == null || value < 0
                ? 'Enter a valid price of 0 or more.'
                : null;
          },
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _category,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Category',
            prefixIcon: Icon(Icons.category_outlined),
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _quantity,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Quantity',
            prefixIcon: Icon(Icons.numbers),
          ),
          validator: (v) {
            final value = int.tryParse(v ?? '');
            return value == null || value < 0
                ? 'Enter a whole number of 0 or more.'
                : null;
          },
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _description,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description',
            alignLabelWithHint: true,
            prefixIcon: Icon(Icons.notes),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_editing ? 'Save Changes' : 'Save Product'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
