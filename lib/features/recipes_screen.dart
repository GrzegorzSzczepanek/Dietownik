import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/ai_settings.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import '../services/recipe_import.dart';
import 'common.dart';
import 'fridge_screen.dart';
import 'scan_screen.dart';
import 'shopping_screen.dart';
import 'widgets.dart';

class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(recipesProvider).value ?? const <Recipe>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        Row(children: [
          Expanded(child: Text('Przepisy', style: display(30))),
          IconButton(
            tooltip: 'Zeskanuj kod',
            icon: Icon(Icons.qr_code_scanner, color: AppColors.accent),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen())),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _Btn(Icons.link, 'Z linku', () => _import(context, ref))),
          const SizedBox(width: 8),
          Expanded(child: _Btn(Icons.edit_note, 'Własny', () => _open(context, const Recipe(title: '')))),
          const SizedBox(width: 8),
          Expanded(child: _Btn(Icons.auto_awesome, 'Pomysł AI', () => _idea(context, ref))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _Btn(Icons.kitchen, 'Co mam w lodówce', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FridgeScreen())))),
          const SizedBox(width: 8),
          Expanded(child: _Btn(Icons.shopping_cart_outlined, 'Zakupy', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShoppingScreen())))),
        ]),
        const SizedBox(height: 16),
        if (list.isEmpty)
          const SectionCard(
            child: Text('Wklej link do przepisu (aniagotuje, kwestiasmaku, mojewypieki…), zapiszę składniki i kroki oraz policzę kalorie na porcję. Albo poproś AI o pomysł z tego, co masz w lodówce.',
                style: TextStyle(fontSize: 15, height: 1.4)),
          ),
        for (final r in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SectionCard(
              padding: const EdgeInsets.all(4),
              child: ListTile(
                title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(r.perServing.kcal == 0
                    ? '${r.servings} porcji · brak kalorii'
                    : '${n0(r.perServing.kcal)} kcal/porcja · ${macroText(r.perServing)}'),
                leading: Icon(r.favorite ? Icons.star : Icons.restaurant_menu, color: AppColors.green),
                onTap: () => _open(context, r),
              ),
            ),
          ),
      ],
    );
  }

  static void _open(BuildContext context, Recipe r) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => RecipeScreen(initial: r)));

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import z linku'),
        content: TextField(controller: ctrl, autofocus: true, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://…')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Importuj')),
        ],
      ),
    );
    if (url == null || url.isEmpty || !context.mounted) return;
    toast(context, 'Pobieram przepis…');
    try {
      final r = await importRecipeFromUrl(url.startsWith('http') ? url : 'https://$url');
      if (!context.mounted) return;
      if (r == null) {
        toast(context, 'Ta strona nie udostępnia przepisu w czytelnym formacie. Dodaj ręcznie.');
      } else {
        _open(context, r);
      }
    } catch (e) {
      if (context.mounted) toast(context, 'Nie udało się pobrać strony: $e');
    }
  }

  Future<void> _idea(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final req = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Czego szukasz?'),
        content: TextField(controller: ctrl, autofocus: true, maxLines: 2, decoration: const InputDecoration(hintText: 'np. obiad 500 kcal z kurczakiem i ryżem')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Wymyśl')),
        ],
      ),
    );
    if (req == null || req.isEmpty || !context.mounted) return;
    final ai = await ref.read(aiSettingsProvider.notifier).dietAi();
    if (!ai.canRun(AiTask.advice)) {
      toast(context, 'Najpierw skonfiguruj AI (Ja → Lokalne AI / Dostawca API).');
      return;
    }
    toast(context, 'Wymyślam…');
    try {
      final r = await ai.recipeIdea(req);
      if (context.mounted) _open(context, r);
    } catch (e) {
      if (context.mounted) toast(context, 'AI nie dało rady: $e');
    }
  }
}

class _Btn extends StatelessWidget {
  const _Btn(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), padding: const EdgeInsets.symmetric(horizontal: 6), backgroundColor: AppColors.bg),
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: AppColors.green),
        label: Text(label, style: const TextStyle(fontSize: 13)),
      );
}

class RecipeScreen extends ConsumerStatefulWidget {
  const RecipeScreen({super.key, required this.initial});
  final Recipe initial;
  @override
  ConsumerState<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends ConsumerState<RecipeScreen> {
  late final _title = TextEditingController(text: widget.initial.title);
  late final _servings = TextEditingController(text: '${widget.initial.servings}');
  late final _ingr = TextEditingController(text: widget.initial.ingredients.join('\n'));
  late final _steps = TextEditingController(text: widget.initial.steps);
  late final _k = TextEditingController(text: _s(widget.initial.perServing.kcal));
  late final _p = TextEditingController(text: _s(widget.initial.perServing.p));
  late final _c = TextEditingController(text: _s(widget.initial.perServing.c));
  late final _f = TextEditingController(text: _s(widget.initial.perServing.f));
  late bool _fav = widget.initial.favorite;
  int? _id;
  bool _busy = false;

  static String _s(double v) => v == 0 ? '' : v.toStringAsFixed(v >= 10 ? 0 : 1);
  double _d(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  @override
  void initState() {
    super.initState();
    _id = widget.initial.id;
  }

  Recipe _build() => Recipe(
        id: _id,
        title: _title.text.trim().isEmpty ? 'Przepis' : _title.text.trim(),
        servings: (int.tryParse(_servings.text) ?? 1).clamp(1, 50),
        ingredients: _ingr.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        steps: _steps.text.trim(),
        sourceUrl: widget.initial.sourceUrl,
        perServing: Macros(kcal: _d(_k), p: _d(_p), c: _d(_c), f: _d(_f)),
        favorite: _fav,
      );

  Future<void> _save({bool pop = true}) async {
    _id = await ref.read(dbProvider).saveRecipe(_build());
    ref.read(dataVersionProvider.notifier).bump();
    if (pop && mounted) Navigator.pop(context);
  }

  Future<void> _estimate() async {
    final r = _build();
    final ai = await ref.read(aiSettingsProvider.notifier).dietAi();
    if (!ai.canRun(AiTask.estimation)) {
      toast(context, 'Skonfiguruj AI (Ja → Lokalne AI / Dostawca API), żeby policzyć makro.');
      return;
    }
    setState(() => _busy = true);
    try {
      final m = await ai.recipeMacros(r.title, r.servings, r.ingredients);
      _k.text = _s(m.kcal); _p.text = _s(m.p); _c.text = _s(m.c); _f.text = _s(m.f);
    } catch (e) {
      if (mounted) toast(context, 'Nie udało się policzyć: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _eat() async {
    final r = _build();
    if (r.perServing.kcal <= 0) { toast(context, 'Najpierw wpisz lub policz kalorie.'); return; }
    final db = ref.read(dbProvider);
    final t = ref.read(selectedDayProvider);
    await db.addEntry(Entry(day: dayKey(t), meal: mealForTime(t), name: r.title, grams: 0, macros: r.perServing, estimated: true));
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) { toast(context, 'Dodano porcję: ${r.title}'); Navigator.pop(context); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.initial.id == null && widget.initial.title.isEmpty ? 'Nowy przepis' : 'Przepis'),
          actions: [
            IconButton(icon: Icon(_fav ? Icons.star : Icons.star_border), onPressed: () => setState(() => _fav = !_fav)),
            if (_id != null)
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
                await ref.read(dbProvider).deleteRecipe(_id!);
                ref.read(dataVersionProvider.notifier).bump();
                if (context.mounted) Navigator.pop(context);
              }),
          ],
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Nazwa')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _servings, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Porcji'))),
          ]),
          const SizedBox(height: 14),
          const Eyebrow('Na jedną porcję'),
          const SizedBox(height: 6),
          Row(children: [
            for (final e in [(_k, 'kcal'), (_p, 'B'), (_c, 'W'), (_f, 'T')])
              Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: TextField(controller: e.$1, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: e.$2)))),
          ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _busy ? null : _estimate, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome), label: const Text('Policz makro (AI)')),
          const SizedBox(height: 14),
          TextField(controller: _ingr, minLines: 4, maxLines: 12, decoration: const InputDecoration(labelText: 'Składniki (jeden w linii)', alignLabelWithHint: true)),
          const SizedBox(height: 10),
          TextField(controller: _steps, minLines: 4, maxLines: 16, decoration: const InputDecoration(labelText: 'Kroki', alignLabelWithHint: true)),
          if (widget.initial.sourceUrl.isNotEmpty)
            TextButton.icon(onPressed: () => launchUrl(Uri.parse(widget.initial.sourceUrl), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new), label: const Text('Otwórz źródło')),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () {
              ref.read(shoppingProvider.notifier).add([for (final i in _build().ingredients) '0|$i']);
              toast(context, 'Składniki dodane do listy zakupów');
            },
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Składniki do listy zakupów'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _eat, icon: const Icon(Icons.restaurant), label: const Text('Zjadłem porcję')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _save, child: const Text('Zapisz przepis')),
        ]),
      );
}
