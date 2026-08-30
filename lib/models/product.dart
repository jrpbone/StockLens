class Product {
  const Product({
    required this.id,
    required this.barcode,
    required this.name,
    double? sellingPrice,
    double? price,
    this.costPrice = 0,
    this.lowStockThreshold = 5,
    this.lowStockNotified = false,
    required this.category,
    required this.description,
    required this.quantity,
    this.imagePath,
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  }) : assert(sellingPrice != null || price != null),
       sellingPrice = sellingPrice ?? price ?? 0;

  final String id;
  final String barcode;
  final String name;
  final double sellingPrice;
  final double costPrice;
  final int lowStockThreshold;
  final bool lowStockNotified;
  final String category;
  final String description;
  final int quantity;
  final String? imagePath;
  final DateTime? archivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Compatibility accessor while persisted SQLite rows continue using `price`.
  double get price => sellingPrice;

  bool get isLowStock => archivedAt == null && quantity <= lowStockThreshold;

  factory Product.fromJson(Map<String, Object?> json) => Product(
    id: json['id'] as String? ?? '',
    barcode: json['barcode'] as String? ?? '',
    name: json['name'] as String? ?? '',
    sellingPrice: _double(json['price'] ?? json['selling_price']),
    costPrice: _double(json['cost_price']),
    lowStockThreshold: _int(json['low_stock_threshold'], 5),
    lowStockNotified: _bool(json['low_stock_notified']),
    category: json['category'] as String? ?? 'Uncategorized',
    description: json['description'] as String? ?? '',
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    imagePath: json['image_path'] as String?,
    archivedAt: _nullableDate(json['archived_at']),
    createdAt: _date(json['created_at']),
    updatedAt: _date(json['updated_at']),
  );

  static DateTime _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);

  static DateTime? _nullableDate(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());

  static double _double(Object? value) => (value as num?)?.toDouble() ?? 0;

  static int _int(Object? value, int fallback) =>
      (value as num?)?.toInt() ?? fallback;

  static bool _bool(Object? value) => value == true || value == 1;

  Map<String, Object?> toJson() => {
    'id': id,
    'barcode': barcode,
    'name': name,
    'price': sellingPrice,
    'cost_price': costPrice,
    'low_stock_threshold': lowStockThreshold,
    'low_stock_notified': lowStockNotified ? 1 : 0,
    'category': category,
    'description': description,
    'quantity': quantity,
    'image_path': imagePath,
    'archived_at': archivedAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  Product copyWith({
    String? id,
    String? barcode,
    String? name,
    double? sellingPrice,
    double? price,
    double? costPrice,
    int? lowStockThreshold,
    bool? lowStockNotified,
    String? category,
    String? description,
    int? quantity,
    Object? imagePath = _unset,
    Object? archivedAt = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Product(
    id: id ?? this.id,
    barcode: barcode ?? this.barcode,
    name: name ?? this.name,
    sellingPrice: sellingPrice ?? price ?? this.sellingPrice,
    costPrice: costPrice ?? this.costPrice,
    lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
    lowStockNotified: lowStockNotified ?? this.lowStockNotified,
    category: category ?? this.category,
    description: description ?? this.description,
    quantity: quantity ?? this.quantity,
    imagePath: identical(imagePath, _unset)
        ? this.imagePath
        : imagePath as String?,
    archivedAt: identical(archivedAt, _unset)
        ? this.archivedAt
        : archivedAt as DateTime?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static const _unset = Object();
}
