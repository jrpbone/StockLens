import 'package:uuid/uuid.dart';

import '../models/stocktake_item.dart';
import '../models/stocktake_session.dart';
import '../repositories/product_repository.dart';
import '../repositories/stocktake_repository.dart';
import 'low_stock_notification_service.dart';

class StocktakeCompletionLine {
  const StocktakeCompletionLine({
    required this.item,
    required this.currentQuantity,
  });

  final StocktakeItem item;
  final int currentQuantity;

  int get variance => item.countedQuantity! - currentQuantity;
  bool get changedSinceStart => currentQuantity != item.expectedQuantity;
}

class StocktakeCompletionPreview {
  StocktakeCompletionPreview({
    required List<StocktakeCompletionLine> lines,
    required this.unresolvedCount,
  }) : lines = List.unmodifiable(lines);

  final List<StocktakeCompletionLine> lines;
  final int unresolvedCount;
}

class StocktakeService {
  StocktakeService(
    this._repository,
    this._products, {
    required this.lowStockNotifications,
  });

  final StocktakeRepository _repository;
  final ProductRepository _products;
  final LowStockNotificationService lowStockNotifications;

  Future<StocktakeSession> create({
    required String name,
    required List<String> productIds,
    required String scopeDescription,
    String notes = '',
  }) async {
    final normalizedName = name.trim();
    final normalizedScope = scopeDescription.trim();
    final normalizedNotes = notes.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Name cannot be blank.');
    }
    if (normalizedScope.isEmpty) {
      throw ArgumentError.value(
        scopeDescription,
        'scopeDescription',
        'Scope description cannot be blank.',
      );
    }
    if (productIds.isEmpty) {
      throw ArgumentError.value(
        productIds,
        'productIds',
        'Scope cannot be empty.',
      );
    }
    final normalizedProductIds = productIds.map((id) => id.trim()).toList();
    if (normalizedProductIds.any((id) => id.isEmpty) ||
        normalizedProductIds.toSet().length != normalizedProductIds.length) {
      throw ArgumentError.value(
        productIds,
        'productIds',
        'Product IDs must be nonblank and unique.',
      );
    }
    normalizedProductIds.sort();

    final expectedQuantities = <String, int>{};
    for (final productId in normalizedProductIds) {
      final product = await _products.getById(productId);
      if (product == null || product.archivedAt != null) {
        throw StateError('Stocktake scope contains an unavailable product.');
      }
      expectedQuantities[productId] = product.quantity;
    }

    final now = DateTime.now().toUtc();
    final session = StocktakeSession(
      id: const Uuid().v4(),
      name: normalizedName,
      status: StocktakeStatus.inProgress,
      scopeDescription: normalizedScope,
      notes: normalizedNotes,
      createdAt: now,
    );
    final items = normalizedProductIds
        .map(
          (productId) => StocktakeItem(
            sessionId: session.id,
            productId: productId,
            expectedQuantity: expectedQuantities[productId]!,
            updatedAt: now,
          ),
        )
        .toList(growable: false);
    await _repository.create(session, items);
    return session.copyWith(items: items);
  }

  Future<StocktakeSession> session(String sessionId) => _activeOrAny(sessionId);

  Future<List<StocktakeSession>> sessions() => _repository.getSessions();

  Future<void> setCount(
    String sessionId,
    String productId,
    int countedQuantity,
  ) async {
    if (countedQuantity < 0) {
      throw ArgumentError.value(
        countedQuantity,
        'countedQuantity',
        'Count cannot be negative.',
      );
    }
    final session = await _activeSession(sessionId);
    _requireInScope(session, productId);
    await _repository.setCount(
      sessionId: session.id,
      productId: productId,
      countedQuantity: countedQuantity,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> incrementByBarcode(String sessionId, String barcode) async {
    final normalizedBarcode = barcode.trim();
    if (normalizedBarcode.isEmpty) {
      throw ArgumentError.value(barcode, 'barcode', 'Barcode cannot be blank.');
    }
    final session = await _activeSession(sessionId);
    final product = await _products.getByBarcode(normalizedBarcode);
    if (product == null) throw StateError('Barcode was not found.');
    final item = _requireInScope(session, product.id);
    await _repository.incrementCount(
      sessionId: session.id,
      productId: item.productId,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> setRemainingToZero(String sessionId) async {
    final session = await _activeSession(sessionId);
    await _repository.setRemainingToZero(
      sessionId: session.id,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Future<StocktakeCompletionPreview> previewCompletion(String sessionId) async {
    final session = await _activeOrAny(sessionId);
    final lines = <StocktakeCompletionLine>[];
    var unresolvedCount = 0;
    for (final item in session.items) {
      if (item.countedQuantity == null) {
        unresolvedCount++;
        continue;
      }
      final product = await _products.getById(item.productId);
      if (product == null) {
        throw StateError('Stocktake product is no longer available.');
      }
      lines.add(
        StocktakeCompletionLine(item: item, currentQuantity: product.quantity),
      );
    }
    return StocktakeCompletionPreview(
      lines: List.unmodifiable(lines),
      unresolvedCount: unresolvedCount,
    );
  }

  Future<void> complete(
    String sessionId,
    StocktakeCompletionPreview acceptedPreview,
  ) async {
    final session = await _activeSession(sessionId);
    if (acceptedPreview.unresolvedCount != 0 ||
        acceptedPreview.lines.length != session.items.length ||
        acceptedPreview.lines.any(
          (line) => line.item.countedQuantity == null,
        )) {
      throw const IncompleteStocktakeException();
    }
    final changes = await _repository.complete(
      sessionId: session.id,
      acceptedLines: acceptedPreview.lines
          .map(
            (line) => AcceptedStocktakeLine(
              sessionId: line.item.sessionId,
              productId: line.item.productId,
              countedQuantity: line.item.countedQuantity!,
              currentQuantity: line.currentQuantity,
            ),
          )
          .toList(growable: false),
      completedAt: DateTime.now().toUtc(),
    );
    await lowStockNotifications.evaluateAll(
      changes.map(
        (change) =>
            LowStockProductChange(before: change.before, after: change.after),
      ),
    );
  }

  Future<StocktakeSession> _activeOrAny(String sessionId) async {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      throw ArgumentError.value(
        sessionId,
        'sessionId',
        'Session ID cannot be blank.',
      );
    }
    final session = await _repository.getById(normalizedSessionId);
    if (session == null) throw StateError('Stocktake session not found.');
    return session;
  }

  Future<StocktakeSession> _activeSession(String sessionId) async {
    final session = await _activeOrAny(sessionId);
    if (session.status == StocktakeStatus.completed) {
      throw StateError('Completed stocktakes cannot be changed.');
    }
    return session;
  }

  StocktakeItem _requireInScope(StocktakeSession session, String productId) {
    final normalizedProductId = productId.trim();
    for (final item in session.items) {
      if (item.productId == normalizedProductId) return item;
    }
    throw StateError('Product is not in this stocktake scope.');
  }
}
