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
    this.sellingPriceSnapshot,
    this.costPriceSnapshot,
    this.source,
    this.sourceId,
  });

  final String id;
  final String productId;
  final int delta;
  final String reason;
  final String note;
  final int previousQuantity;
  final int resultingQuantity;
  final DateTime occurredAt;
  final double? sellingPriceSnapshot;
  final double? costPriceSnapshot;
  final String? source;
  final String? sourceId;

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
        sellingPriceSnapshot: (json['selling_price_snapshot'] as num?)
            ?.toDouble(),
        costPriceSnapshot: (json['cost_price_snapshot'] as num?)?.toDouble(),
        source: json['source'] as String?,
        sourceId: json['source_id'] as String?,
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
    'selling_price_snapshot': sellingPriceSnapshot,
    'cost_price_snapshot': costPriceSnapshot,
    'source': source,
    'source_id': sourceId,
  };

  StockTransaction copyWith({
    String? id,
    String? productId,
    int? delta,
    String? reason,
    String? note,
    int? previousQuantity,
    int? resultingQuantity,
    DateTime? occurredAt,
    Object? sellingPriceSnapshot = _unset,
    Object? costPriceSnapshot = _unset,
    Object? source = _unset,
    Object? sourceId = _unset,
  }) => StockTransaction(
    id: id ?? this.id,
    productId: productId ?? this.productId,
    delta: delta ?? this.delta,
    reason: reason ?? this.reason,
    note: note ?? this.note,
    previousQuantity: previousQuantity ?? this.previousQuantity,
    resultingQuantity: resultingQuantity ?? this.resultingQuantity,
    occurredAt: occurredAt ?? this.occurredAt,
    sellingPriceSnapshot: identical(sellingPriceSnapshot, _unset)
        ? this.sellingPriceSnapshot
        : sellingPriceSnapshot as double?,
    costPriceSnapshot: identical(costPriceSnapshot, _unset)
        ? this.costPriceSnapshot
        : costPriceSnapshot as double?,
    source: identical(source, _unset) ? this.source : source as String?,
    sourceId: identical(sourceId, _unset) ? this.sourceId : sourceId as String?,
  );

  static const _unset = Object();
}
