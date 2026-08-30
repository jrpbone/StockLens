import 'dart:developer' as developer;

import '../models/product.dart';
import '../repositories/product_repository.dart';

abstract interface class LowStockNotificationGateway {
  Future<void> showLowStock(Product product);
}

class LowStockProductChange {
  const LowStockProductChange({this.before, required this.after});

  final Product? before;
  final Product after;
}

class LowStockNotificationService {
  LowStockNotificationService(this._repository, {required this.gateway});

  final ProductRepository _repository;
  final LowStockNotificationGateway gateway;

  Future<void> evaluate({Product? before, required Product after}) async {
    try {
      final notified =
          (await _repository.getById(after.id))?.lowStockNotified ??
          after.lowStockNotified;
      final crossed =
          (before == null || !before.isLowStock) && after.isLowStock;
      if (crossed && !notified) {
        await gateway.showLowStock(after);
        await _repository.setLowStockNotified(after.id, true);
      } else if (!after.isLowStock && notified) {
        await _repository.setLowStockNotified(after.id, false);
      }
    } catch (error, stackTrace) {
      developer.log(
        'Unable to evaluate low-stock notification state for ${after.id}.',
        name: 'stocklens.low_stock_notification',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> evaluateAll(Iterable<LowStockProductChange> changes) async {
    for (final change in changes) {
      await evaluate(before: change.before, after: change.after);
    }
  }
}
