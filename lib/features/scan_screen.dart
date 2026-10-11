import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'label_flow.dart';

/// Opens straight into the camera. Barcode -> product (local pack, cache, then
/// Open Food Facts); the bottom button reads a label with AI. Stays open after
/// each product so a whole shopping bag can be scanned in a row.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE],
    detectionTimeoutMs: 600,
  );
  bool _busy = false;
  String? _last;
  String _status = 'Skieruj aparat na kod kreskowy';
  int _count = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pause() => _controller.stop();
  Future<void> _resume() async {
    if (mounted) setState(() { _busy = false; _status = 'Skieruj aparat na kod kreskowy'; });
    await _controller.start();
  }

  Future<void> _onCode(String code) async {
    if (_busy || code == _last) return;
    _busy = true;
    _last = code;
    await _pause();
    if (mounted) setState(() => _status = 'Szukam $code…');
    final db = ref.read(dbProvider);
    var food = await db.foodByBarcode(code);
    if (food == null) {
      food = await ref.read(offProvider).byBarcode(code);
      if (food != null) {
        final id = await db.saveFood(food);
        food = Food.fromMap({...food.toMap(), 'id': id});
      }
    }
    if (!mounted) return;
    if (food == null) {
      final photo = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nie ma w bazie'),
          content: Text('Kodu $code nie znam. Sfotografuj etykietę — AI odczyta wartości i skład, a ja zapamiętam je pod tym kodem.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Skanuj dalej')),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(120, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Etykieta')),
          ],
        ),
      );
      if (photo == true && mounted) food = await labelToFood(context, ref, barcode: code, askSource: false);
    }
    if (food != null && mounted) {
      final done = await foodActions(context, ref, food);
      if (done) _count++;
    }
    _last = null;
    await _resume();
  }

  Future<void> _labelOnly() async {
    if (_busy) return;
    _busy = true;
    await _pause();
    if (mounted) {
      final f = await labelToFood(context, ref, askSource: false);
      if (f != null && mounted) {
        if (await foodActions(context, ref, f)) _count++;
      }
    }
    await _resume();
  }

  @override
  Widget build(BuildContext context) {
    final searching = _status.startsWith('Szukam');
    return Scaffold(
      backgroundColor: const Color(0xFF1A2220),
      body: Stack(children: [
        Positioned.fill(
          child: MobileScanner(
            controller: _controller,
            onDetect: (cap) {
              final code = cap.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
              if (code != null) _onCode(code);
            },
            errorBuilder: (ctx, err) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Brak dostępu do aparatu (${err.errorCode.name}). Zezwól w ustawieniach telefonu.',
                    textAlign: TextAlign.center, style: fig(16, color: Colors.white)),
              ),
            ),
          ),
        ),
        Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.18))),
        SafeArea(
          child: Stack(children: [
            Positioned(
              top: 0,
              left: 8,
              right: 8,
              height: 52,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                IconButton(tooltip: 'Zamknij skaner', color: Colors.white, icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                Text(_count == 0 ? 'Skaner' : 'Skaner · dodano $_count', style: fig(18, weight: 700, color: Colors.white)),
                IconButton(tooltip: 'Włącz latarkę', color: Colors.white, icon: const Icon(Icons.flashlight_on_outlined), onPressed: () => _controller.toggleTorch()),
              ]),
            ),
            const Positioned(left: 35, right: 35, top: 190, height: 200, child: _Corners()),
            Positioned(
              left: 20,
              right: 20,
              top: 420,
              child: Column(children: [
                Text(_status, textAlign: TextAlign.center, style: fig(18, weight: 600, color: Colors.white, height: 24 / 18)),
                const SizedBox(height: 8),
                if (!searching)
                  Text('Skanuję bez przerwy. Produkty dodasz po kolei, a kod zostanie zapamiętany.',
                      textAlign: TextAlign.center, style: fig(15, color: const Color(0xFFC2CEC8), height: 22 / 15)),
              ]),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 32,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Produkt bez kodu?', style: fig(15, color: const Color(0xFFC2CEC8))),
                const SizedBox(height: 12),
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF12392C)),
                    onPressed: _labelOnly,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Zrób zdjęcie etykiety'),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Corners extends StatelessWidget {
  const _Corners();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _CornerPainter());
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const l = 44.0, r = 16.0;
    final w = size.width, h = size.height;
    Path c(double x, double y, double dx, double dy) => Path()
      ..moveTo(x, y + dy * l)
      ..lineTo(x, y + dy * r)
      ..quadraticBezierTo(x, y, x + dx * r, y)
      ..lineTo(x + dx * l, y);
    canvas.drawPath(c(0, 0, 1, 1), p);
    canvas.drawPath(c(w, 0, -1, 1), p);
    canvas.drawPath(c(0, h, 1, -1), p);
    canvas.drawPath(c(w, h, -1, -1), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
