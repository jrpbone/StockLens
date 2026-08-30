import '../models/product.dart';
import '../models/stocktake_item.dart';
import '../models/stocktake_session.dart';

class AcceptedStocktakeLine {
  const AcceptedStocktakeLine({
    required this.sessionId,
    required this.productId,
    required this.countedQuantity,
    required this.currentQuantity,
  });

  final String sessionId;
  final String productId;
  final int countedQuantity;
  final int currentQuantity;
}

class StocktakeProductChange {
  const StocktakeProductChange({required this.before, required this.after});

  final Product before;
  final Product after;
}

class IncompleteStocktakeException implements Exception {
  const IncompleteStocktakeException();

  @override
  String toString() =>
      'Every stocktake item must be counted before completion.';
}

class StaleStocktakeCompletionException implements Exception {
  const StaleStocktakeCompletionException();

  @override
  String toString() => 'The stocktake changed after its completion preview.';
}

abstract interface class StocktakeRepository {
  /// Session items always use ascending, bytewise product-ID order.
  Future<void> create(StocktakeSession session, List<StocktakeItem> items);
  Future<List<StocktakeSession>> getSessions();
  Future<StocktakeSession?> getById(String sessionId);
  Future<void> setCount({
    required String sessionId,
    required String productId,
    required int countedQuantity,
    required DateTime updatedAt,
  });
  Future<void> incrementCount({
    required String sessionId,
    required String productId,
    required DateTime updatedAt,
  });
  Future<void> setRemainingToZero({
    required String sessionId,
    required DateTime updatedAt,
  });
  Future<List<StocktakeProductChange>> complete({
    required String sessionId,
    required List<AcceptedStocktakeLine> acceptedLines,
    required DateTime completedAt,
  });
}
