import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/db.dart';
import '../domain/models.dart';

/// Meal reminder settings: three slots (breakfast/lunch/dinner), minutes since midnight.
class ReminderPrefs {
  const ReminderPrefs({this.enabled = false, this.slots = const [9 * 60, 13 * 60 + 30, 19 * 60]});
  final bool enabled;
  final List<int> slots;

  static const _kOn = 'rem_on';
  static const _kSlots = 'rem_slots';

  static Future<ReminderPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getStringList(_kSlots)?.map(int.parse).toList();
    return ReminderPrefs(
        enabled: p.getBool(_kOn) ?? false,
        slots: (s != null && s.length == 3) ? s : const [9 * 60, 13 * 60 + 30, 19 * 60]);
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOn, enabled);
    await p.setStringList(_kSlots, slots.map((e) => '$e').toList());
  }

  ReminderPrefs copyWith({bool? enabled, List<int>? slots}) =>
      ReminderPrefs(enabled: enabled ?? this.enabled, slots: slots ?? this.slots);
}

const _messages = [
  ['Śniadanie?', 'Powiedz mikrofonowi, co zjadłeś. 5 sekund i po sprawie.'],
  ['Obiad?', 'Co dziś na talerzu? Dotknij i powiedz.'],
  ['Kolacja?', 'Zamknij dzień jednym zdaniem do mikrofonu.'],
];

/// Schedules one-off notifications for the next week and skips slots whose meal
/// is already logged today. Re-run on app start and after each log, so the app
/// only nags when there is something missing, and never about a gap.
class ReminderScheduler {
  ReminderScheduler(this.db);
  final AppDb db;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool? _ready;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'meals',
      'Przypomnienia o posiłkach',
      channelDescription: 'Delikatne przypomnienia, żeby zapisać posiłek',
      importance: Importance.defaultImportance,
      icon: 'ic_notification',
    ),
  );

  Future<bool> _init() async {
    if (_ready != null) return _ready!;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
      await _plugin.initialize(
          settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      return _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
      return _ready = false;
    }
  }

  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await a?.requestNotificationsPermission() ?? false;
  }

  Future<void> sync() async {
    try {
      if (!await _init()) return;
      await _plugin.cancelAll();
      final prefs = await ReminderPrefs.load();
      if (!prefs.enabled) return;
      final now = DateTime.now();
      final today = await db.entriesFor(dayKey(now));
      final logged = {for (final e in today) e.meal};
      for (var d = 0; d < 7; d++) {
        for (var s = 0; s < 3; s++) {
          final day = now.add(Duration(days: d));
          final when = DateTime(day.year, day.month, day.day, prefs.slots[s] ~/ 60, prefs.slots[s] % 60);
          if (!when.isAfter(now)) continue;
          if (d == 0 && logged.contains(s)) continue;
          await _plugin.zonedSchedule(
            id: 1000 + d * 10 + s,
            title: _messages[s][0],
            body: _messages[s][1],
            scheduledDate: tz.TZDateTime.from(when, tz.local),
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      }
    } catch (e) {
      debugPrint('Reminder sync failed: $e');
    }
  }
}
