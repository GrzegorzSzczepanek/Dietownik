import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

const githubRepo = 'GrzegorzSzczepanek/Dietownik';

class AppUpdate {
  const AppUpdate({required this.current, required this.latest, required this.notes, required this.downloadUrl, required this.pageUrl});
  final String current, latest, notes, downloadUrl, pageUrl;
}

/// True when [latest] is strictly newer than [current]. Only major.minor.patch counts;
/// build numbers and a leading "v" are ignored, so "v1.0.5" > "1.0.4" and "1.0.4" == "v1.0.4".
bool isNewerVersion(String latest, String current) {
  List<int> parts(String v) => v
      .trim()
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split('+')
      .first
      .split('.')
      .map((p) => int.tryParse(p.replaceAll(RegExp(r'\D.*'), '')) ?? 0)
      .toList();
  final l = parts(latest), c = parts(current);
  for (var i = 0; i < (l.length > c.length ? l.length : c.length); i++) {
    final a = i < l.length ? l[i] : 0, b = i < c.length ? c[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}

/// Release notes arrive as Markdown; show a short plain-text version in the dialog.
String plainNotes(String md, {int maxLines = 5, int maxChars = 320}) {
  final lines = <String>[];
  for (var raw in md.split('\n')) {
    var l = raw
        .replaceAll(RegExp(r'^\s*#+\s*'), '')
        .replaceAll(RegExp(r'^\s*[-*]\s+'), '• ')
        .replaceAll('**', '')
        .replaceAll('`', '')
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1)!)
        .trim();
    if (l.isEmpty) continue;
    if (RegExp(r'^dietownik \d').hasMatch(l.toLowerCase())) continue; // the release title repeated in the body
    lines.add(l);
    if (lines.length >= maxLines) break;
  }
  final out = lines.join('\n');
  return out.length > maxChars ? '${out.substring(0, maxChars)}…' : out;
}

/// Picks the APK matching the phone's CPU: arm64 builds for 64-bit phones, armv7 for old 32-bit ones.
String? pickApkUrl(List<Map<String, dynamic>> assets, List<String> abis) {
  final apks = [
    for (final a in assets)
      if ('${a['name']}'.toLowerCase().endsWith('.apk')) a
  ];
  String? find(String needle) {
    for (final a in apks) {
      if ('${a['name']}'.toLowerCase().contains(needle)) return '${a['browser_download_url']}';
    }
    return null;
  }

  if (abis.contains('arm64-v8a')) return find('arm64') ?? find('universal');
  if (abis.contains('armeabi-v7a') || abis.contains('armeabi')) return find('armv7') ?? find('universal');
  if (abis.contains('x86_64')) return find('x86_64') ?? find('universal');
  return apks.isEmpty ? null : '${apks.first['browser_download_url']}';
}

/// Looks at the latest published GitHub release, and decides whether to bother the user.
class UpdateService {
  UpdateService({Dio? dio, this.repo = githubRepo})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 6),
              headers: {'Accept': 'application/vnd.github+json'},
            ));
  final Dio _dio;
  final String repo;

  static const _kLastCheck = 'update_last_check';
  static const _kSnoozeUntil = 'update_snooze_until';
  static const _kSkipVersion = 'update_skip_version';
  static const checkEvery = Duration(hours: 12);
  static const snoozeFor = Duration(days: 3);

  /// The newest published (non-draft, non-prerelease) release, or null when it could not be fetched.
  Future<Map<String, dynamic>?> _release() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('https://api.github.com/repos/$repo/releases/latest');
      final data = res.data;
      if (res.statusCode != 200 || data == null) return null;
      if (data['draft'] == true || data['prerelease'] == true) return null;
      return data;
    } catch (_) {
      return null; // offline, rate limit, no releases yet: stay silent
    }
  }

  Future<AppUpdate?> _toUpdate(Map<String, dynamic> data, {String? currentVersion, List<String>? abis}) async {
    try {
      final current = currentVersion ?? (await PackageInfo.fromPlatform()).version;
      final tag = '${data['tag_name'] ?? ''}';
      if (!isNewerVersion(tag, current)) return null;
      final phoneAbis = abis ?? await _abis();
      final page = '${data['html_url'] ?? 'https://github.com/$repo/releases'}';
      final assets = ((data['assets'] as List?) ?? const []).cast<Map<String, dynamic>>();
      return AppUpdate(
        current: current,
        latest: tag.replaceFirst(RegExp(r'^[vV]'), ''),
        notes: '${data['body'] ?? ''}'.trim(),
        downloadUrl: pickApkUrl(assets, phoneAbis) ?? page,
        pageUrl: page,
      );
    } catch (_) {
      return null;
    }
  }

  /// Manual check ("Sprawdź aktualizacje"): ignores throttle, snooze and skipped versions.
  /// Returns null when up to date or when the check failed; [reachable] tells which.
  Future<(AppUpdate?, bool reachable)> checkNow({String? currentVersion, List<String>? abis}) async {
    final data = await _release();
    if (data == null) return (null, false);
    return (await _toUpdate(data, currentVersion: currentVersion, abis: abis), true);
  }

  Future<List<String>> _abis() async {
    try {
      if (Platform.isAndroid) return (await DeviceInfoPlugin().androidInfo).supportedAbis;
    } catch (_) {}
    return const [];
  }

  /// The automatic check: honours the 12 h throttle, the snooze and "skip this version".
  /// Returns an update only when the user should actually be asked.
  Future<AppUpdate?> checkAutomatically({DateTime? now, String? currentVersion, List<String>? abis}) async {
    final t = now ?? DateTime.now();
    final p = await SharedPreferences.getInstance();
    final last = p.getInt(_kLastCheck);
    if (last != null && t.difference(DateTime.fromMillisecondsSinceEpoch(last)) < checkEvery) return null;
    final snooze = p.getInt(_kSnoozeUntil);
    if (snooze != null && t.millisecondsSinceEpoch < snooze) return null;
    final data = await _release();
    if (data == null) return null; // nothing reached: try again next launch, do not start the 12 h clock
    await p.setInt(_kLastCheck, t.millisecondsSinceEpoch);
    final u = await _toUpdate(data, currentVersion: currentVersion, abis: abis);
    if (u == null || p.getString(_kSkipVersion) == u.latest) return null;
    return u;
  }

  Future<void> snooze({DateTime? now}) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kSnoozeUntil, (now ?? DateTime.now()).add(snoozeFor).millisecondsSinceEpoch);
  }

  Future<void> skipVersion(String version) async =>
      (await SharedPreferences.getInstance()).setString(_kSkipVersion, version);
}

/// Asks whether to download. "Później" is quiet for 3 days; "Pomiń tę wersję" until the next release.
Future<void> showUpdateDialog(BuildContext context, AppUpdate u, UpdateService service) {
  final notes = plainNotes(u.notes);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Nowa wersja ${u.latest}', style: display(24, height: 1.15)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Masz ${u.current}. Pobrać nową wersję?', style: fig(16, color: AppColors.text3)),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(notes, style: fig(14, color: AppColors.text2, height: 20 / 14)),
          ],
          const SizedBox(height: 8),
          Text('Dane zostają na telefonie. Plik zainstalujesz jako aktualizację.', style: fig(13, color: AppColors.text2)),
          Transform.translate(
            offset: const Offset(-12, 0),
            child: TextButton(
              onPressed: () {
                service.skipVersion(u.latest);
                Navigator.pop(ctx);
              },
              child: Text('Pomiń tę wersję', style: fig(14, weight: 600, color: AppColors.text2)),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () {
            service.snooze();
            Navigator.pop(ctx);
          },
          child: const Text('Później'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(110, 48)),
          onPressed: () {
            Navigator.pop(ctx);
            launchUrl(Uri.parse(u.downloadUrl), mode: LaunchMode.externalApplication);
          },
          child: const Text('Pobierz'),
        ),
      ],
    ),
  );
}
