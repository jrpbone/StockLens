import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/widgets/async_state.dart';
import '../../services/inventory_report_service.dart';
import '../../services/inventory_import_service.dart';
import '../../services/product_service.dart';
import '../../services/stocktake_service.dart';
import '../inventory/inventory_screen.dart';
import '../pos/pos_screen.dart';
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _switchingTabs = false;
  late final MobileScannerController _scannerController;

  bool _usesScanner(int index) => index == 1 || index == 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scannerController = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 500,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_usesScanner(_index) ||
        !_scannerController.value.hasCameraPermission) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_startScanner());
    } else if (state == AppLifecycleState.inactive) {
      unawaited(_stopScanner());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_scannerController.dispose());
    super.dispose();
  }

  Future<void> _selectTab(int value) async {
    if (value == _index || _switchingTabs) return;
    setState(() => _switchingTabs = true);
    if (_usesScanner(_index)) await _stopScanner();
    if (!mounted) return;
    setState(() => _index = value);
    if (_usesScanner(value)) {
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && _index == value) await _startScanner();
    }
    if (mounted) setState(() => _switchingTabs = false);
  }

  Future<void> _startScanner() async {
    try {
      await _scannerController.start();
    } catch (_) {
      // The scanner widget presents controller errors to the user.
    }
  }

  Future<void> _stopScanner() async {
    try {
      await _scannerController.stop();
    } catch (_) {
      // An uninitialized or failed camera is already stopped for tab changes.
    }
  }

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
        onSelectTab: _selectTab,
        onEnableLowStockNotifications: widget.onEnableLowStockNotifications,
        onLowStockNotificationsEnabled: widget.onLowStockNotificationsEnabled,
        onOpenLowStockNotificationSettings:
            widget.onOpenLowStockNotificationSettings,
      ),
      1 => ScannerScreen(
        service: widget.productService,
        controller: _scannerController,
      ),
      2 => PosScreen(
        service: widget.productService,
        scannerController: _scannerController,
      ),
      3 => InventoryScreen(
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
        onDestinationSelected: _switchingTabs ? null : _selectTab,
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
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'POS',
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
