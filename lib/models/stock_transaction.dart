class StockTransaction {
  const StockTransaction({
    required this.id,
    required this.productId,
    required this.delta,
    required this.reason,
    required this.note,
    required this.previousQuantity,
    required this.resultingQuantity,
    required this.occurredAt,
  });

  final String id;
  final String productId;
  final int delta;
  final String reason;
  final String note;
  final int previousQuantity;
  final int resultingQuantity;
  final DateTime occurredAt;

  factory StockTransaction.fromJson(Map<String, Object?> json) =>
      StockTransaction(
        id: json['id'] as String,
        productId: json['product_id'] as String,
        delta: (json['delta'] as num).toInt(),
        reason: json['reason'] as String,
        note: json['note'] as String? ?? '',
        previousQuantity: (json['previous_quantity'] as num).toInt(),
        resultingQuantity: (json['resulting_quantity'] as num).toInt(),
        occurredAt: DateTime.parse(json['occurred_at'] as String),
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'product_id': productId,
    'delta': delta,
    'reason': reason,
    'note': note,
    'previous_quantity': previousQuantity,
    'resulting_quantity': resultingQuantity,
    'occurred_at': occurredAt.toIso8601String(),
  };
}
