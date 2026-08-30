import 'package:flutter/material.dart';

import '../../core/widgets/async_state.dart';
import '../../services/inventory_report_service.dart';
import '../../services/inventory_import_service.dart';
import '../../services/product_service.dart';
import '../../services/stocktake_service.dart';
import '../inventory/inventory_screen.dart';
import '../scanner/scanner_screen.dart';
import '../search/search_screen.dart';
import 'home_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.productService,
    this.startupError,
    this.onEnableLowStockNotifications,
    this.onLowStockNotificationsEnabled,
    this.onOpenLowStockNotificationSettings,
    this.stocktakeService,
    this.reportService,
    this.importService,
  });
  final ProductService productService;
  final Object? startupError;
  final Future<bool> Function()? onEnableLowStockNotifications;
  final Future<bool> Function()? onLowStockNotificationsEnabled;
  final Future<bool> Function()? onOpenLowStockNotificationSettings;
  final StocktakeService? stocktakeService;
  final InventoryReportService? reportService;
  final InventoryImportService? importService;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.startupError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('StockLens')),
        body: const ErrorState(
          message:
              'The local database could not be opened. Please restart the app.',
        ),
      );
    }
    final page = switch (_index) {
      0 => HomeScreen(
        service: widget.productService,
        onSelectTab: (value) => setState(() => _index = value),
        onEnableLowStockNotifications: widget.onEnableLowStockNotifications,
        onLowStockNotificationsEnabled: widget.onLowStockNotificationsEnabled,
        onOpenLowStockNotificationSettings:
            widget.onOpenLowStockNotificationSettings,
      ),
      1 => ScannerScreen(service: widget.productService),
      2 => InventoryScreen(
        service: widget.productService,
        stocktakeService: widget.stocktakeService,
        reportService: widget.reportService,
        importService: widget.importService,
      ),
      _ => SearchScreen(service: widget.productService),
    };
    return Scaffold(
      body: page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventory',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
        ],
      ),
    );
  }
}
