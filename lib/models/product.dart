class Product {
  const Product({
    required this.id,
    required this.barcode,
    required this.name,
    required this.price,
    required this.category,
    required this.description,
    required this.quantity,
    this.imagePath,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String barcode;
  final String name;
  final double price;
  final String category;
  final String description;
  final int quantity;
  final String? imagePath;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Product.fromJson(Map<String, Object?> json) => Product(
    id: json['id'] as String? ?? '',
    barcode: json['barcode'] as String? ?? '',
    name: json['name'] as String? ?? '',
    price: (json['price'] as num?)?.toDouble() ?? 0,
    category: json['category'] as String? ?? 'Uncategorized',
    description: json['description'] as String? ?? '',
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    imagePath: json['image_path'] as String?,
    createdAt: _date(json['created_at']),
    updatedAt: _date(json['updated_at']),
  );

  static DateTime _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);

  Map<String, Object?> toJson() => {
    'id': id,
    'barcode': barcode,
    'name': name,
    'price': price,
    'category': category,
    'description': description,
    'quantity': quantity,
    'image_path': imagePath,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  Product copyWith({
    String? id,
    String? barcode,
    String? name,
    double? price,
    String? category,
    String? description,
    int? quantity,
    Object? imagePath = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Product(
    id: id ?? this.id,
    barcode: barcode ?? this.barcode,
    name: name ?? this.name,
    price: price ?? this.price,
    category: category ?? this.category,
    description: description ?? this.description,
    quantity: quantity ?? this.quantity,
    imagePath: identical(imagePath, _unset)
        ? this.imagePath
        : imagePath as String?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static const _unset = Object();
}
