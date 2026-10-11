import 'package:dio/dio.dart';
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
import 'state_screens.dart';
import 'widgets.dart';

/// Przepisy per design/Przepisy: hero with a paste-a-link field, then a flat list of entry points.
class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});
  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  final _url = TextEditingController();
  bool _importing = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  static void _open(BuildContext context, Recipe r) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => RecipeScreen(initial: r)));

  Future<void> _import() async {
    final url = _url.text.trim();
    if (url.isEmpty || _importing) return;
    setState(() => _importing = true);
    toast(context, 'Pobieram przepis…');
    try {
      final r = await importRecipeFromUrl(url.startsWith('http') ? url : 'https://$url');
      if (!mounted) return;
      if (r == null) {
        toast(context, 'Ta strona nie udostępnia przepisu w czytelnym formacie. Dodaj ręcznie.');
      } else {
        _url.clear();
        _open(context, r);
      }
    } catch (e) {
      final offline = e is DioException &&
          (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout);
      if (mounted) {
        if (offline) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => OfflineScreen(url: url, onRetry: _import)));
        } else {
          toast(context, 'Nie udało się pobrać strony: $e');
        }
      }
    }
    if (mounted) setState(() => _importing = false);
  }

  Future<void> _idea() async {
    final ctrl = TextEditingController();
    final req = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Czego szukasz?'),
        content: TextField(controller: ctrl, autofocus: true, maxLines: 2, decoration: const InputDecoration(hintText: 'np. obiad 500 kcal z kurczakiem i ryżem')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 48)), onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Wymyśl')),
        ],
      ),
    );
    if (req == null || req.isEmpty || !mounted) return;
    final ai = await ref.read(aiSettingsProvider.notifier).dietAi();
    if (!mounted) return;
    if (!ai.canRun(AiTask.advice)) {
      toast(context, 'Najpierw skonfiguruj AI (Ja → Dostawca API).');
      return;
    }
    toast(context, 'Wymyślam…');
    try {
      final r = await ai.recipeIdea(req);
      if (mounted) _open(context, r);
    } catch (e) {
      if (mounted) toast(context, 'AI nie dało rady: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(recipesProvider).value ?? const <Recipe>[];
    final shopping = ref.watch(shoppingProvider).where((e) => e.startsWith('0|')).length;
    final pending = ref.watch(pendingLinksProvider);
    final bottom = 84 + MediaQuery.of(context).padding.bottom + 40;
    Widget icon(IconData i) => Icon(i, color: AppColors.accent, size: 26);
    return ListView(padding: EdgeInsets.only(bottom: bottom), children: [
      HeroZone(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 52,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Przepisy', style: display(32)),
              Transform.translate(
                offset: const Offset(12, 0),
                child: IconButton(
                  tooltip: 'Skanuj kod',
                  icon: Icon(Icons.qr_code_scanner, color: AppColors.accent),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen())),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Text('Wklej link do przepisu, a policzę kalorie na porcję.', style: fig(17, weight: 600, height: 24 / 17)),
          const SizedBox(height: 14),
          HeroField(
            controller: _url,
            hint: 'aniagotuje.pl, kwestiasmaku.com…',
            keyboardType: TextInputType.url,
            leading: Icon(Icons.link, color: AppColors.text2),
            onSubmitted: (_) => _import(),
            actions: [AccentSquareButton(onTap: _import, label: _importing ? '…' : 'Importuj', semantics: 'Importuj przepis')],
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          NavRow(
            topLine: false,
            minHeight: 72,
            bold: true,
            leading: icon(Icons.kitchen_outlined),
            title: 'Co mam w lodówce',
            subtitle: 'Wpisz składniki, a znajdę prawdziwe przepisy',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FridgeScreen())),
          ),
          NavRow(
            minHeight: 72,
            bold: true,
            leading: icon(Icons.shopping_cart_outlined),
            title: 'Zakupy',
            subtitle: shopping == 0 ? 'Lista jest pusta' : '$shopping do kupienia',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShoppingScreen())),
          ),
          NavRow(
            minHeight: 72,
            bold: true,
            leading: icon(Icons.auto_awesome_outlined),
            title: 'Pomysł od AI',
            subtitle: 'Oznaczony jako niezweryfikowany',
            onTap: _idea,
          ),
          NavRow(
            minHeight: 72,
            bold: true,
            bottomLine: true,
            leading: icon(Icons.edit_note),
            title: 'Własny przepis',
            subtitle: 'Wpisz składniki i kroki ręcznie',
            onTap: () => _open(context, const Recipe(title: '')),
          ),
          if (pending.isNotEmpty)
            NavRow(
              topLine: false,
              bottomLine: true,
              minHeight: 60,
              title: 'Zapamiętane linki (${pending.length})',
              subtitle: 'Dotknij, żeby zaimportować teraz',
              subtitleColor: AppColors.warn,
              onTap: () async {
                final url = pending.first;
                _url.text = url;
                await ref.read(pendingLinksProvider.notifier).remove(url);
                _import();
              },
            ),
          const SizedBox(height: 28),
          if (list.isEmpty)
            Text('Zapisane przepisy pojawią się tutaj, ulubione na górze. Pierwszy dodasz linkiem w kilka sekund.',
                style: fig(16, color: AppColors.text3, height: 24 / 16))
          else ...[
            Text('Zapisane', style: fig(18, weight: 700)),
            const SizedBox(height: 4),
            for (var i = 0; i < list.length; i++)
              NavRow(
                topLine: true,
                bottomLine: i == list.length - 1,
                minHeight: 64,
                title: list[i].title,
                subtitle: list[i].perServing.kcal == 0
                    ? '${list[i].servings} porcji · brak kalorii'
                    : '~${n0(list[i].perServing.kcal)} kcal/porcja · ${macroText(list[i].perServing)}',
                trailing: list[i].favorite ? Icon(Icons.star, color: AppColors.accent) : null,
                onTap: () => _open(context, list[i]),
              ),
          ],
        ]),
      ),
    ]);
  }
}

/// Przepis per design/Porcje: servings in the pot, one portion's kcal, "I cooked for several days".
class RecipeScreen extends ConsumerStatefulWidget {
  const RecipeScreen({super.key, required this.initial});
  final Recipe initial;
  @override
  ConsumerState<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends ConsumerState<RecipeScreen> {
  late final _title = TextEditingController(text: widget.initial.title);
  late final _ingr = TextEditingController(text: widget.initial.ingredients.join('\n'));
  late final _steps = TextEditingController(text: widget.initial.steps);
  late final _k = TextEditingController(text: _s(widget.initial.perServing.kcal));
  late final _p = TextEditingController(text: _s(widget.initial.perServing.p));
  late final _c = TextEditingController(text: _s(widget.initial.perServing.c));
  late final _f = TextEditingController(text: _s(widget.initial.perServing.f));
  late bool _fav = widget.initial.favorite;
  int? _id;
  bool _busy = false;
  int _servings = 1;
  double _eat = 1;
  bool _batch = false;

  static String _s(double v) => v == 0 ? '' : v.toStringAsFixed(v >= 10 ? 0 : 1);
  double _d(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  /// Whole-pot macros stay fixed while the number of servings changes.
  late Macros _pot;

  @override
  void initState() {
    super.initState();
    _id = widget.initial.id;
    _servings = widget.initial.servings.clamp(1, 50);
    _pot = widget.initial.perServing * _servings.toDouble();
  }

  Macros get _per => _pot * (1 / _servings);

  void _setServings(int n) {
    final v = n.clamp(1, 50);
    setState(() {
      _servings = v;
      final m = _per;
      _k.text = _s(m.kcal);
      _p.text = _s(m.p);
      _c.text = _s(m.c);
      _f.text = _s(m.f);
    });
  }

  void _syncPot() => _pot = Macros(kcal: _d(_k), p: _d(_p), c: _d(_c), f: _d(_f)) * _servings.toDouble();

  Recipe _build() => Recipe(
        id: _id,
        title: _title.text.trim().isEmpty ? 'Przepis' : _title.text.trim(),
        servings: _servings,
        ingredients: _ingr.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        steps: _steps.text.trim(),
        sourceUrl: widget.initial.sourceUrl,
        perServing: Macros(kcal: _d(_k), p: _d(_p), c: _d(_c), f: _d(_f)),
        favorite: _fav,
      );

  Future<void> _save() async {
    _id = await ref.read(dbProvider).saveRecipe(_build());
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) {
      toast(context, 'Zapisano przepis');
      Navigator.pop(context);
    }
  }

  Future<void> _estimate() async {
    final r = _build();
    final ai = await ref.read(aiSettingsProvider.notifier).dietAi();
    if (!mounted) return;
    if (!ai.canRun(AiTask.estimation)) {
      toast(context, 'Skonfiguruj AI (Ja → Dostawca API), żeby policzyć makro.');
      return;
    }
    setState(() => _busy = true);
    try {
      final m = await ai.recipeMacros(r.title, r.servings, r.ingredients);
      _k.text = _s(m.kcal);
      _p.text = _s(m.p);
      _c.text = _s(m.c);
      _f.text = _s(m.f);
      _syncPot();
    } catch (e) {
      if (mounted) toast(context, 'Nie udało się policzyć: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _eatNow() async {
    final r = _build();
    final per = r.perServing * _eat;
    if (r.perServing.kcal <= 0) {
      toast(context, 'Najpierw wpisz lub policz kalorie.');
      return;
    }
    final db = ref.read(dbProvider);
    final t = ref.read(selectedDayProvider);
    await db.addEntry(Entry(day: dayKey(t), meal: mealForTime(t), name: r.title, grams: 0, macros: per, estimated: true));
    if (_batch) {
      final left = _servings - _eat;
      if (left > 0) {
        final shown = left == left.roundToDouble() ? '${left.round()}' : left.toStringAsFixed(1);
        await ref.read(pantryProvider.notifier).add(['${r.title} ($shown porcji)']);
      }
    }
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) {
      toast(context, 'Dodano: ${r.title}');
      Navigator.pop(context);
    }
  }

  String _portions(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1).replaceAll('.', ',');

  Widget _round(String t, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(t, style: fig(28, weight: 700, color: AppColors.accentDeep)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final per = _per;
    final eatMacros = per * _eat;
    Widget eatChip(double v, String label) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _eat = v),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _eat == v ? AppColors.hero : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _eat == v ? AppColors.accent : AppColors.outline, width: _eat == v ? 2 : 1),
              ),
              child: Text(label, style: fig(15, weight: 700)),
            ),
          ),
        );
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        ListView(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 110), children: [
          HeroZone(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              HeroBackHeader('Przepis', size: 15, actions: [
                IconButton(tooltip: 'Ulubiony', icon: Icon(_fav ? Icons.star : Icons.star_border, color: AppColors.accent), onPressed: () => setState(() => _fav = !_fav)),
                if (_id != null)
                  Transform.translate(
                    offset: const Offset(12, 0),
                    child: IconButton(
                      tooltip: 'Usuń przepis',
                      icon: Icon(Icons.delete_outline, color: AppColors.text2),
                      onPressed: () async {
                        await ref.read(dbProvider).deleteRecipe(_id!);
                        ref.read(dataVersionProvider.notifier).bump();
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ),
              ]),
              TextField(
                controller: _title,
                maxLines: 2,
                minLines: 1,
                style: display(30, height: 34 / 30),
                decoration: InputDecoration(hintText: 'Nazwa przepisu', hintStyle: display(30, color: AppColors.text2), filled: false, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, contentPadding: EdgeInsets.zero),
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _round('−', 'Mniej porcji', () => _setServings(_servings - 1)),
                Column(children: [
                  Text('$_servings', style: display(72)),
                  Text(_servings == 1 ? 'porcja w garnku' : 'porcji w garnku', style: fig(17, weight: 600)),
                ]),
                _round('+', 'Więcej porcji', () => _setServings(_servings + 1)),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Jedna porcja', style: fig(17, weight: 700)),
                Text(per.kcal == 0 ? 'brak kalorii' : '~${n0(per.kcal)} kcal', style: display(28)),
              ]),
              const SizedBox(height: 4),
              Text(per.kcal == 0 ? 'Wpisz makro niżej albo poproś AI o policzenie.' : 'Cały garnek ~${n0(_pot.kcal)} kcal. Składniki przeliczone z przepisu.', style: fig(14, color: AppColors.text2)),
              const SizedBox(height: 16),
              Row(children: [
                Text('B ${n0(per.p)} g', style: fig(15, weight: 600, color: AppColors.protein)),
                const SizedBox(width: 20),
                Text('W ${n0(per.c)} g', style: fig(15, weight: 600, color: AppColors.carbs)),
                const SizedBox(width: 20),
                Text('T ${n0(per.f)} g', style: fig(15, weight: 600, color: AppColors.fat)),
              ]),
              const SizedBox(height: 20),
              Text('Ile zjadłeś?', style: fig(16, weight: 700)),
              const SizedBox(height: 10),
              Row(children: [eatChip(1, '1 porcja'), const SizedBox(width: 8), eatChip(1.5, '1,5'), const SizedBox(width: 8), eatChip(2, '2')]),
              Container(
                margin: const EdgeInsets.only(top: 20),
                constraints: const BoxConstraints(minHeight: 60),
                decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: AppColors.line))),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Ugotowałem na kilka dni', style: fig(16, weight: 600)),
                      Text(_batch ? 'Zjem dziś ${_portions(_eat)} ${_eat == 1 ? 'porcję' : 'porcji'}, ${_portions((_servings - _eat).clamp(0, 99).toDouble())} zostaje w lodówce' : 'Reszta porcji trafi do lodówki', style: fig(14, color: AppColors.text2, height: 20 / 14)),
                    ]),
                  ),
                  Switch(value: _batch, onChanged: (v) => setState(() => _batch = v)),
                ]),
              ),
              const SizedBox(height: 28),
              Text('Szczegóły przepisu', style: fig(18, weight: 700)),
              const SizedBox(height: 12),
              Text('Na jedną porcję', style: fig(14, color: AppColors.text2)),
              const SizedBox(height: 6),
              Row(children: [
                for (final e in [(_k, 'kcal'), (_p, 'B'), (_c, 'W'), (_f, 'T')])
                  Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: TextField(controller: e.$1, onChanged: (_) => setState(_syncPot), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: e.$2)))),
              ]),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _estimate,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_outlined),
                label: const Text('Policz makro (AI)'),
              ),
              const SizedBox(height: 14),
              TextField(controller: _ingr, minLines: 4, maxLines: 12, decoration: const InputDecoration(labelText: 'Składniki (jeden w linii)', alignLabelWithHint: true)),
              const SizedBox(height: 10),
              TextField(controller: _steps, minLines: 4, maxLines: 16, decoration: const InputDecoration(labelText: 'Kroki', alignLabelWithHint: true)),
              if (widget.initial.sourceUrl.isNotEmpty)
                TextButton.icon(onPressed: () => launchUrl(Uri.parse(widget.initial.sourceUrl), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new), label: const Text('Otwórz źródło')),
              TextButton.icon(
                onPressed: () {
                  ref.read(shoppingProvider.notifier).add([for (final i in _build().ingredients) '0|$i']);
                  toast(context, 'Składniki dodane do listy zakupów');
                },
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Składniki do listy zakupów'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _save, child: const Text('Zapisz przepis')),
            ]),
          ),
        ]),
        Positioned(
          left: 24,
          right: 24,
          bottom: MediaQuery.of(context).padding.bottom + 24,
          child: FilledButton(
            onPressed: _eatNow,
            child: Text('Zjadłem ${_portions(_eat)} ${_eat == 1 ? 'porcję' : 'porcji'}, ~${n0(eatMacros.kcal)} kcal'),
          ),
        ),
      ]),
    );
  }
}
