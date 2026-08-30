import 'package:flutter/material.dart';

import '../../core/widgets/async_state.dart';
import '../../models/product.dart';
import '../../repositories/product_repository.dart';
import '../../services/inventory_report_service.dart';
import '../../services/inventory_import_service.dart';
import '../../services/product_service.dart';
import '../../services/stocktake_service.dart';
import '../../widgets/custom_search_bar.dart';
import '../../widgets/product_card.dart';
import '../add_product/add_product_screen.dart';
import '../product_details/product_details_screen.dart';
import '../reports/inventory_reports_screen.dart';
import '../stocktake/stocktake_sessions_screen.dart';
import 'archived_products_screen.dart';
import 'data_management_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.service,
    this.stocktakeService,
    this.reportService,
    this.importService,
  });
  final ProductService service;
  final StocktakeService? stocktakeService;
  final InventoryReportService? reportService;
  final InventoryImportService? importService;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _search = TextEditingController();
  List<Product> _products = [];
  List<String> _categories = [];
  String? _category;
  ProductSort _sort = ProductSort.nameAsc;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.service.products(
          query: _search.text,
          category: _category,
          sort: _sort,
        ),
        widget.service.categories(),
      ]);
      if (mounted) {
        setState(() {
          _products = results[0] as List<Product>;
          _categories = results[1] as List<String>;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(Product product) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailsScreen(
          service: widget.service,
          productId: product.id,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Inventory'),
      actions: [
        if (widget.stocktakeService != null)
          IconButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => StocktakeSessionsScreen(
                    stocktakeService: widget.stocktakeService!,
                    productService: widget.service,
                  ),
                ),
              );
              _load();
            },
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: 'Stocktake',
          ),
        if (widget.reportService != null)
          IconButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    InventoryReportsScreen(service: widget.reportService!),
              ),
            ),
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'Reports',
          ),
        IconButton(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DataManagementScreen(
                  service: widget.service,
                  importService: widget.importService,
                ),
              ),
            );
            _load();
          },
          icon: const Icon(Icons.settings_backup_restore),
          tooltip: 'Data and backups',
        ),
        IconButton(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ArchivedProductsScreen(service: widget.service),
              ),
            );
            _load();
          },
          icon: const Icon(Icons.archive_outlined),
          tooltip: 'Archived products',
        ),
        PopupMenuButton<ProductSort>(
          initialValue: _sort,
          tooltip: 'Sort products',
          icon: const Icon(Icons.sort),
          onSelected: (value) {
            _sort = value;
            _load();
          },
          itemBuilder: (_) => ProductSort.values
              .map(
                (value) =>
                    PopupMenuItem(value: value, child: Text(_sortLabel(value))),
              )
              .toList(),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        final id = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => AddProductScreen(service: widget.service),
          ),
        );
        if (id != null) _load();
      },
      icon: const Icon(Icons.add),
      label: const Text('Add Product'),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            children: [
              CustomSearchBar(
                controller: _search,
                onChanged: (_) {
                  setState(() {});
                  _load();
                },
                hint: 'Name, barcode, or category',
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  prefixIcon: Icon(Icons.filter_list),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All categories'),
                  ),
                  ..._categories.map(
                    (c) => DropdownMenuItem<String?>(value: c, child: Text(c)),
                  ),
                ],
                onChanged: (value) {
                  _category = value;
                  _load();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? ErrorState(
                  message: 'Inventory could not be loaded.',
                  onRetry: _load,
                )
              : _products.isEmpty
              ? const _EmptyInventory()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: _products.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) => ProductCard(
                      product: _products[index],
                      onTap: () => _open(_products[index]),
                    ),
                  ),
                ),
        ),
      ],
    ),
  );

  String _sortLabel(ProductSort sort) => switch (sort) {
    ProductSort.nameAsc => 'Product Name A–Z',
    ProductSort.nameDesc => 'Product Name Z–A',
    ProductSort.priceAsc => 'Price Low to High',
    ProductSort.priceDesc => 'Price High to Low',
    ProductSort.stockAsc => 'Lowest Stock',
    ProductSort.stockDesc => 'Highest Stock',
    ProductSort.newest => 'Newest',
  };
}

class _EmptyInventory extends StatelessWidget {
  const _EmptyInventory();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'No products found.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    ),
  );
}
