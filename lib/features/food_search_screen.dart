import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_settings.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'common.dart';
import 'label_flow.dart';

class FoodSearchScreen extends ConsumerStatefulWidget {
  const FoodSearchScreen({super.key});
  @override
  ConsumerState<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends ConsumerState<FoodSearchScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Food> _local = [], _web = [];
  bool _loadingWeb = false;
  String _last = '';

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

  Future<void> _pick(Food f) async {
    final g = await askGrams(context, f);
    if (g == null || !mounted) return;
    await ref.read(foodLoggerProvider).addFood(f, g, when: ref.read(selectedDayProvider));
    if (mounted) { toast(context, 'Dodano: ${f.title}'); Navigator.pop(context); }
  }

  Future<void> _estimate() async {
    final name = _q.text.trim();
    if (name.isEmpty) return;
    final ai = await ref.read(aiSettingsProvider.notifier).dietAi();
    if (!ai.canRun(AiTask.estimation)) {
      if (mounted) toast(context, 'Skonfiguruj AI w Ja → Lokalne AI albo API, żeby szacować.');
      return;
    }
    try {
      final e = await ai.estimate(name);
      final f = Food(name: name, kcal100: e.kcal100, p100: e.p100, c100: e.c100, f100: e.f100, servingG: e.servingG, source: 'ai');
      final id = await ref.read(dbProvider).saveFood(f);
      await _pick(Food.fromMap({...f.toMap(), 'id': id}));
    } catch (e) {
      if (mounted) toast(context, 'Nie udało się oszacować: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget tile(Food f) => ListTile(
          title: Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${n0(f.kcal100)} kcal/100 g · ${macroText(Macros(p: f.p100, c: f.c100, f: f.f100))}'
              '${f.estimated ? ' · ~szacunek' : ''}'),
          onTap: () => _pick(f),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Dodaj jedzenie')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _q,
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'np. skyr, big mac, pierogi'),
            onChanged: _run,
          ),
        ),
        Expanded(
          child: ListView(children: [
            for (final f in _local) tile(f),
            if (_loadingWeb) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            if (_web.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Eyebrow2('Z OPEN FOOD FACTS')),
            for (final f in _web) tile(f),
            if (_q.text.trim().isNotEmpty) ...[
              const Divider(),
              ListTile(leading: const Icon(Icons.auto_awesome, color: AppColors.green), title: const Text('Oszacuj AI'), subtitle: Text('„${_q.text.trim()}”'), onTap: _estimate),
              ListTile(leading: const Icon(Icons.photo_camera_outlined, color: AppColors.green), title: const Text('Zdjęcie etykiety (AI odczyta)'), onTap: () async { await scanLabelFlow(context, ref); if (mounted) Navigator.pop(context); }),
              ListTile(leading: const Icon(Icons.add_circle_outline, color: AppColors.green), title: const Text('Dodaj własny produkt'), onTap: () => _custom(_q.text.trim())),
            ],
          ]),
        ),
      ]),
    );
  }

  Future<void> _custom(String name, {String? barcode}) async {
    final f = await showCustomFoodDialog(context, name: name, barcode: barcode);
    if (f == null) return;
    final id = await ref.read(dbProvider).saveFood(f);
    await _pick(Food.fromMap({...f.toMap(), 'id': id}));
  }
}

class Eyebrow2 extends StatelessWidget {
  const Eyebrow2(this.t, {super.key});
  final String t;
  @override
  Widget build(BuildContext context) => Text(t, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.8));
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
