import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../widgets/custom_search_bar.dart';
import '../../widgets/product_card.dart';
import '../product_details/product_details_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.service});
  final ProductService service;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<Product> _results = [];
  bool _loading = false;
  int _request = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    final request = ++_request;
    try {
      final results = await widget.service.products(query: query);
      if (mounted && request == _request) {
        setState(() {
          _results = results;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Search could not be completed.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Search Product')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: CustomSearchBar(
            controller: _controller,
            onChanged: (value) {
              setState(() {});
              _search(value);
            },
            hint: 'Search name, barcode, or category',
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _controller.text.trim().isEmpty
              ? const _SearchPrompt()
              : _results.isEmpty && !_loading
              ? const Center(child: Text('No products found.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) => ProductCard(
                    product: _results[index],
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProductDetailsScreen(
                            service: widget.service,
                            productId: _results[index].id,
                          ),
                        ),
                      );
                      _search(_controller.text);
                    },
                  ),
                ),
        ),
      ],
    ),
  );
}

class _SearchPrompt extends StatelessWidget {
  const _SearchPrompt();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.manage_search,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 14),
          const Text(
            'Find products by name, barcode, or category.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
