import 'package:flutter/material.dart';

import '../../core/widgets/async_state.dart';
import '../../services/product_service.dart';
import '../inventory/inventory_screen.dart';
import '../scanner/scanner_screen.dart';
import '../search/search_screen.dart';
import 'home_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.productService, this.startupError});
  final ProductService productService;
  final Object? startupError;

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
      ),
      1 => ScannerScreen(service: widget.productService),
      2 => InventoryScreen(service: widget.productService),
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
