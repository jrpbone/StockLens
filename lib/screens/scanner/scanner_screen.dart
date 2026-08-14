import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/barcode_service.dart';
import '../../services/product_service.dart';
import '../add_product/add_product_screen.dart';
import '../product_details/product_details_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, required this.service});
  final ProductService service;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  final _barcodeService = BarcodeService();
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 500,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    if (state == AppLifecycleState.resumed) {
      _controller.start();
    } else if (state == AppLifecycleState.inactive) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final code = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (code == null || code.isEmpty) return;
    await _handleCode(code, scannerFeedback: true);
  }

  Future<void> _manualEntry() async {
    final code = await showDialog<String>(
      context: context,
      builder: (context) => const _ManualBarcodeDialog(),
    );
    if (code != null && mounted) {
      await _handleCode(code, scannerFeedback: false);
    }
  }

  Future<void> _handleCode(String code, {required bool scannerFeedback}) async {
    if (_handling || (scannerFeedback && !_barcodeService.shouldHandle(code))) {
      return;
    }
    _handling = true;
    await _controller.stop();
    try {
      if (scannerFeedback) {
        try {
          await HapticFeedback.mediumImpact();
          await SystemSound.play(SystemSoundType.click);
        } catch (_) {
          // Feedback support varies by device and must not block barcode lookup.
        }
      }
      final product = await widget.service.byBarcode(code);
      if (!mounted) return;
      if (product != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailsScreen(
              service: widget.service,
              productId: product.id,
            ),
          ),
        );
      } else {
        final add = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Product not found'),
            content: Text(
              'No product uses barcode $code. Would you like to add this product?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Add Product'),
              ),
            ],
          ),
        );
        if (add == true && mounted) {
          final id = await Navigator.push<String>(
            context,
            MaterialPageRoute(
              builder: (_) => AddProductScreen(
                service: widget.service,
                initialBarcode: code,
              ),
            ),
          );
          if (id != null && mounted) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductDetailsScreen(
                  service: widget.service,
                  productId: id,
                ),
              ),
            );
          }
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Barcode lookup failed. Please try again.'),
          ),
        );
      }
    } finally {
      _handling = false;
      if (mounted) {
        try {
          await _controller.start();
        } catch (_) {
          /* Error UI handles camera failures. */
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Scan Barcode'),
      actions: [
        IconButton(
          onPressed: _manualEntry,
          icon: const Icon(Icons.keyboard_outlined),
          tooltip: 'Enter barcode manually',
        ),
        IconButton(
          onPressed: _controller.toggleTorch,
          icon: const Icon(Icons.flashlight_on_outlined),
          tooltip: 'Toggle flashlight',
        ),
        IconButton(
          onPressed: _controller.switchCamera,
          icon: const Icon(Icons.cameraswitch_outlined),
          tooltip: 'Switch camera',
        ),
      ],
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          tapToFocus: true,
          errorBuilder: (context, error) => ColoredBox(
            color: Colors.black,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.no_photography_outlined,
                      color: Colors.white,
                      size: 54,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      error.errorCode == MobileScannerErrorCode.permissionDenied
                          ? 'Camera permission denied. Enable camera access in system settings to scan barcodes.'
                          : 'The camera could not be started.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const IgnorePointer(child: _ScannerOverlay()),
        const Positioned(
          left: 24,
          right: 24,
          bottom: 30,
          child: Text(
            'Align a product barcode inside the frame',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(blurRadius: 8)],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ManualBarcodeDialog extends StatefulWidget {
  const _ManualBarcodeDialog();

  @override
  State<_ManualBarcodeDialog> createState() => _ManualBarcodeDialogState();
}

class _ManualBarcodeDialogState extends State<_ManualBarcodeDialog> {
  String _barcode = '';

  void _submit([String? value]) {
    final barcode = (value ?? _barcode).trim();
    if (barcode.isNotEmpty) Navigator.pop(context, barcode);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Enter Barcode'),
    content: TextField(
      autofocus: true,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        labelText: 'Barcode',
        prefixIcon: Icon(Icons.qr_code),
      ),
      onChanged: (value) => _barcode = value,
      onSubmitted: _submit,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Look Up')),
    ],
  );
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ScannerOverlayPainter());
}

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cutout = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * .78,
      height: 190,
    );
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(cutout, const Radius.circular(20)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black54);
    canvas.drawRRect(
      RRect.fromRectAndRadius(cutout, const Radius.circular(20)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
