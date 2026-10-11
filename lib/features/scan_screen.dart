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
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(_count == 0 ? 'Skaner' : 'Skaner · dodano $_count'),
          actions: [
            IconButton(icon: const Icon(Icons.flash_on), onPressed: () => _controller.toggleTorch()),
          ],
        ),
        body: Stack(children: [
          MobileScanner(
            controller: _controller,
            onDetect: (cap) {
              final code = cap.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
              if (code != null) _onCode(code);
            },
            errorBuilder: (ctx, err) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Brak dostępu do aparatu (${err.errorCode.name}). Zezwól w ustawieniach telefonu.',
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
          Center(child: Container(width: 280, height: 160, decoration: BoxDecoration(border: Border.all(color: AppColors.greenSoft, width: 3), borderRadius: BorderRadius.circular(16)))),
          Positioned(
            left: 16, right: 16, bottom: 24,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(14)),
                child: Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _labelOnly,
                icon: const Icon(Icons.document_scanner),
                label: const Text('Brak kodu? Zdjęcie etykiety (AI)'),
              ),
            ]),
          ),
        ]),
      );
}
