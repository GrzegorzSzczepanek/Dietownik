import 'package:dio/dio.dart';

class WebHit {
  const WebHit(this.title, this.url, this.snippet);
  final String title, url, snippet;
}

/// Brave Search API (free tier). Returns titles + snippets; the app, not the
/// model, does the searching, so any LLM provider can use the results.
Future<List<WebHit>> braveSearch(String query, String? key, {int count = 8, Dio? dio}) async {
  if (key == null || key.isEmpty) return [];
  try {
    final r = await (dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 12))))
        .get('https://api.search.brave.com/res/v1/web/search',
            queryParameters: {'q': query, 'country': 'pl', 'search_lang': 'pl', 'count': count},
            options: Options(headers: {'X-Subscription-Token': key, 'Accept': 'application/json'}));
    final results = ((r.data as Map)['web']?['results'] as List?) ?? const [];
    String clean(Object? s) => '$s'.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&quot;', '"').replaceAll('&#x27;', "'").replaceAll('&amp;', '&');
    return [
      for (final e in results.whereType<Map>())
        WebHit(clean(e['title']), '${e['url']}', clean(e['description'])),
    ];
  } catch (_) {
    return [];
  }
}
