class SaleOrder {
  const SaleOrder({
    required this.id,
    required this.orderNumber,
    required this.transactionDate,
    required this.transactionTime,
    required this.totalAmountCents,
    required this.totalItems,
    required this.totalQuantity,
    required this.createdAt,
    this.items = const [],
  });

  final String id;
  final String orderNumber;
  final String transactionDate;
  final String transactionTime;
  final int totalAmountCents;
  final int totalItems;
  final int totalQuantity;
  final DateTime createdAt;
  final List<SaleOrderItem> items;

  factory SaleOrder.fromJson(
    Map<String, Object?> json, {
    List<SaleOrderItem> items = const [],
  }) => SaleOrder(
    id: json['id'] as String,
    orderNumber: json['order_number'] as String,
    transactionDate: json['transaction_date'] as String,
    transactionTime: json['transaction_time'] as String,
    totalAmountCents: (json['total_amount_cents'] as num).toInt(),
    totalItems: (json['total_items'] as num).toInt(),
    totalQuantity: (json['total_quantity'] as num).toInt(),
    createdAt: DateTime.parse(json['created_at'] as String),
    items: items,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'order_number': orderNumber,
    'transaction_date': transactionDate,
    'transaction_time': transactionTime,
    'total_amount_cents': totalAmountCents,
    'total_items': totalItems,
    'total_quantity': totalQuantity,
    'created_at': createdAt.toIso8601String(),
  };
}

class SaleOrderItem {
  const SaleOrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.barcode,
    required this.quantity,
    required this.unitPriceCents,
    required this.subtotalCents,
    required this.createdAt,
  });

  final String id;
  final String orderId;
  final String productId;
  final String productName;
  final String sku;
  final String barcode;
  final int quantity;
  final int unitPriceCents;
  final int subtotalCents;
  final DateTime createdAt;

  factory SaleOrderItem.fromJson(Map<String, Object?> json) => SaleOrderItem(
    id: json['id'] as String,
    orderId: json['order_id'] as String,
    productId: json['product_id'] as String,
    productName: json['product_name'] as String,
    sku: json['sku'] as String,
    barcode: json['barcode'] as String,
    quantity: (json['quantity'] as num).toInt(),
    unitPriceCents: (json['unit_price_cents'] as num).toInt(),
    subtotalCents: (json['subtotal_cents'] as num).toInt(),
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'order_id': orderId,
    'product_id': productId,
    'product_name': productName,
    'sku': sku,
    'barcode': barcode,
    'quantity': quantity,
    'unit_price_cents': unitPriceCents,
    'subtotal_cents': subtotalCents,
    'created_at': createdAt.toIso8601String(),
  };
}

class SaleRequestItem {
  const SaleRequestItem({required this.productId, required this.quantity});

  final String productId;
  final int quantity;
}
