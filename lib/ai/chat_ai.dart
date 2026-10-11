import 'dart:convert';

import '../services/web_search.dart';
import 'diet_ai.dart';

class ChatRecipe {
  const ChatRecipe({required this.title, this.kcal = 0, this.p = 0, this.c = 0, this.f = 0, this.note = '', this.ingredients = const [], this.missing = const []});
  final String title, note;
  final double kcal, p, c, f;
  final List<String> ingredients, missing;

  Map<String, dynamic> toJson() => {
        'title': title, 'kcal': kcal, 'p': p, 'c': c, 'f': f, 'note': note, 'ingredients': ingredients, 'missing': missing,
      };

  factory ChatRecipe.fromJson(Map j) {
    double d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(',', '.')) ?? 0;
    List<String> l(dynamic v) => (v as List? ?? const []).map((e) => '$e').toList();
    return ChatRecipe(
      title: '${j['title'] ?? ''}',
      kcal: d(j['kcal']),
      p: d(j['p']),
      c: d(j['c']),
      f: d(j['f']),
      note: '${j['note'] ?? ''}',
      ingredients: l(j['ingredients']),
      missing: l(j['missing']),
    );
  }
}

class ChatSource {
  const ChatSource(this.title, this.url, this.snippet);
  final String title, url, snippet;
  String get host => Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? url;
  Map<String, dynamic> toJson() => {'title': title, 'url': url, 'snippet': snippet};
  factory ChatSource.fromJson(Map j) => ChatSource('${j['title'] ?? ''}', '${j['url'] ?? ''}', '${j['snippet'] ?? ''}');
}

class ChatReply {
  const ChatReply({required this.answer, this.recipe, this.suggestions = const [], this.used = const [], this.sources = const [], this.searched = false});
  final String answer;
  final ChatRecipe? recipe;
  final List<String> suggestions, used;
  final List<ChatSource> sources;

  /// A web search was attempted for this answer.
  final bool searched;
}

const _chatPrompt = '''
Jesteś życzliwym dietetykiem w aplikacji do śledzenia jedzenia. Użytkownik jest leniwy i ma ADHD: odpowiadaj po polsku, krótko (do ok. 120 słów), konkretnie, bez moralizowania i bez wyrzutów.
Dostajesz KONTEKST użytkownika (tylko to, co zezwolił) i opcjonalnie WYNIKI WYSZUKIWANIA ponumerowane [1], [2]...
Zasady:
- Fakty ze świata (wartości odżywcze, przepisy) opieraj na WYNIKACH i oznaczaj numerem źródła w tekście, np. „… [1][2]”. Nie wymyślaj źródeł ani numerów. Jeśli wyniki nie wystarczają, napisz to wprost.
- Gdy proponujesz konkretny posiłek, wypełnij pole recipe (wartości SZACUNKOWE na jedną porcję; w note napisz skąd szacunek). W missing wypisz składniki, których użytkownik nie ma w lodówce.
- Nie udawaj pewności. Kalorie i makro to szacunek.
Zwróć WYŁĄCZNIE JSON:
{"answer":"tekst z odnośnikami [n]","recipe":null lub {"title":"","kcal":n,"p":n,"c":n,"f":n,"note":"","ingredients":[""],"missing":[""]},"suggestions":["krótka propozycja dalszego pytania","..."],"used":["nazwy użytych części kontekstu"]}''';

extension ChatAi on DietAi {
  /// One chat turn. Searching is done here (not by the model) so any provider works.
  Future<ChatReply> chat({
    required String question,
    required List<Map<String, String>> history,
    required String context,
    required bool webSearch,
  }) async {
    var hits = <WebHit>[];
    var searched = false;
    if (webSearch && braveKey != null && braveKey!.isNotEmpty) {
      searched = true;
      hits = await braveSearch(question, braveKey, count: 6);
    }
    final src = [for (final h in hits.take(5)) ChatSource(h.title, h.url, h.snippet)];
    final results = src.isEmpty
        ? 'WYNIKI WYSZUKIWANIA: brak (odpowiedz bez źródeł i zaznacz, że nie szukałeś w internecie).'
        : 'WYNIKI WYSZUKIWANIA:\n${[for (var i = 0; i < src.length; i++) '[${i + 1}] ${src[i].title} (${src[i].host})\n${src[i].snippet}'].join('\n\n')}';
    final conv = history.isEmpty ? '' : 'DOTYCHCZASOWA ROZMOWA:\n${[for (final m in history) '${m['role'] == 'user' ? 'Użytkownik' : 'Asystent'}: ${m['text']}'].join('\n')}\n\n';
    final user = 'KONTEKST:\n$context\n\n$results\n\n$conv''PYTANIE: $question';
    final raw = await runChat(_chatPrompt, user);
    try {
      final j = DietAi.extractJson(raw) as Map;
      final r = j['recipe'];
      return ChatReply(
        answer: '${j['answer'] ?? raw}'.trim(),
        recipe: r is Map && '${r['title'] ?? ''}'.isNotEmpty ? ChatRecipe.fromJson(r) : null,
        suggestions: (j['suggestions'] as List? ?? const []).map((e) => '$e').where((e) => e.isNotEmpty).take(3).toList(),
        used: (j['used'] as List? ?? const []).map((e) => '$e').toList(),
        sources: src,
        searched: searched,
      );
    } catch (_) {
      return ChatReply(answer: raw.trim(), sources: src, searched: searched);
    }
  }
}

String encodeMeta(ChatReply r) => jsonEncode({
      'recipe': r.recipe?.toJson(),
      'suggestions': r.suggestions,
      'used': r.used,
      'sources': [for (final s in r.sources) s.toJson()],
      'searched': r.searched,
    });
