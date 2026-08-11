import 'package:flutter/material.dart';

import 'app.dart';
import 'data/local/app_database.dart';
import 'repositories/local_product_repository.dart';
import 'services/product_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final service = ProductService(LocalProductRepository(AppDatabase.instance));
  Object? startupError;
  try {
    await service.initialize();
  } catch (error) {
    startupError = error;
  }
  runApp(StockLensApp(productService: service, startupError: startupError));
}
