import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../ai/ai_settings.dart';
import '../core/theme.dart';
import '../providers.dart';
import '../services/recipe_search.dart';
import 'common.dart';
import 'recipes_screen.dart';
import 'widgets.dart';

class FridgeScreen extends ConsumerStatefulWidget {
  const FridgeScreen({super.key});
  @override
  ConsumerState<FridgeScreen> createState() => _FridgeScreenState();
}

class _FridgeScreenState extends ConsumerState<FridgeScreen> {
  final _input = TextEditingController();
  List<RecipeMatch>? _results;
  bool _busy = false;
  String? _note;

  void _add() {
    ref.read(pantryProvider.notifier).add(_input.text.split(RegExp(r'[,;\n]')));
    _input.clear();
  }

  Future<void> _search() async {
    final pantry = ref.read(pantryProvider);
    if (pantry.isEmpty) return;
    setState(() { _busy = true; _note = null; _results = null; });
    final key = await const FlutterSecureStorage().read(key: 'brave_key');
    final r = await RecipeWebSearch(braveKey: key).search(pantry);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _results = r;
      _note = r.isEmpty ? 'Nic nie znalazłem (brak internetu albo zbyt dziwne składniki). Spróbuj mniej składników.' : null;
    });
  }

  Future<void> _aiIdea() async {
    final pantry = ref.read(pantryProvider);
    final ai = await ref.read(aiSettingsProvider.notifier).dietAi();
    if (!ai.canRun(AiTask.advice)) {
      if (mounted) toast(context, 'Skonfiguruj AI w Ja, żeby generować pomysły.');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await ai.recipeIdea('Użyj głównie tych składników: ${pantry.join(', ')}. Nie dodawaj więcej niż 2 dodatkowych.');
      if (!mounted) return;
      final m = matchRecipe(r, pantry, verified: false);
      setState(() { _results = [m, ...?_results]; _busy = false; });
    } catch (e) {
      if (mounted) { setState(() => _busy = false); toast(context, 'AI nie dało rady: $e'); }
    }
  }

  Future<void> _braveKey() async {
    const storage = FlutterSecureStorage();
    final ctrl = TextEditingController(text: await storage.read(key: 'brave_key') ?? '');
    if (!mounted) return;
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Brave Search API (opcjonalnie)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Bez klucza szukam w Kwestii Smaku. Z kluczem szukam w całym polskim internecie. Darmowy klucz: brave.com/search/api.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          TextField(controller: ctrl, obscureText: true, decoration: const InputDecoration(labelText: 'Klucz API')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Zapisz')),
        ],
      ),
    );
    if (v == null) return;
    v.isEmpty ? await storage.delete(key: 'brave_key') : await storage.write(key: 'brave_key', value: v);
  }

  @override
  Widget build(BuildContext context) {
    final pantry = ref.watch(pantryProvider);
    final bottom = MediaQuery.of(context).padding.bottom + 32;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListView(padding: EdgeInsets.only(bottom: bottom), children: [
        HeroZone(
          bottom: 20,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            HeroBackHeader('Co mam w lodówce', actions: [
              Transform.translate(
                offset: const Offset(12, 0),
                child: IconButton(icon: Icon(Icons.key, color: AppColors.text2), tooltip: 'Klucz Brave Search', onPressed: _braveKey),
              ),
            ]),
            const SizedBox(height: 8),
            HeroField(
              controller: _input,
              hint: 'Dodaj składnik',
              onSubmitted: (_) => _add(),
              actions: [AccentSquareButton(onTap: _add, icon: Icons.add, semantics: 'Dodaj składnik')],
            ),
            if (pantry.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in pantry)
                  GestureDetector(
                    onTap: () => ref.read(pantryProvider.notifier).remove(p),
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.only(left: 16, right: 10),
                      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(22)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(p, style: fig(15, weight: 600)),
                        const SizedBox(width: 6),
                        Icon(Icons.close, size: 18, color: AppColors.text2),
                      ]),
                    ),
                  ),
              ]),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _busy || pantry.isEmpty ? null : _search,
                child: Text(_busy ? 'Szukam…' : 'Szukaj przepisów w sieci'),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('To prawdziwe przepisy ze stron. Zgodność liczę ze składników, nie zgaduje jej AI.', style: fig(15, color: AppColors.text3, height: 22 / 15)),
            const SizedBox(height: 8),
            if (_busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            if (_note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note!, style: fig(15, weight: 600, color: AppColors.warn))),
            for (var i = 0; i < (_results ?? const <RecipeMatch>[]).length; i++) _MatchRow(_results![i], last: i == _results!.length - 1),
            if (pantry.isNotEmpty)
              NavRow(
                topLine: _results == null || _results!.isEmpty,
                bottomLine: true,
                minHeight: 60,
                leading: Icon(Icons.auto_awesome_outlined, color: AppColors.accent),
                title: 'Pomysł AI z tych składników',
                subtitle: 'Niezweryfikowany, AI może się mylić',
                subtitleColor: AppColors.warn,
                onTap: _busy ? null : _aiIdea,
              ),
          ]),
        ),
      ]),
    );
  }
}

class _MatchRow extends ConsumerWidget {
  const _MatchRow(this.m, {required this.last});
  final RecipeMatch m;
  final bool last;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pct = (m.score * 100).round();
    final total = m.have.length + m.missing.length;
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecipeScreen(initial: m.recipe))),
      child: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line), bottom: last ? BorderSide(color: AppColors.line) : BorderSide.none)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.verified ? m.recipe.title : 'Pomysł AI: ${m.recipe.title}', style: fig(17, weight: 700)),
                Text(m.verified ? 'Masz ${m.have.length} z $total składników' : 'Niezweryfikowany · masz ${m.have.length} z $total',
                    style: fig(14, weight: m.verified ? 400 : 600, color: m.verified ? AppColors.text2 : AppColors.warn)),
              ]),
            ),
            const SizedBox(width: 12),
            Text('$pct%', style: display(32, color: pct >= 60 ? AppColors.text : AppColors.text2)),
          ]),
          if (m.missing.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Brakuje: ${m.missing.join(', ')}', style: fig(14, color: AppColors.text3)),
            InkWell(
              onTap: () {
                ref.read(shoppingProvider.notifier).add([for (final x in m.missing) '0|$x']);
                toast(context, 'Dodano ${m.missing.length} do listy zakupów');
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(children: [
                  Icon(Icons.add_shopping_cart, size: 20, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text('Dodaj brakujące do zakupów', style: fig(15, weight: 600, color: AppColors.accent)),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
