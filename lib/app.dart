import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/alerts/low_stock_alerts_screen.dart';
import 'screens/home/home_shell.dart';
import 'screens/product_details/product_details_screen.dart';
import 'services/inventory_report_service.dart';
import 'services/inventory_import_service.dart';
import 'services/product_service.dart';
import 'services/stocktake_service.dart';

class AppNavigationController {
  AppNavigationController({
    ProductService? productService,
    ProductService Function()? productServiceProvider,
  }) : assert(
         productService != null || productServiceProvider != null,
         'Provide a product service or provider.',
       ),
       assert(
         productService == null || productServiceProvider == null,
         'Provide only one product service source.',
       ),
       _productService = productService,
       _productServiceProvider = productServiceProvider;

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final ProductService? _productService;
  final ProductService Function()? _productServiceProvider;
  Future<bool> Function()? requestLowStockNotificationPermission;
  Future<bool> Function()? lowStockNotificationsEnabled;
  Future<bool> Function()? openLowStockNotificationSettings;
  String? _pendingProductId;
  bool _pendingAlertCenter = false;

  ProductService get _service => _productService ?? _productServiceProvider!();

  Future<void> openLowStockProduct(String productId) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _pendingProductId = productId;
      return;
    }
    try {
      final product = await _service.byId(productId);
      if (product == null) {
        openLowStockAlertCenter();
        return;
      }
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ProductDetailsScreen(service: _service, productId: product.id),
        ),
      );
    } catch (_) {
      openLowStockAlertCenter();
    }
  }

  void openLowStockAlertCenter() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _pendingAlertCenter = true;
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => LowStockAlertsScreen(
          service: _service,
          onEnableNotifications: requestLowStockNotificationPermission,
          onNotificationsEnabled: lowStockNotificationsEnabled,
          onOpenNotificationSettings: openLowStockNotificationSettings,
        ),
      ),
    );
  }

  Future<void> activate() async {
    final productId = _pendingProductId;
    _pendingProductId = null;
    if (productId != null) {
      await openLowStockProduct(productId);
      return;
    }
    if (_pendingAlertCenter) {
      _pendingAlertCenter = false;
      openLowStockAlertCenter();
    }
  }
}

class StockLensApp extends StatefulWidget {
  const StockLensApp({
    super.key,
    required this.productService,
    this.startupError,
    this.navigationController,
    this.requestLowStockNotificationPermission,
    this.lowStockNotificationsEnabled,
    this.openLowStockNotificationSettings,
    this.stocktakeService,
    this.reportService,
    this.importService,
  });
  final ProductService productService;
  final Object? startupError;
  final AppNavigationController? navigationController;
  final Future<bool> Function()? requestLowStockNotificationPermission;
  final Future<bool> Function()? lowStockNotificationsEnabled;
  final Future<bool> Function()? openLowStockNotificationSettings;
  final StocktakeService? stocktakeService;
  final InventoryReportService? reportService;
  final InventoryImportService? importService;

  @override
  State<StockLensApp> createState() => _StockLensAppState();
}

class _StockLensAppState extends State<StockLensApp> {
  @override
  void initState() {
    super.initState();
    widget.navigationController?.requestLowStockNotificationPermission =
        widget.requestLowStockNotificationPermission;
    widget.navigationController?.lowStockNotificationsEnabled =
        widget.lowStockNotificationsEnabled;
    widget.navigationController?.openLowStockNotificationSettings =
        widget.openLowStockNotificationSettings;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.navigationController?.activate();
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'StockLens',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    navigatorKey: widget.navigationController?.navigatorKey,
    home: HomeShell(
      productService: widget.productService,
      startupError: widget.startupError,
      onEnableLowStockNotifications:
          widget.requestLowStockNotificationPermission,
      onLowStockNotificationsEnabled: widget.lowStockNotificationsEnabled,
      onOpenLowStockNotificationSettings:
          widget.openLowStockNotificationSettings,
      stocktakeService: widget.stocktakeService,
      reportService: widget.reportService,
      importService: widget.importService,
    ),
  );
}
