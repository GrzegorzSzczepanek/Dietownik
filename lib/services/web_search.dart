import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WebHit {
  const WebHit(this.title, this.url, this.snippet);
  final String title, url, snippet;
}

/// Which search service the key belongs to. Tavily has a free monthly quota without a card;
/// Brave removed its free tier in 2026. Without a key the app tries keyless sources.
class SearchBackend {
  static String provider = 'tavily';
  static const providers = {'tavily': 'Tavily (darmowy limit, bez karty)', 'brave': 'Brave (płatny, wymaga karty)'};

  static Future<void> load() async {
    provider = (await SharedPreferences.getInstance()).getString('search_provider') ?? 'tavily';
  }

  static Future<void> save(String p) async {
    provider = p;
    await (await SharedPreferences.getInstance()).setString('search_provider', p);
  }
}

String _clean(Object? s) => '$s'
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&quot;', '"')
    .replaceAll('&#x27;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

Dio _dio() => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) Chrome/124 Mobile Safari/537.36'},
    ));

/// Web search with the configured key, or a keyless best effort when there is none.
/// Never throws; returns an empty list when nothing could be fetched.
Future<List<WebHit>> webSearch(String query, String? key, {int count = 8, Dio? dio}) async {
  final d = dio ?? _dio();
  if (key != null && key.isNotEmpty) {
    return SearchBackend.provider == 'brave' ? _brave(d, query, key, count) : _tavily(d, query, key, count);
  }
  final ddg = await _duckDuckGo(d, query, count);
  return ddg.isNotEmpty ? ddg : _wikipedia(d, query, count);
}

/// Kept for older call sites.
Future<List<WebHit>> braveSearch(String query, String? key, {int count = 8, Dio? dio}) =>
    webSearch(query, key, count: count, dio: dio);

Future<List<WebHit>> _tavily(Dio d, String q, String key, int count) async {
  try {
    final r = await d.post('https://api.tavily.com/search',
        options: Options(headers: {'Authorization': 'Bearer $key'}),
        data: {'query': q, 'max_results': count, 'search_depth': 'basic'});
    final results = ((r.data as Map)['results'] as List?) ?? const [];
    return [for (final e in results.whereType<Map>()) WebHit(_clean(e['title']), '${e['url']}', _clean(e['content']))];
  } catch (_) {
    return [];
  }
}

Future<List<WebHit>> _brave(Dio d, String q, String key, int count) async {
  try {
    final r = await d.get('https://api.search.brave.com/res/v1/web/search',
        queryParameters: {'q': q, 'country': 'pl', 'search_lang': 'pl', 'count': count},
        options: Options(headers: {'X-Subscription-Token': key, 'Accept': 'application/json'}));
    final results = ((r.data as Map)['web']?['results'] as List?) ?? const [];
    return [for (final e in results.whereType<Map>()) WebHit(_clean(e['title']), '${e['url']}', _clean(e['description']))];
  } catch (_) {
    return [];
  }
}

/// DuckDuckGo's HTML page. It often serves a bot check to servers, but usually works from a phone.
Future<List<WebHit>> _duckDuckGo(Dio d, String q, int count) async {
  try {
    final r = await d.get<String>('https://html.duckduckgo.com/html/',
        queryParameters: {'q': q, 'kl': 'pl-pl'}, options: Options(responseType: ResponseType.plain));
    final html = r.data ?? '';
    if (r.statusCode != 200 || html.contains('anomaly')) return [];
    final links = RegExp(r'class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>', dotAll: true).allMatches(html).toList();
    final snippets = RegExp(r'class="result__snippet"[^>]*>(.*?)</a>', dotAll: true).allMatches(html).toList();
    final out = <WebHit>[];
    for (var i = 0; i < links.length && out.length < count; i++) {
      var url = links[i].group(1)!.replaceAll('&amp;', '&');
      final u = Uri.tryParse(url.startsWith('//') ? 'https:$url' : url);
      final real = u?.queryParameters['uddg'];
      if (real != null) url = real;
      if (!url.startsWith('http')) continue;
      out.add(WebHit(_clean(links[i].group(2)), url, i < snippets.length ? _clean(snippets[i].group(1)) : ''));
    }
    return out;
  } catch (_) {
    return [];
  }
}

/// Last resort: Polish Wikipedia (free, no key). Good for general nutrition facts, not for recipes.
Future<List<WebHit>> _wikipedia(Dio d, String q, int count) async {
  try {
    final r = await d.get('https://pl.wikipedia.org/w/api.php',
        queryParameters: {'action': 'query', 'list': 'search', 'srsearch': q, 'format': 'json', 'srlimit': count});
    final results = (((r.data as Map)['query'] as Map?)?['search'] as List?) ?? const [];
    return [
      for (final e in results.whereType<Map>())
        WebHit(_clean(e['title']), 'https://pl.wikipedia.org/?curid=${e['pageid']}', _clean(e['snippet']))
    ];
  } catch (_) {
    return [];
  }
}
