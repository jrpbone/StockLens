import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import 'app.dart';
import 'data/local/app_database.dart';
import 'repositories/local_inventory_report_repository.dart';
import 'repositories/local_inventory_import_repository.dart';
import 'repositories/local_product_repository.dart';
import 'repositories/local_stocktake_repository.dart';
import 'services/android_low_stock_notification_gateway.dart';
import 'services/inventory_report_service.dart';
import 'services/inventory_import_service.dart';
import 'services/low_stock_notification_service.dart';
import 'services/product_service.dart';
import 'services/stocktake_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase.instance;
  final repository = LocalProductRepository(database);
  late final ProductService service;
  final navigationController = AppNavigationController(
    productServiceProvider: () => service,
  );
  final notifications = AndroidLowStockNotificationGateway(
    onNotificationOpened: navigationController.openLowStockProduct,
  );
  final lowStockNotifications = LowStockNotificationService(
    repository,
    gateway: notifications,
  );
  service = ProductService(
    repository,
    lowStockNotifications: lowStockNotifications,
  );
  final stocktakeService = StocktakeService(
    LocalStocktakeRepository(database),
    repository,
    lowStockNotifications: lowStockNotifications,
  );
  final reportService = InventoryReportService(
    LocalInventoryReportRepository(database),
  );
  final importService = InventoryImportService(
    LocalInventoryImportRepository(database),
    lowStockNotifications: lowStockNotifications,
  );
  try {
    await notifications.initialize();
  } catch (error, stackTrace) {
    developer.log(
      'Unable to initialize low-stock notifications.',
      name: 'stocklens.low_stock_notification',
      error: error,
      stackTrace: stackTrace,
    );
    // Notifications are optional; inventory workflows stay available.
  }
  Object? startupError;
  try {
    await service.initialize();
  } catch (error) {
    startupError = error;
  }
  runApp(
    StockLensApp(
      productService: service,
      startupError: startupError,
      navigationController: navigationController,
      requestLowStockNotificationPermission: notifications.requestPermission,
      lowStockNotificationsEnabled: notifications.notificationsEnabled,
      openLowStockNotificationSettings: notifications.openNotificationSettings,
      stocktakeService: stocktakeService,
      reportService: reportService,
      importService: importService,
    ),
  );
}
