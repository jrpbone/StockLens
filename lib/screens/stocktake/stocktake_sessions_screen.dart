import 'package:flutter/material.dart';

import '../../models/stocktake_session.dart';
import '../../services/product_service.dart';
import '../../services/stocktake_service.dart';
import 'create_stocktake_screen.dart';
import 'stocktake_count_screen.dart';
import 'stocktake_review_screen.dart';

class StocktakeSessionsScreen extends StatefulWidget {
  const StocktakeSessionsScreen({
    super.key,
    required this.stocktakeService,
    required this.productService,
    this.onOpenSession,
  });

  final StocktakeService stocktakeService;
  final ProductService productService;
  final Future<void> Function(StocktakeSession session)? onOpenSession;

  @override
  State<StocktakeSessionsScreen> createState() =>
      _StocktakeSessionsScreenState();
}

class _StocktakeSessionsScreenState extends State<StocktakeSessionsScreen> {
  List<StocktakeSession>? _sessions;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sessions = await widget.stocktakeService.sessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _create() async {
    final session = await Navigator.push<StocktakeSession>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateStocktakeScreen(
          stocktakeService: widget.stocktakeService,
          productService: widget.productService,
        ),
      ),
    );
    if (!mounted || session == null) return;
    await _load();
    await _openSession(session);
  }

  Future<void> _open(StocktakeSession session) async {
    await _openSession(session);
    if (mounted) await _load();
  }

  Future<void> _openSession(StocktakeSession session) async {
    final callback = widget.onOpenSession;
    if (callback != null) {
      await callback(session);
      return;
    }
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => session.status == StocktakeStatus.inProgress
            ? StocktakeCountScreen(
                stocktakeService: widget.stocktakeService,
                productService: widget.productService,
                sessionId: session.id,
              )
            : StocktakeReviewScreen(
                stocktakeService: widget.stocktakeService,
                productService: widget.productService,
                sessionId: session.id,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    final active = sessions
        ?.where((session) => session.status == StocktakeStatus.inProgress)
        .toList(growable: false);
    final completed = sessions
        ?.where((session) => session.status == StocktakeStatus.completed)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const Text('Stocktake')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New Stocktake'),
      ),
      body: sessions == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: FilledButton.tonal(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  _Section(
                    title: 'In progress',
                    sessions: active!,
                    emptyMessage: 'No stocktakes in progress.',
                    onTap: _open,
                  ),
                  const SizedBox(height: 24),
                  _Section(
                    title: 'Completed',
                    sessions: completed!,
                    emptyMessage: 'No completed stocktakes yet.',
                    onTap: _open,
                  ),
                ],
              ),
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.sessions,
    required this.emptyMessage,
    required this.onTap,
  });

  final String title;
  final List<StocktakeSession> sessions;
  final String emptyMessage;
  final Future<void> Function(StocktakeSession session) onTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (sessions.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(emptyMessage),
        )
      else
        for (final session in sessions)
          Card(
            child: ListTile(
              title: Text(session.name),
              subtitle: Text(
                '${session.scopeDescription}\n${session.items.length} products',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onTap(session),
            ),
          ),
    ],
  );
}
