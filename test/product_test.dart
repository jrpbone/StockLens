import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/models/product.dart';
import 'package:stocklens/models/stock_transaction.dart';

void main() {
  test('Product JSON round-trip preserves fields', () {
    final now = DateTime.utc(2026, 8, 11);
    final product = Product(
      id: '1',
      barcode: '480123',
      name: 'Sample',
      sellingPrice: 12.5,
      costPrice: 8,
      lowStockThreshold: 2,
      category: 'Food',
      description: 'Test',
      quantity: 3,
      createdAt: now,
      updatedAt: now,
    );

    expect(Product.fromJson(product.toJson()).toJson(), product.toJson());
    expect(product.copyWith(costPrice: 8, lowStockThreshold: 2).costPrice, 8);
    expect(
      product.copyWith(quantity: 2, lowStockThreshold: 2).isLowStock,
      isTrue,
    );
    expect(product.copyWith(imagePath: 'photo.jpg').imagePath, 'photo.jpg');
    expect(product.copyWith(imagePath: null).imagePath, isNull);
  });

  test('archived products are not low stock at or below the threshold', () {
    final timestamp = DateTime.utc(2026, 8, 11);
    final active = Product(
      id: 'low-product',
      barcode: '480123',
      name: 'Low product',
      sellingPrice: 12.5,
      category: 'Food',
      description: '',
      quantity: 2,
      lowStockThreshold: 2,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    expect(active.isLowStock, isTrue);
    expect(active.copyWith(archivedAt: timestamp).isLowStock, isFalse);
  });

  test(
    'StockTransaction JSON round-trip and copyWith preserve schema-v3 data',
    () {
      final now = DateTime.utc(2026, 8, 11);
      final transaction = StockTransaction(
        id: 'transaction-1',
        productId: 'product-1',
        delta: -2,
        reason: 'Sale',
        note: 'Receipt 42',
        previousQuantity: 4,
        resultingQuantity: 2,
        occurredAt: now,
        sellingPriceSnapshot: 12.5,
        costPriceSnapshot: 8,
        source: 'sale',
        sourceId: 'receipt-42',
      );

      expect(
        StockTransaction.fromJson(transaction.toJson()).toJson(),
        transaction.toJson(),
      );
      expect(transaction.copyWith(source: 'manual').source, 'manual');
    },
  );
}
