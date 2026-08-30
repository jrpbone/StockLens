import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product.dart';
import '../../models/stocktake_item.dart';
import '../../models/stocktake_session.dart';
import '../../services/product_service.dart';
import '../../services/stocktake_service.dart';
import 'stocktake_review_screen.dart';
import 'stocktake_scan_screen.dart';

class StocktakeCountScreen extends StatefulWidget {
  const StocktakeCountScreen({
    super.key,
    required this.stocktakeService,
    required this.productService,
    required this.sessionId,
  });

  final StocktakeService stocktakeService;
  final ProductService productService;
  final String sessionId;

  @override
  State<StocktakeCountScreen> createState() => _StocktakeCountScreenState();
}

class _StocktakeCountScreenState extends State<StocktakeCountScreen> {
  StocktakeSession? _session;
  Map<String, Product> _products = const {};
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, Future<void>> _saveQueues = {};
  Object? _error;
  bool _zeroFilling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final session = await widget.stocktakeService.session(widget.sessionId);
      final productList = await Future.wait(
        session.items.map((item) => widget.productService.byId(item.productId)),
      );
      if (productList.any((product) => product == null)) {
        throw StateError('A stocktake product is no longer available.');
      }
      if (!mounted) return;
      for (final item in session.items) {
        final text = item.countedQuantity?.toString() ?? '';
        final controller = _controllers.putIfAbsent(
          item.productId,
          TextEditingController.new,
        );
        if (controller.text != text) controller.text = text;
      }
      setState(() {
        _session = session;
        _products = {
          for (final product in productList.cast<Product>())
            product.id: product,
        };
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _countChanged(StocktakeItem item, String value) {
    final count = int.tryParse(value);
    if (count == null || count < 0) return;
    final session = _session;
    if (session == null || session.status == StocktakeStatus.completed) return;
    setState(() {
      _session = session.copyWith(
        items: [
          for (final current in session.items)
            if (current.productId == item.productId)
              current.copyWith(countedQuantity: count)
            else
              current,
        ],
      );
    });
    _queueSave(item.productId, count);
  }

  void _queueSave(String productId, int count) {
    final previous = _saveQueues[productId] ?? Future<void>.value();
    final pending = previous.then(
      (_) =>
          widget.stocktakeService.setCount(widget.sessionId, productId, count),
      onError: (_) =>
          widget.stocktakeService.setCount(widget.sessionId, productId, count),
    );
    _saveQueues[productId] = pending;
    unawaited(
      pending
          .then((_) {
            if (identical(_saveQueues[productId], pending)) {
              _saveQueues.remove(productId);
            }
          })
          .catchError((Object _) {
            if (identical(_saveQueues[productId], pending)) {
              _saveQueues.remove(productId);
            }
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('The count could not be saved.')),
            );
            _load();
          }),
    );
  }

  Future<void> _waitForSaves() async {
    while (_saveQueues.isNotEmpty) {
      await Future.wait(_saveQueues.values.toList());
    }
  }

  Future<void> _scan() async {
    await _waitForSaves();
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => StocktakeScanScreen(
          stocktakeService: widget.stocktakeService,
          sessionId: widget.sessionId,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _setRemainingToZero() async {
    final remaining = _remaining;
    if (remaining == 0 || _zeroFilling) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          remaining == 1
              ? 'Set 1 remaining item to zero?'
              : 'Set $remaining remaining items to zero?',
        ),
        content: const Text(
          'Only items without a count will be set to zero. Entered counts will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Set to zero'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _zeroFilling = true);
    try {
      await _waitForSaves();
      await widget.stocktakeService.setRemainingToZero(widget.sessionId);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Remaining counts could not be saved.')),
        );
      }
    } finally {
      if (mounted) setState(() => _zeroFilling = false);
    }
  }

  Future<void> _review() async {
    if (_remaining != 0) return;
    try {
      await _waitForSaves();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => StocktakeReviewScreen(
          stocktakeService: widget.stocktakeService,
          productService: widget.productService,
          sessionId: widget.sessionId,
        ),
      ),
    );
    if (mounted) await _load();
  }

  int get _remaining =>
      _session?.items.where((item) => item.countedQuantity == null).length ?? 0;

  int get _counted => (_session?.items.length ?? 0) - _remaining;

  int get _variance =>
      _session?.items.fold<int>(
        0,
        (sum, item) =>
            sum +
            (item.countedQuantity == null
                ? 0
                : item.countedQuantity! - item.expectedQuantity),
      ) ??
      0;

  String _quantityLabel(int value) => value > 0 ? '+$value' : '$value';

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        title: Text(session?.name ?? 'Stocktake count'),
        actions: [
          if (session?.status == StocktakeStatus.inProgress)
            IconButton(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Scan stocktake item',
            ),
        ],
      ),
      body: session == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: FilledButton.tonal(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 130),
              children: [
                Text(session.scopeDescription),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _SummaryCard(label: '$_counted counted')),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryCard(label: '$_remaining remaining'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryCard(
                        label: 'Variance ${_quantityLabel(_variance)}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final item in session.items)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _products[item.productId]?.name ??
                                      item.productId,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text('Expected ${item.expectedQuantity}'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 92,
                            child: TextField(
                              key: Key('count-${item.productId}'),
                              controller: _controllers[item.productId],
                              enabled:
                                  session.status == StocktakeStatus.inProgress,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Count',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (value) => _countChanged(item, value),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: session == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_remaining > 0 &&
                      session.status == StocktakeStatus.inProgress)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _zeroFilling ? null : _setRemainingToZero,
                        child: const Text('Set remaining to zero'),
                      ),
                    ),
                  if (_remaining > 0) const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _remaining == 0 ? _review : null,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Review changes'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge,
      ),
    ),
  );
}
