import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/models/product.dart';

void main() {
  test('Product JSON round-trip preserves fields', () {
    final now = DateTime.utc(2026, 8, 11);
    final product = Product(
      id: '1',
      barcode: '480123',
      name: 'Sample',
      price: 12.5,
      category: 'Food',
      description: 'Test',
      quantity: 3,
      createdAt: now,
      updatedAt: now,
    );

    expect(Product.fromJson(product.toJson()).toJson(), product.toJson());
    expect(product.copyWith(imagePath: 'photo.jpg').imagePath, 'photo.jpg');
    expect(product.copyWith(imagePath: null).imagePath, isNull);
  });
}
