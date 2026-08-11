import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/home/home_shell.dart';
import 'services/product_service.dart';

class StockLensApp extends StatelessWidget {
  const StockLensApp({
    super.key,
    required this.productService,
    this.startupError,
  });
  final ProductService productService;
  final Object? startupError;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'StockLens',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: HomeShell(productService: productService, startupError: startupError),
  );
}
