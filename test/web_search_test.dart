import 'dart:convert';
import 'dart:typed_data';

import 'package:dietownik/services/web_search.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fake implements HttpClientAdapter {
  _Fake(this.handler);
  final (int, String) Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final (code, text) = handler(o);
    return ResponseBody.fromString(text, code, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('tavily results are mapped', () async {
    SearchBackend.provider = 'tavily';
    final d = Dio()..httpClientAdapter = _Fake((o) => (200, jsonEncode({'results': [{'title': 'Omlet', 'url': 'https://a.pl/x', 'content': '150 kcal na 100 g'}]})));
    final r = await webSearch('omlet', 'KEY', dio: d);
    expect(r.single.url, 'https://a.pl/x');
    expect(r.single.snippet, contains('150 kcal'));
  });

  test('keyless: DuckDuckGo html is parsed, redirect unwrapped', () async {
    const html = '<a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fkalorie.pl%2Fomlet&amp;rut=1">Omlet <b>kalorie</b></a>'
        '<a class="result__snippet" href="#">Omlet ma <b>154</b> kcal</a>';
    final d = Dio()..httpClientAdapter = _Fake((o) => (200, html));
    final r = await webSearch('omlet', null, dio: d);
    expect(r.single.url, 'https://kalorie.pl/omlet');
    expect(r.single.title, 'Omlet kalorie');
    expect(r.single.snippet, 'Omlet ma 154 kcal');
  });

  test('keyless: bot check falls back to Wikipedia', () async {
    final d = Dio()
      ..httpClientAdapter = _Fake((o) => o.uri.host.contains('duckduckgo')
          ? (200, 'anomaly-modal')
          : (200, jsonEncode({'query': {'search': [{'title': 'Omlet', 'pageid': 7, 'snippet': 'danie z <span>jajek</span>'}]}})));
    final r = await webSearch('omlet', null, dio: d);
    expect(r.single.url, contains('curid=7'));
    expect(r.single.snippet, 'danie z jajek');
  });

  test('network failure returns empty list', () async {
    final d = Dio()..httpClientAdapter = _Fake((o) => throw DioException(requestOptions: o, type: DioExceptionType.connectionError));
    expect(await webSearch('x', null, dio: d), isEmpty);
  });
}
