class StocktakeItem {
  const StocktakeItem({
    required this.sessionId,
    required this.productId,
    required this.expectedQuantity,
    this.countedQuantity,
    required this.updatedAt,
  });

  final String sessionId;
  final String productId;
  final int expectedQuantity;
  final int? countedQuantity;
  final DateTime updatedAt;

  factory StocktakeItem.fromJson(Map<String, Object?> json) => StocktakeItem(
    sessionId: json['session_id'] as String,
    productId: json['product_id'] as String,
    expectedQuantity: (json['expected_quantity'] as num).toInt(),
    countedQuantity: (json['counted_quantity'] as num?)?.toInt(),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  Map<String, Object?> toJson() => {
    'session_id': sessionId,
    'product_id': productId,
    'expected_quantity': expectedQuantity,
    'counted_quantity': countedQuantity,
    'updated_at': updatedAt.toIso8601String(),
  };

  StocktakeItem copyWith({
    int? countedQuantity,
    bool clearCountedQuantity = false,
    DateTime? updatedAt,
  }) => StocktakeItem(
    sessionId: sessionId,
    productId: productId,
    expectedQuantity: expectedQuantity,
    countedQuantity: clearCountedQuantity
        ? null
        : countedQuantity ?? this.countedQuantity,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
