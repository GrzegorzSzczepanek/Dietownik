import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_settings.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'common.dart';
import 'label_flow.dart';
import 'oko_screen.dart';
import 'scan_screen.dart';

class FoodSearchScreen extends ConsumerStatefulWidget {
  const FoodSearchScreen({super.key, this.initialMeal});
  final int? initialMeal;
  @override
  ConsumerState<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends ConsumerState<FoodSearchScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Food> _local = [], _web = [];
  bool _loadingWeb = false;
  String _last = '';
  late int _meal = widget.initialMeal ?? mealForTime(DateTime.now());

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _run(String q) {
    _last = q;
    ref.read(dbProvider).searchFoods(q, limit: 30).then((r) {
      if (mounted && _last == q) setState(() => _local = r);
    });
    _debounce?.cancel();
    if (q.trim().length < 3) {
      setState(() => _web = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      setState(() => _loadingWeb = true);
      final r = await ref.read(offProvider).search(q.trim());
      if (mounted && _last == q) setState(() { _web = r; _loadingWeb = false; });
    });
  }

  /// Row tap: choose the amount. Plus button: default portion, one tap, with undo.
  Future<void> _pick(Food f) async {
    final g = await askGrams(context, f);
    if (g == null || !mounted) return;
    await ref.read(foodLoggerProvider).addFood(f, g, when: ref.read(selectedDayProvider), meal: _meal);
    if (mounted) { toast(context, 'Dodano: ${f.title}'); Navigator.pop(context); }
  }

  Future<void> _quickAdd(Food f) async {
    final logger = ref.read(foodLoggerProvider);
    final id = await logger.addFood(f, f.servingG, when: ref.read(selectedDayProvider), meal: _meal);
    if (!mounted) return;
    toast(context, 'Dodano: ${f.title}',
        action: SnackBarAction(
            label: 'Cofnij',
            onPressed: () async {
              await ref.read(dbProvider).deleteEntry(id);
              ref.read(dataVersionProvider.notifier).bump();
            }));
  }

  Future<void> _estimate() async {
    final name = _q.text.trim();
    if (name.isEmpty) {
      toast(context, 'Wpisz nazwę, a AI oszacuje wartości.');
      return;
    }
    final ai = await ref.read(aiSettingsProvider.notifier).dietAi();
    if (!ai.canRun(AiTask.estimation)) {
      if (mounted) toast(context, 'Skonfiguruj AI w Ja → Dostawca API, żeby szacować.');
      return;
    }
    try {
      final e = await ai.estimate(name);
      final f = Food(
          name: name,
          kcal100: e.kcal100,
          p100: e.p100,
          c100: e.c100,
          f100: e.f100,
          servingG: e.servingG,
          ingredients: (e.sourceUrl ?? '').isEmpty ? '' : 'Źródło: ${e.sourceUrl}',
          source: (e.sourceUrl ?? '').isEmpty ? 'ai' : 'web');
      final id = await ref.read(dbProvider).saveFood(f);
      await _pick(Food.fromMap({...f.toMap(), 'id': id}));
    } catch (e) {
      if (mounted) toast(context, 'Nie udało się oszacować: $e');
    }
  }

  Widget _row(Food f) {
    final portion = f.servingLabel.isNotEmpty ? '${f.servingLabel}, ${n0(f.servingG)} g' : '${n0(f.servingG)} g';
    final kcal = f.per(f.servingG).kcal;
    return InkWell(
      onTap: () => _pick(f),
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
        child: Row(children: [
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: fig(16, weight: 600)),
              Text(f.estimated ? '$portion · ~szacunek' : portion, style: fig(14, color: AppColors.text2)),
            ]),
          ),
          const SizedBox(width: 12),
          Text('${f.estimated ? '~' : ''}${n0(kcal)}', style: fig(18, weight: 600)),
          const SizedBox(width: 12),
          Semantics(
            button: true,
            label: 'Dodaj: ${f.title}, $portion',
            child: GestureDetector(
              onTap: () => _quickAdd(f),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                child: Icon(Icons.add, color: AppColors.onAccent),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 20, 0),
            child: SizedBox(
              height: 52,
              child: Row(children: [
                IconButton(tooltip: 'Wróć', icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                Text('Co zjadłeś?', style: display(28)),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: TextField(
              controller: _q,
              autofocus: true,
              style: fig(17, weight: 500),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search, color: AppColors.text2),
                hintText: 'np. skyr, big mac, pierogi',
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppColors.accent, width: 2)),
              ),
              onChanged: _run,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
                for (var m = 0; m < 4; m++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _meal = m),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _meal == m ? AppColors.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(22),
                          border: _meal == m ? null : Border.all(color: AppColors.outline),
                        ),
                        child: Text(mealNames[m],
                            style: fig(15, weight: _meal == m ? 700 : 600, color: _meal == m ? AppColors.onAccent : AppColors.text)),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 24), children: [
              if (_local.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(_q.text.isEmpty ? 'Ostatnio i najczęściej' : 'Wyniki', style: fig(16, weight: 700))),
              for (final f in _local) _row(f),
              if (_loadingWeb) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
              if (_web.isNotEmpty) ...[
                Padding(padding: const EdgeInsets.only(top: 20, bottom: 4), child: Text('Z Open Food Facts', style: fig(16, weight: 700))),
                for (final f in _web) _row(f),
              ],
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                child: Text('Nie ma na liście?', style: fig(14, color: AppColors.text2)),
              ),
              Transform.translate(
                offset: const Offset(-12, 0),
                child: Wrap(children: [
                  _link('Zeskanuj kod', () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ScanScreen()))),
                  _link('Oszacuj z AI', _estimate),
                  _link('Zdjęcie etykiety', () async { await scanLabelFlow(context, ref); if (mounted) Navigator.pop(context); }),
                  _link('Wpis na oko', () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => OkoScreen(initialMeal: _meal)))),
                  _link('Dodaj własny', () => _custom(_q.text.trim())),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _link(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Text(label, style: fig(15, weight: 600, color: AppColors.accent))]),
          ),
        ),
      );

  Future<void> _custom(String name, {String? barcode}) async {
    final f = await showCustomFoodDialog(context, name: name, barcode: barcode);
    if (f == null) return;
    final id = await ref.read(dbProvider).saveFood(f);
    await _pick(Food.fromMap({...f.toMap(), 'id': id}));
  }
}

Future<Food?> showCustomFoodDialog(BuildContext context, {String name = '', String? barcode, Food? initial}) {
  final c = {for (final k in ['name', 'brand', 'kcal', 'p', 'c', 'f', 'serving', 'ingr']) k: TextEditingController()};
  String t(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1));
  c['name']!.text = initial?.name ?? name;
  c['brand']!.text = initial?.brand ?? '';
  c['kcal']!.text = t(initial?.kcal100);
  c['p']!.text = t(initial?.p100);
  c['c']!.text = t(initial?.c100);
  c['f']!.text = t(initial?.f100);
  c['serving']!.text = t(initial?.servingG ?? 100);
  c['ingr']!.text = initial?.ingredients ?? '';
  double d(String k) => double.tryParse(c[k]!.text.replaceAll(',', '.')) ?? 0;
  Widget num(String k, String label) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 6, top: 8),
          child: TextField(controller: c[k], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: label)),
        ),
      );
  return showDialog<Food>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Produkt (wartości na 100 g)'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: c['name'], decoration: const InputDecoration(labelText: 'Nazwa')),
          const SizedBox(height: 8),
          TextField(controller: c['brand'], decoration: const InputDecoration(labelText: 'Marka')),
          Row(children: [num('kcal', 'kcal'), num('serving', 'porcja g')]),
          Row(children: [num('p', 'białko'), num('c', 'węgle'), num('f', 'tłuszcz')]),
          const SizedBox(height: 8),
          TextField(controller: c['ingr'], minLines: 1, maxLines: 5, decoration: const InputDecoration(labelText: 'Skład')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
          onPressed: () {
            if (c['name']!.text.trim().isEmpty) return;
            Navigator.pop(ctx, Food(
              name: c['name']!.text.trim(),
              brand: c['brand']!.text.trim(),
              barcode: barcode ?? initial?.barcode,
              kcal100: d('kcal'), p100: d('p'), c100: d('c'), f100: d('f'),
              servingG: d('serving') > 0 ? d('serving') : 100,
              ingredients: c['ingr']!.text.trim(),
              source: initial?.source ?? 'own',
            ));
          },
          child: const Text('Zapisz'),
        ),
      ],
    ),
  );
}
