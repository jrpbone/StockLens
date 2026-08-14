import 'product.dart';

class PosCartItem {
  const PosCartItem({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.barcode,
    required this.unitPriceCents,
    required this.quantity,
    required this.availableStock,
  });

  factory PosCartItem.fromProduct(Product product, {int quantity = 1}) =>
      PosCartItem(
        productId: product.id,
        productName: product.name,
        sku: product.barcode,
        barcode: product.barcode,
        unitPriceCents: (product.price * 100).round(),
        quantity: quantity,
        availableStock: product.quantity,
      );

  final String productId;
  final String productName;
  final String sku;
  final String barcode;
  final int unitPriceCents;
  final int quantity;
  final int availableStock;

  int get subtotalCents => unitPriceCents * quantity;

  PosCartItem copyWith({
    String? productName,
    String? sku,
    String? barcode,
    int? unitPriceCents,
    int? quantity,
    int? availableStock,
  }) => PosCartItem(
    productId: productId,
    productName: productName ?? this.productName,
    sku: sku ?? this.sku,
    barcode: barcode ?? this.barcode,
    unitPriceCents: unitPriceCents ?? this.unitPriceCents,
    quantity: quantity ?? this.quantity,
    availableStock: availableStock ?? this.availableStock,
  );
}
