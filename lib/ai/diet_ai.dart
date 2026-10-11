import 'dart:convert';

import '../domain/models.dart';
import 'ai_settings.dart';
import 'llm_api.dart';
import 'local_runtime.dart';

class ParsedItem {
  const ParsedItem(this.name, {this.grams, this.qty});
  final String name;

  /// Total grams/ml for the whole item when known.
  final double? grams;
  final double? qty;
}

class EstimatedFood {
  const EstimatedFood(this.name, this.kcal100, this.p100, this.c100, this.f100, this.servingG);
  final String name;
  final double kcal100, p100, c100, f100, servingG;
}

/// All diet-related LLM calls, routed to the local model or the API provider
/// depending on the per-task engine setting. Returns null when no engine is
/// usable so callers can fall back to dumb parsing.
class DietAi {
  DietAi({required this.settings, required this.llm, required this.local, this.onTokens});
  final AiSettings settings;
  final LlmApi? llm;
  final LocalRuntime local;
  final Future<void> Function(int)? onTokens;

  bool canRun(AiTask t) => settings.engineFor(t) == AiEngine.api ? llm != null : local.isReady;

  Future<String> _run(AiTask t, String system, String user, {bool json = false}) async {
    if (settings.engineFor(t) == AiEngine.api) {
      final api = llm;
      if (api == null) throw LlmException('Dostawca API nie jest skonfigurowany.');
      final r = await api.complete(system: system, user: user, json: json, maxTokens: 1500);
      await onTokens?.call(r.totalTokens);
      return r.text;
    }
    return local.generate(system: system, user: user, json: json);
  }

  static dynamic extractJson(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'^```(?:json)?', multiLine: true), '').replaceAll('```', '').trim();
    final a = s.indexOf(RegExp(r'[\[{]'));
    final b = s.lastIndexOf(RegExp(r'[\]}]'));
    if (a < 0 || b <= a) throw const FormatException('brak JSON');
    return jsonDecode(s.substring(a, b + 1));
  }

  static double? _d(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(',', '.'));

  static const _parsePrompt = '''
Jesteś parserem opisu posiłku mówionego po polsku. Użytkownik wymienia, co zjadł lub wypił.
Zwróć WYŁĄCZNIE JSON: {"items":[{"name":"krótka nazwa produktu lub dania","qty":liczba_sztuk_lub_null,"grams":łączna_masa_w_gramach_lub_ml}]}
Zasady:
- Jedna pozycja na produkt/danie ("kanapka z serem" to jedna pozycja).
- grams = Twoje najlepsze oszacowanie CAŁKOWITEJ masy pozycji (np. 2 jajka = 110, szklanka mleka = 250, kromka chleba = 35, talerz zupy = 350). Jeśli użytkownik podał gramy, użyj ich.
- name w mianowniku, bez ilości.
Bez komentarzy.''';

  Future<List<ParsedItem>> parseMeal(String text) async {
    final out = await _run(AiTask.foodParsing, _parsePrompt, text, json: true);
    final j = extractJson(out);
    final list = (j is Map ? j['items'] : j) as List;
    return [
      for (final e in list.whereType<Map>())
        if ('${e['name'] ?? ''}'.trim().isNotEmpty)
          ParsedItem('${e['name']}'.trim(), grams: _d(e['grams']), qty: _d(e['qty'])),
    ];
  }

  static const _estPrompt = '''
Jesteś dietetykiem. Podaj typowe wartości odżywcze na 100 g (lub 100 ml) dla produktu/dania z polskiej kuchni lub restauracji.
Zwróć WYŁĄCZNIE JSON: {"kcal100":n,"p100":n,"c100":n,"f100":n,"serving_g":typowa_porcja_w_gramach}
p = białko, c = węglowodany, f = tłuszcz, w gramach. Bez komentarzy.''';

  Future<EstimatedFood> estimate(String name) async {
    final j = extractJson(await _run(AiTask.estimation, _estPrompt, name, json: true)) as Map;
    final kcal = _d(j['kcal100']);
    if (kcal == null) throw const FormatException('brak kcal');
    return EstimatedFood(name, kcal, _d(j['p100']) ?? 0, _d(j['c100']) ?? 0, _d(j['f100']) ?? 0,
        _d(j['serving_g']) ?? 100);
  }

  static const _recipePrompt = '''
Oszacuj wartości odżywcze JEDNEJ PORCJI przepisu na podstawie składników.
Zwróć WYŁĄCZNIE JSON: {"kcal":n,"p":n,"c":n,"f":n} (p=białko, c=węglowodany, f=tłuszcz w gramach na porcję). Bez komentarzy.''';

  Future<Macros> recipeMacros(String title, int servings, List<String> ingredients) async {
    final user = 'Przepis: $title\nLiczba porcji: $servings\nSkładniki:\n${ingredients.join('\n')}';
    final j = extractJson(await _run(AiTask.estimation, _recipePrompt, user, json: true)) as Map;
    return Macros(
        kcal: _d(j['kcal']) ?? 0, p: _d(j['p']) ?? 0, c: _d(j['c']) ?? 0, f: _d(j['f']) ?? 0);
  }

  static const _advicePrompt = '''
Jesteś pomocnym, życzliwym dietetykiem dla osoby z ADHD, która jest leniwa w gotowaniu i planowaniu.
Odpowiadaj po polsku, krótko (maks. ~120 słów), konkretnie, bez moralizowania i bez wyrzutów.
Proponuj proste rzeczy: mało składników, mało zmywania, szybkie. Gdy proponujesz posiłek, podaj orientacyjne kcal i białko.''';

  Future<String> advise(String question, String context) =>
      _run(AiTask.advice, _advicePrompt, 'Kontekst dnia:\n$context\n\nPytanie: $question');

  static const _ideaPrompt = '''
Wymyśl JEDEN prosty przepis (maks. 6 składników, do 20 minut) spełniający wymagania użytkownika.
Zwróć WYŁĄCZNIE JSON: {"title":"","servings":1,"ingredients":["200 g ..."],"steps":["..."],"kcal":n,"p":n,"c":n,"f":n}
kcal/p/c/f dotyczą jednej porcji. Po polsku. Bez komentarzy.''';

  Future<Recipe> recipeIdea(String request) async {
    final j = extractJson(await _run(AiTask.advice, _ideaPrompt, request, json: true)) as Map;
    final steps = (j['steps'] as List? ?? const []).map((e) => '$e').toList();
    return Recipe(
      title: '${j['title'] ?? 'Pomysł'}',
      servings: (_d(j['servings']) ?? 1).round().clamp(1, 20),
      ingredients: (j['ingredients'] as List? ?? const []).map((e) => '$e').toList(),
      steps: [for (var i = 0; i < steps.length; i++) '${i + 1}. ${steps[i]}'].join('\n'),
      perServing: Macros(
          kcal: _d(j['kcal']) ?? 0, p: _d(j['p']) ?? 0, c: _d(j['c']) ?? 0, f: _d(j['f']) ?? 0),
    );
  }
}
