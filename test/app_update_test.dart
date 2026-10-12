import 'dart:convert';
import 'dart:typed_data';

import 'package:dietownik/core/app_update.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fake implements HttpClientAdapter {
  _Fake(this.handler);
  final (int, String) Function() handler;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    calls++;
    final (code, text) = handler();
    if (code == 0) throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
    return ResponseBody.fromString(text, code, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

String _release(String tag, {bool pre = false}) => jsonEncode({
      'tag_name': tag,
      'html_url': 'https://github.com/x/y/releases/tag/$tag',
      'body': 'Notes',
      'prerelease': pre,
      'assets': [
        {'name': 'Dietownik-9.9.9-arm64.apk', 'browser_download_url': 'https://dl/arm64.apk'},
        {'name': 'Dietownik-9.9.9-armv7.apk', 'browser_download_url': 'https://dl/armv7.apk'},
      ],
    });

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('version comparison', () {
    expect(isNewerVersion('v1.0.5', '1.0.4'), isTrue);
    expect(isNewerVersion('1.1.0', '1.0.9'), isTrue);
    expect(isNewerVersion('v1.0.4', '1.0.4'), isFalse);
    expect(isNewerVersion('1.0.3', '1.0.4'), isFalse);
    expect(isNewerVersion('2.0', '1.9.9'), isTrue);
    expect(isNewerVersion('1.0.4+9', '1.0.4+1'), isFalse); // build numbers never trigger a prompt
  });

  test('release notes are shown as short plain text', () {
    const md = '## Dietownik 1.0.6\n\n**What\'s new**\n- Voice fix, see [docs](https://x)\n- Update dialog\n\nSee `README`.';
    final t = plainNotes(md);
    expect(t.contains('#'), isFalse);
    expect(t.contains('**'), isFalse);
    expect(t.contains('`'), isFalse);
    expect(t, contains('• Voice fix, see docs'));
    expect(t.toLowerCase().contains('dietownik 1.0.6'), isFalse);
  });

  test('APK is chosen by CPU architecture', () {
    final assets = [
      {'name': 'a-arm64.apk', 'browser_download_url': 'u1'},
      {'name': 'a-armv7.apk', 'browser_download_url': 'u2'},
    ];
    expect(pickApkUrl(assets, ['arm64-v8a', 'armeabi-v7a']), 'u1');
    expect(pickApkUrl(assets, ['armeabi-v7a']), 'u2');
    expect(pickApkUrl(const [], ['arm64-v8a']), isNull);
  });

  UpdateService svc(_Fake f) => UpdateService(dio: Dio()..httpClientAdapter = f, repo: 'x/y');
  const abis = ['arm64-v8a'];

  test('newer release prompts once, then stays quiet (throttle)', () async {
    final f = _Fake(() => (200, _release('v9.9.9')));
    final s = svc(f);
    final t0 = DateTime(2026, 10, 12, 9);
    final u = await s.checkAutomatically(now: t0, currentVersion: '1.0.4', abis: abis);
    expect(u?.latest, '9.9.9');
    expect(u?.downloadUrl, 'https://dl/arm64.apk');
    expect(await s.checkAutomatically(now: t0.add(const Duration(hours: 1)), currentVersion: '1.0.4', abis: abis), isNull);
    expect(f.calls, 1); // the second launch did not even hit the network
    expect(await s.checkAutomatically(now: t0.add(const Duration(hours: 13)), currentVersion: '1.0.4', abis: abis), isNotNull);
  });

  test('same or older release never prompts', () async {
    final s = svc(_Fake(() => (200, _release('v1.0.4'))));
    expect(await s.checkAutomatically(currentVersion: '1.0.4', abis: abis), isNull);
  });

  test('prereleases and drafts are ignored', () async {
    final s = svc(_Fake(() => (200, _release('v9.9.9', pre: true))));
    expect(await s.checkAutomatically(currentVersion: '1.0.4', abis: abis), isNull);
  });

  test('snooze silences for 3 days, a later release version after skip prompts again', () async {
    final s = svc(_Fake(() => (200, _release('v9.9.9'))));
    final t0 = DateTime(2026, 10, 12, 9);
    await s.snooze(now: t0);
    expect(await s.checkAutomatically(now: t0.add(const Duration(days: 2)), currentVersion: '1.0.4', abis: abis), isNull);
    expect(await s.checkAutomatically(now: t0.add(const Duration(days: 4)), currentVersion: '1.0.4', abis: abis), isNotNull);

    SharedPreferences.setMockInitialValues({});
    await s.skipVersion('9.9.9');
    expect(await s.checkAutomatically(now: t0, currentVersion: '1.0.4', abis: abis), isNull);
    final newer = svc(_Fake(() => (200, _release('v10.0.0'))));
    // a newer release than the skipped one prompts again once the 12 h throttle has passed
    expect((await newer.checkAutomatically(now: t0.add(const Duration(hours: 13)), currentVersion: '1.0.4', abis: abis))?.latest, '10.0.0');
  });

  test('offline stays silent and does not start the 12 h clock', () async {
    var online = false;
    final f = _Fake(() => online ? (200, _release('v9.9.9')) : (0, ''));
    final s = svc(f);
    expect(await s.checkAutomatically(currentVersion: '1.0.4', abis: abis), isNull);
    online = true;
    expect(await s.checkAutomatically(currentVersion: '1.0.4', abis: abis), isNotNull);
  });

  test('404 (no releases yet) is silent; manual check reports unreachable', () async {
    final s = svc(_Fake(() => (404, '{"message":"Not Found"}')));
    expect(await s.checkAutomatically(currentVersion: '1.0.4', abis: abis), isNull);
    final (u, ok) = await s.checkNow(currentVersion: '1.0.4', abis: abis);
    expect(u, isNull);
    expect(ok, isFalse);
  });
}
