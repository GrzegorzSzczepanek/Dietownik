import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'common.dart';
import 'label_flow.dart';

/// Barcode -> macros in one step: local cache first, then Open Food Facts.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE]);
  bool _busy = false;
  String _status = 'Skieruj aparat na kod kreskowy';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onCode(String code) async {
    if (_busy) return;
    _busy = true;
    setState(() => _status = 'Szukam $code…');
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
      final add = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nie ma w bazie'),
          content: Text('Kod $code nie jest w bazie. Sfotografuj etykietę — AI odczyta wartości i skład, a ja zapamiętam je pod tym kodem.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Skanuj dalej')),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(120, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Etykieta')),
          ],
        ),
      );
      if (add == true && mounted) {
        final logged = await scanLabelFlow(context, ref, barcode: code);
        if (logged && mounted) {
          Navigator.pop(context);
          return;
        }
      }
    }
    if (food != null && mounted) {
      final g = await askGrams(context, food);
      if (g != null && mounted) {
        await ref.read(foodLoggerProvider).addFood(food, g, when: ref.read(selectedDayProvider));
        if (mounted) {
          toast(context, 'Dodano: ${food.title}');
          Navigator.pop(context);
          return;
        }
      }
    }
    if (mounted) setState(() { _busy = false; _status = 'Skieruj aparat na kod kreskowy'; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Skanuj kod')),
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
                child: Text('Brak dostępu do aparatu (${err.errorCode.name}). Zezwól w ustawieniach telefonu albo użyj wyszukiwarki.', textAlign: TextAlign.center),
              ),
            ),
          ),
          Positioned(
            left: 16, right: 16, bottom: 32,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(16)),
              child: Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
          Center(child: Container(width: 280, height: 160, decoration: BoxDecoration(border: Border.all(color: AppColors.greenSoft, width: 3), borderRadius: BorderRadius.circular(16)))),
        ]),
      );
}
