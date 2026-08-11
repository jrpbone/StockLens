import 'package:flutter/material.dart';

import '../../core/widgets/async_state.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../widgets/custom_search_bar.dart';
import '../../widgets/product_card.dart';
import '../product_details/product_details_screen.dart';

class ArchivedProductsScreen extends StatefulWidget {
  const ArchivedProductsScreen({super.key, required this.service});
  final ProductService service;

  @override
  State<ArchivedProductsScreen> createState() => _ArchivedProductsScreenState();
}

class _ArchivedProductsScreenState extends State<ArchivedProductsScreen> {
  final _search = TextEditingController();
  List<Product> _products = [];
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
      final products = await widget.service.archivedProducts(
        query: _search.text,
      );
      if (mounted) {
        setState(() {
          _products = products;
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Archived Products')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: CustomSearchBar(
            controller: _search,
            onChanged: (_) => _load(),
            hint: 'Search archived products',
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? ErrorState(
                  message: 'Archived products could not be loaded.',
                  onRetry: _load,
                )
              : _products.isEmpty
              ? const Center(child: Text('No archived products.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: _products.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) => ProductCard(
                      product: _products[index],
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProductDetailsScreen(
                              service: widget.service,
                              productId: _products[index].id,
                            ),
                          ),
                        );
                        _load();
                      },
                    ),
                  ),
                ),
        ),
      ],
    ),
  );
}
