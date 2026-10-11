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
    return Scaffold(
      appBar: AppBar(title: const Text('Co mam w lodówce'), actions: [
        IconButton(icon: const Icon(Icons.key), tooltip: 'Klucz Brave Search', onPressed: _braveKey),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
        TextField(
          controller: _input,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: 'jajka, ser, pomidor…', suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _add)),
          onSubmitted: (_) => _add(),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final p in pantry) InputChip(label: Text(p), onDeleted: () => ref.read(pantryProvider.notifier).remove(p)),
        ]),
        if (pantry.isNotEmpty)
          Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => ref.read(pantryProvider.notifier).replace(const []), child: const Text('Wyczyść'))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: _busy || pantry.isEmpty ? null : _search, icon: const Icon(Icons.travel_explore), label: const Text('Szukaj w sieci'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: _busy || pantry.isEmpty ? null : _aiIdea, icon: const Icon(Icons.auto_awesome), label: const Text('Pomysł AI'))),
        ]),
        Padding(
          padding: EdgeInsets.only(top: 6, bottom: 12),
          child: Text('Wyniki z sieci to prawdziwe przepisy ze stron. Zgodność liczę ze składników, nie zgaduje jej AI. „Pomysł AI” jest nieweryfikowany.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ),
        if (_busy) const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
        if (_note != null) Text(_note!, style: TextStyle(color: AppColors.amberInk)),
        for (final m in _results ?? const <RecipeMatch>[]) _MatchCard(m),
      ]),
    );
  }
}

class _MatchCard extends ConsumerWidget {
  const _MatchCard(this.m);
  final RecipeMatch m;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pct = (m.score * 100).round();
    final color = pct >= 80 ? AppColors.green : (pct >= 50 ? AppColors.amber : AppColors.muted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecipeScreen(initial: m.recipe))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(m.recipe.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              Text('$pct%', style: figure(size: 20, color: color)),
            ]),
            const SizedBox(height: 6),
            ProgressBar(m.score, color: color, height: 8),
            const SizedBox(height: 8),
            Text('Masz ${m.have.length} z ${m.have.length + m.missing.length} składników', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (m.missing.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Brakuje: ${m.missing.join('; ')}', style: TextStyle(color: AppColors.amberInk, fontSize: 13)),
            ],
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              Pill(m.verified ? 'prawdziwy przepis' : 'AI — nieweryfikowane', bg: m.verified ? AppColors.greenSoft : AppColors.amberSoft, fg: m.verified ? AppColors.green : AppColors.amberInk),
              if (m.recipe.perServing.kcal > 0) Pill('${n0(m.recipe.perServing.kcal)} kcal/porcja'),
            ]),
            if (m.missing.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  ref.read(shoppingProvider.notifier).add([for (final x in m.missing) '0|$x']);
                  toast(context, 'Dodano ${m.missing.length} do listy zakupów');
                },
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Brakujące do zakupów'),
              ),
          ]),
        ),
      ),
    );
  }
}
