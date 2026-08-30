import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/barcode_service.dart';
import '../../services/stocktake_service.dart';

typedef StocktakeScannerBuilder =
    Widget Function(ValueChanged<String> onBarcode);

class StocktakeScanScreen extends StatefulWidget {
  const StocktakeScanScreen({
    super.key,
    required this.stocktakeService,
    required this.sessionId,
    this.scannerBuilder,
  });

  final StocktakeService stocktakeService;
  final String sessionId;
  final StocktakeScannerBuilder? scannerBuilder;

  @override
  State<StocktakeScanScreen> createState() => _StocktakeScanScreenState();
}

class _StocktakeScanScreenState extends State<StocktakeScanScreen>
    with WidgetsBindingObserver {
  final _barcodeService = BarcodeService();
  MobileScannerController? _controller;
  bool _handling = false;
  int _countedUnits = 0;

  @override
  void initState() {
    super.initState();
    if (widget.scannerBuilder == null) {
      WidgetsBinding.instance.addObserver(this);
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        detectionTimeoutMs: 500,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.hasCameraPermission) return;
    if (state == AppLifecycleState.resumed) {
      controller.start();
    } else if (state == AppLifecycleState.inactive) {
      controller.stop();
    }
  }

  @override
  void dispose() {
    if (_controller != null) WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code != null) await _handleBarcode(code, scannerFeedback: true);
  }

  Future<void> _handleBarcode(
    String rawCode, {
    required bool scannerFeedback,
  }) async {
    final code = rawCode.trim();
    if (code.isEmpty ||
        _handling ||
        (scannerFeedback && !_barcodeService.shouldHandle(code))) {
      return;
    }
    _handling = true;
    try {
      await widget.stocktakeService.incrementByBarcode(widget.sessionId, code);
      final session = await widget.stocktakeService.session(widget.sessionId);
      final countedUnits = session.items.fold<int>(
        0,
        (sum, item) => sum + (item.countedQuantity ?? 0),
      );
      if (scannerFeedback) {
        try {
          await HapticFeedback.mediumImpact();
          await SystemSound.play(SystemSoundType.click);
        } catch (_) {
          // Device feedback is best effort.
        }
      }
      if (mounted) setState(() => _countedUnits = countedUnits);
    } on StateError catch (error) {
      if (!mounted) return;
      final outOfScope = error.toString().contains(
        'not in this stocktake scope',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            outOfScope
                ? 'This product is not part of this stocktake.'
                : 'No product in this stocktake uses that barcode.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The barcode count could not be saved.'),
          ),
        );
      }
    } finally {
      _handling = false;
    }
  }

  Future<void> _manualEntry() async {
    final input = TextEditingController();
    final barcode = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter barcode'),
        content: TextField(
          controller: input,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Barcode'),
          onSubmitted: (value) {
            final code = value.trim();
            if (code.isNotEmpty) Navigator.pop(context, code);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final code = input.text.trim();
              if (code.isNotEmpty) Navigator.pop(context, code);
            },
            child: const Text('Count one'),
          ),
        ],
      ),
    );
    input.dispose();
    if (barcode != null && mounted) {
      await _handleBarcode(barcode, scannerFeedback: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scannerBuilder = widget.scannerBuilder;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan stocktake'),
        actions: [
          IconButton(
            onPressed: _manualEntry,
            icon: const Icon(Icons.keyboard_outlined),
            tooltip: 'Enter barcode manually',
          ),
          if (_controller != null)
            IconButton(
              onPressed: _controller!.toggleTorch,
              icon: const Icon(Icons.flashlight_on_outlined),
              tooltip: 'Toggle flashlight',
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (scannerBuilder != null)
            scannerBuilder(
              (code) => unawaited(_handleBarcode(code, scannerFeedback: true)),
            )
          else
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              tapToFocus: true,
              errorBuilder: (context, error) => ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? 'Camera permission denied. Enable camera access in system settings.'
                        : 'The camera could not be started.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          if (scannerBuilder == null)
            const IgnorePointer(child: _StocktakeScannerOverlay()),
          Positioned(
            left: 24,
            right: 24,
            bottom: 30,
            child: Card(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .92),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Counted $_countedUnits',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StocktakeScannerOverlay extends StatelessWidget {
  const _StocktakeScannerOverlay();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _StocktakeScannerOverlayPainter());
}

class _StocktakeScannerOverlayPainter extends CustomPainter {
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
