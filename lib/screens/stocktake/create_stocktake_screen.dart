import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../services/stocktake_service.dart';

enum StocktakeScopeType { all, categories, products }

class CreateStocktakeScreen extends StatefulWidget {
  const CreateStocktakeScreen({
    super.key,
    required this.stocktakeService,
    required this.productService,
  });

  final StocktakeService stocktakeService;
  final ProductService productService;

  @override
  State<CreateStocktakeScreen> createState() => _CreateStocktakeScreenState();
}

class _CreateStocktakeScreenState extends State<CreateStocktakeScreen> {
  List<Product>? _products;
  List<String> _categories = const [];
  StocktakeScopeType _scope = StocktakeScopeType.all;
  final Set<String> _selectedCategories = {};
  final Set<String> _selectedProductIds = {};
  Object? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final products = await widget.productService.products();
      final categories = await widget.productService.categories();
      if (!mounted) return;
      setState(() {
        _products = products;
        _categories = categories;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  List<Product> get _selectedProducts {
    final products = _products ?? const <Product>[];
    return switch (_scope) {
      StocktakeScopeType.all => products,
      StocktakeScopeType.categories =>
        products
            .where((product) => _selectedCategories.contains(product.category))
            .toList(growable: false),
      StocktakeScopeType.products =>
        products
            .where((product) => _selectedProductIds.contains(product.id))
            .toList(growable: false),
    };
  }

  String get _name => switch (_scope) {
    StocktakeScopeType.all => 'Full inventory count',
    StocktakeScopeType.categories when _selectedCategories.length == 1 =>
      '${_selectedCategories.single} count',
    StocktakeScopeType.categories => 'Category stocktake',
    StocktakeScopeType.products => 'Selected products count',
  };

  String get _scopeDescription => switch (_scope) {
    StocktakeScopeType.all => 'All active products',
    StocktakeScopeType.categories =>
      'Category: ${(_selectedCategories.toList()..sort()).join(', ')}',
    StocktakeScopeType.products =>
      'Selected products: ${_selectedProducts.length}',
  };

  Future<void> _start() async {
    final selected = _selectedProducts;
    if (selected.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final session = await widget.stocktakeService.create(
        name: _name,
        productIds: selected.map((product) => product.id).toList(),
        scopeDescription: _scopeDescription,
      );
      if (mounted) Navigator.pop(context, session);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The stocktake could not be started.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New Stocktake')),
    body: _products == null
        ? _error == null
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: FilledButton.tonal(
                    onPressed: _load,
                    child: const Text('Retry'),
                  ),
                )
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              Text(
                'Choose scope',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SegmentedButton<StocktakeScopeType>(
                segments: const [
                  ButtonSegment(
                    value: StocktakeScopeType.all,
                    label: Text('All'),
                    icon: Icon(Icons.inventory_2_outlined),
                  ),
                  ButtonSegment(
                    value: StocktakeScopeType.categories,
                    label: Text('Categories'),
                    icon: Icon(Icons.category_outlined),
                  ),
                  ButtonSegment(
                    value: StocktakeScopeType.products,
                    label: Text('Products'),
                    icon: Icon(Icons.checklist),
                  ),
                ],
                selected: {_scope},
                onSelectionChanged: (selection) {
                  setState(() => _scope = selection.single);
                },
              ),
              const SizedBox(height: 20),
              if (_scope == StocktakeScopeType.all)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.select_all),
                  title: Text('All active products'),
                  subtitle: Text(
                    'Counts every product currently in inventory.',
                  ),
                ),
              if (_scope == StocktakeScopeType.categories) ...[
                Text(
                  'Select categories',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _categories
                      .map(
                        (category) => FilterChip(
                          label: Text(category),
                          selected: _selectedCategories.contains(category),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedCategories.add(category);
                              } else {
                                _selectedCategories.remove(category);
                              }
                            });
                          },
                        ),
                      )
                      .toList(),
                ),
              ],
              if (_scope == StocktakeScopeType.products) ...[
                Text(
                  'Select products',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                for (final product in _products!)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(product.name),
                    subtitle: Text(product.barcode),
                    value: _selectedProductIds.contains(product.id),
                    onChanged: (selected) {
                      setState(() {
                        if (selected ?? false) {
                          _selectedProductIds.add(product.id);
                        } else {
                          _selectedProductIds.remove(product.id);
                        }
                      });
                    },
                  ),
              ],
              const SizedBox(height: 20),
              Text(
                _selectionLabel(_selectedProducts.length),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(_name),
            ],
          ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(16),
      child: FilledButton.icon(
        onPressed: _selectedProducts.isEmpty || _saving ? null : _start,
        icon: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_arrow),
        label: const Text('Start Stocktake'),
      ),
    ),
  );

  String _selectionLabel(int count) =>
      count == 1 ? '1 product selected' : '$count products selected';
}
