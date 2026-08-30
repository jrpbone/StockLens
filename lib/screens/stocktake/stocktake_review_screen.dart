import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../models/stocktake_session.dart';
import '../../repositories/stocktake_repository.dart';
import '../../services/product_service.dart';
import '../../services/stocktake_service.dart';

class StocktakeReviewScreen extends StatefulWidget {
  const StocktakeReviewScreen({
    super.key,
    required this.stocktakeService,
    required this.productService,
    required this.sessionId,
  });

  final StocktakeService stocktakeService;
  final ProductService productService;
  final String sessionId;

  @override
  State<StocktakeReviewScreen> createState() => _StocktakeReviewScreenState();
}

class _StocktakeReviewScreenState extends State<StocktakeReviewScreen> {
  StocktakeSession? _session;
  StocktakeCompletionPreview? _preview;
  Map<String, Product> _products = const {};
  Object? _error;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final session = await widget.stocktakeService.session(widget.sessionId);
      final preview = await widget.stocktakeService.previewCompletion(
        widget.sessionId,
      );
      final productList = await Future.wait(
        preview.lines.map(
          (line) => widget.productService.byId(line.item.productId),
        ),
      );
      if (!mounted) return;
      setState(() {
        _session = session;
        _preview = preview;
        _products = {
          for (final product in productList.whereType<Product>())
            product.id: product,
        };
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _complete() async {
    final preview = _preview;
    if (preview == null || preview.unresolvedCount != 0 || _completing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply these inventory corrections?'),
        content: const Text(
          'Product quantities will be reconciled atomically to the counted values.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _completing = true);
    try {
      await widget.stocktakeService.complete(widget.sessionId, preview);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Stocktake completed')));
      }
    } on StaleStocktakeCompletionException {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Inventory changed again. Review the latest quantities.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The stocktake could not be completed.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  String _signed(int value) => value > 0 ? '+$value' : '$value';

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Review stocktake')),
      body: session == null || preview == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: FilledButton.tonal(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
              children: [
                Text(
                  session.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(session.scopeDescription),
                const SizedBox(height: 16),
                if (session.status == StocktakeStatus.completed)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.check_circle_outline),
                      title: Text('Stocktake completed'),
                      subtitle: Text('This session is read-only.'),
                    ),
                  ),
                if (preview.unresolvedCount > 0)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_outlined),
                      title: Text('${preview.unresolvedCount} remaining'),
                      subtitle: const Text(
                        'Count every item or explicitly set remaining items to zero.',
                      ),
                    ),
                  ),
                for (final line in preview.lines)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _products[line.item.productId]?.name ??
                                line.item.productId,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (line.changedSinceStart) ...[
                            const SizedBox(height: 8),
                            const Row(
                              children: [
                                Icon(Icons.warning_amber_outlined, size: 18),
                                SizedBox(width: 6),
                                Text('Changed during count'),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              Text('Expected ${line.item.expectedQuantity}'),
                              Text('Current ${line.currentQuantity}'),
                              Text('Counted ${line.item.countedQuantity}'),
                              Text('Variance ${_signed(line.variance)}'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar:
          session == null ||
              preview == null ||
              session.status == StocktakeStatus.completed
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: preview.unresolvedCount == 0 && !_completing
                    ? _complete
                    : null,
                icon: _completing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.done_all),
                label: const Text('Complete stocktake'),
              ),
            ),
    );
  }
}
