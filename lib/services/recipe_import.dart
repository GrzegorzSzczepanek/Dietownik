import 'dart:convert';

import 'package:dio/dio.dart';

import '../domain/models.dart';

/// Imports a recipe from any page that publishes schema.org/Recipe JSON-LD
/// (most Polish recipe sites do: aniagotuje, kwestiasmaku, mojewypieki ...).
Future<Recipe?> importRecipeFromUrl(String url, {Dio? dio}) async {
  final d = dio ??
      Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'User-Agent': 'Mozilla/5.0 (Android) Dietownik/1.0'},
      ));
  final res = await d.get<String>(url, options: Options(responseType: ResponseType.plain));
  return parseRecipeHtml(res.data ?? '', url);
}

Recipe? parseRecipeHtml(String html, String url) {
  final re = RegExp(r'<script[^>]*application/ld\+json[^>]*>(.*?)</script>',
      dotAll: true, caseSensitive: false);
  for (final m in re.allMatches(html)) {
    try {
      final node = _findRecipe(jsonDecode(m.group(1)!.trim()));
      if (node != null) return _toRecipe(node, url);
    } catch (_) {}
  }
  return null;
}

Map? _findRecipe(dynamic j) {
  if (j is List) {
    for (final e in j) {
      final r = _findRecipe(e);
      if (r != null) return r;
    }
  } else if (j is Map) {
    final t = j['@type'];
    if (t == 'Recipe' || (t is List && t.contains('Recipe'))) return j;
    if (j['@graph'] != null) return _findRecipe(j['@graph']);
  }
  return null;
}

String _clean(String s) => s
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

List<String> _steps(dynamic v) {
  if (v is String) return [for (final s in v.split(RegExp(r'\n+'))) if (_clean(s).isNotEmpty) _clean(s)];
  if (v is List) return [for (final e in v) ..._steps(e)];
  if (v is Map) {
    if (v['itemListElement'] != null) return _steps(v['itemListElement']);
    return _steps(v['text'] ?? v['name'] ?? '');
  }
  return const [];
}

Recipe _toRecipe(Map n, String url) {
  final yieldRaw = n['recipeYield'];
  final ys = yieldRaw is List ? yieldRaw.join(' ') : '${yieldRaw ?? ''}';
  final servings = int.tryParse(RegExp(r'\d+').firstMatch(ys)?.group(0) ?? '') ?? 1;
  final nut = n['nutrition'];
  double? pick(String k) {
    if (nut is! Map) return null;
    final m = RegExp(r'[\d.,]+').firstMatch('${nut[k] ?? ''}');
    return m == null ? null : double.tryParse(m.group(0)!.replaceAll(',', '.'));
  }

  final steps = _steps(n['recipeInstructions']);
  return Recipe(
    title: _clean('${n['name'] ?? 'Przepis'}'),
    servings: servings < 1 ? 1 : servings,
    ingredients: [for (final i in (n['recipeIngredient'] as List? ?? const [])) _clean('$i')],
    steps: [for (var i = 0; i < steps.length; i++) '${i + 1}. ${steps[i]}'].join('\n'),
    sourceUrl: url,
    perServing: Macros(
      kcal: pick('calories') ?? 0,
      p: pick('proteinContent') ?? 0,
      c: pick('carbohydrateContent') ?? 0,
      f: pick('fatContent') ?? 0,
    ),
  );
}
