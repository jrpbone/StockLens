import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/utils/formatters.dart';
import '../../models/pos_cart_item.dart';
import '../../repositories/product_repository.dart';
import '../../services/barcode_service.dart';
import '../../services/product_service.dart';
import '../sales/sales_history_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({
    super.key,
    required this.service,
    required this.scannerController,
  });

  final ProductService service;
  final MobileScannerController scannerController;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _barcodeController = TextEditingController();
  final _barcodeFocus = FocusNode();
  final _barcodeService = BarcodeService();
  final List<PosCartItem> _cart = [];
  bool _lookingUp = false;
  bool _checkingOut = false;

  int get _totalQuantity =>
      _cart.fold(0, (total, item) => total + item.quantity);
  int get _totalCents =>
      _cart.fold(0, (total, item) => total + item.subtotalCents);

  MobileScannerController get _scannerController => widget.scannerController;

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final code = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (code == null || code.isEmpty || _checkingOut) return;
    if (!_barcodeService.shouldHandle(
      code,
      cooldown: const Duration(milliseconds: 900),
    )) {
      return;
    }
    try {
      await HapticFeedback.mediumImpact();
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {
      // Feedback support varies by device and must not block adding an item.
    }
    await _addCode(code, clearInput: false);
  }

  Future<void> _submitManual([String? value]) async {
    final code = (value ?? _barcodeController.text).trim();
    if (code.isEmpty) {
      _message('Enter a barcode or SKU.');
      _barcodeFocus.requestFocus();
      return;
    }
    await _addCode(code, clearInput: true);
  }

  Future<void> _addCode(String code, {required bool clearInput}) async {
    if (_lookingUp || _checkingOut) return;
    setState(() => _lookingUp = true);
    try {
      final product = await widget.service.byBarcode(code);
      if (!mounted) return;
      if (product == null) {
        _message('Product not found for barcode or SKU "$code".');
        return;
      }
      if (!product.price.isFinite || product.price < 0) {
        _message('${product.name} has an invalid price.');
        return;
      }
      if (product.quantity <= 0) {
        _message('${product.name} is out of stock.');
        return;
      }
      final index = _cart.indexWhere((item) => item.productId == product.id);
      if (index >= 0) {
        final existing = _cart[index];
        if (existing.quantity >= product.quantity) {
          _message('Only ${product.quantity} units are currently available.');
          return;
        }
        setState(() {
          _cart[index] = PosCartItem.fromProduct(
            product,
            quantity: existing.quantity + 1,
          );
        });
      } else {
        setState(() => _cart.add(PosCartItem.fromProduct(product)));
      }
      if (clearInput) _barcodeController.clear();
    } catch (_) {
      if (mounted) _message('Product lookup failed. Please try again.');
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  void _increase(PosCartItem item) {
    if (item.quantity >= item.availableStock) {
      _message('Only ${item.availableStock} units are currently available.');
      return;
    }
    _replace(item, item.copyWith(quantity: item.quantity + 1));
  }

  void _decrease(PosCartItem item) {
    if (item.quantity <= 1) return;
    _replace(item, item.copyWith(quantity: item.quantity - 1));
  }

  void _replace(PosCartItem current, PosCartItem replacement) {
    final index = _cart.indexWhere(
      (item) => item.productId == current.productId,
    );
    if (index >= 0) setState(() => _cart[index] = replacement);
  }

  void _remove(PosCartItem item) {
    setState(
      () => _cart.removeWhere((value) => value.productId == item.productId),
    );
  }

  Future<void> _clearOrder() async {
    if (_cart.isEmpty) return;
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear current order?'),
        content: const Text(
          'This will remove all items from the current transaction.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (clear == true && mounted) setState(_cart.clear);
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty || _checkingOut) return;
    setState(() => _checkingOut = true);
    try {
      final refreshed = await widget.service.revalidateSale(_cart);
      if (!mounted) return;
      setState(() {
        _cart
          ..clear()
          ..addAll(refreshed);
      });
      final quantity = refreshed.fold<int>(
        0,
        (total, item) => total + item.quantity,
      );
      final total = refreshed.fold<int>(
        0,
        (sum, item) => sum + item.subtotalCents,
      );
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Sale?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DialogSummary(label: 'Items', value: '${refreshed.length}'),
              _DialogSummary(label: 'Total Quantity', value: '$quantity'),
              _DialogSummary(
                label: 'Total Amount',
                value: formatCentavos(total),
                emphasized: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final order = await widget.service.completeSale(refreshed);
      if (!mounted) return;
      setState(_cart.clear);
      _barcodeController.clear();
      _message(
        'Sale completed successfully.\n'
        '${order.orderNumber} • ${formatCentavos(order.totalAmountCents)}',
      );
    } on ProductUnavailableException catch (error) {
      if (mounted) _message(error.toString());
    } on ProductMissingForSaleException {
      if (mounted) {
        _message('A product in this order is no longer available.');
      }
    } on InvalidProductPriceException catch (error) {
      if (mounted) _message(error.toString());
    } catch (_) {
      if (mounted) {
        _message('The sale could not be completed. No stock was changed.');
      }
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  Future<void> _openHistory() async {
    try {
      await _scannerController.stop();
    } catch (_) {
      // The scanner may already be stopped after a camera error.
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SalesHistoryScreen(service: widget.service),
      ),
    );
    if (mounted) {
      try {
        await _scannerController.start();
      } catch (_) {
        // The scanner error view communicates camera failures.
      }
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Point of Sale'),
      actions: [
        IconButton(
          onPressed: _openHistory,
          icon: const Icon(Icons.receipt_long_outlined),
          tooltip: 'Sales history',
        ),
      ],
    ),
    body: Column(
      children: [
        _ScannerPanel(controller: _scannerController, onDetect: _onDetect),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _barcodeController,
                  focusNode: _barcodeFocus,
                  enabled: !_checkingOut,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Barcode / SKU',
                    prefixIcon: Icon(Icons.qr_code),
                  ),
                  onSubmitted: _submitManual,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: _lookingUp || _checkingOut ? null : _submitManual,
                  child: _lookingUp
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Add'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 8, 4),
          child: Row(
            children: [
              Text(
                'Current Order',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _cart.isEmpty || _checkingOut ? null : _clearOrder,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Clear Order'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _cart.isEmpty
              ? const _EmptyCart()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  itemCount: _cart.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final item = _cart[index];
                    return _CartItemCard(
                      item: item,
                      enabled: !_checkingOut,
                      onIncrease: () => _increase(item),
                      onDecrease: () => _decrease(item),
                      onRemove: () => _remove(item),
                    );
                  },
                ),
        ),
        _OrderSummary(
          differentItems: _cart.length,
          totalQuantity: _totalQuantity,
          totalCents: _totalCents,
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _cart.isEmpty || _checkingOut ? null : _checkout,
                icon: _checkingOut
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.point_of_sale),
                label: Text(_checkingOut ? 'Processing…' : 'Confirm Sale'),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ScannerPanel extends StatelessWidget {
  const _ScannerPanel({required this.controller, required this.onDetect});

  final MobileScannerController controller;
  final ValueChanged<BarcodeCapture> onDetect;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 170,
    child: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: controller,
          onDetect: onDetect,
          tapToFocus: true,
          errorBuilder: (context, error) => ColoredBox(
            color: Colors.black87,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Camera permission denied. You can still enter a barcode or SKU below.'
                      : 'Scanner unavailable. Enter a barcode or SKU below.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Center(
            child: Container(
              width: 230,
              height: 105,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Row(
            children: [
              IconButton.filledTonal(
                onPressed: controller.toggleTorch,
                icon: const Icon(Icons.flashlight_on_outlined),
                tooltip: 'Toggle flashlight',
              ),
              IconButton.filledTonal(
                onPressed: controller.switchCamera,
                icon: const Icon(Icons.cameraswitch_outlined),
                tooltip: 'Switch camera',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CartItemCard extends StatelessWidget {
  const _CartItemCard({
    required this.item,
    required this.enabled,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
  });

  final PosCartItem item;
  final bool enabled;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'SKU: ${item.sku}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatCentavos(item.unitPriceCents)} × ${item.quantity}',
                    ),
                  ],
                ),
              ),
              Text(
                formatCentavos(item.subtotalCents),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: enabled && item.quantity > 1 ? onDecrease : null,
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Decrease quantity',
              ),
              SizedBox(
                width: 34,
                child: Text(
                  '${item.quantity}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: enabled ? onIncrease : null,
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Increase quantity',
              ),
              const Spacer(),
              IconButton(
                onPressed: enabled ? onRemove : null,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove item',
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({
    required this.differentItems,
    required this.totalQuantity,
    required this.totalCents,
  });

  final int differentItems;
  final int totalQuantity;
  final int totalCents;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _SummaryValue(label: 'Items', value: '$differentItems'),
            const SizedBox(width: 20),
            _SummaryValue(label: 'Quantity', value: '$totalQuantity'),
            const Spacer(),
            _SummaryValue(
              label: 'TOTAL',
              value: formatCentavos(totalCents),
              emphasized: true,
            ),
          ],
        ),
      ),
    ),
  );
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: 2),
      Text(
        value,
        style:
            (emphasized
                    ? Theme.of(context).textTheme.titleLarge
                    : Theme.of(context).textTheme.titleMedium)
                ?.copyWith(
                  color: emphasized
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  fontWeight: FontWeight.w800,
                ),
      ),
    ],
  );
}

class _DialogSummary extends StatelessWidget {
  const _DialogSummary({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: emphasized ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
      ],
    ),
  );
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 10),
          Text(
            'No items added yet.',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Scan a barcode or enter an SKU to begin a sale.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
