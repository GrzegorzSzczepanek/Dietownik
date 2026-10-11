import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai/ai_settings.dart';
import 'ai/usage.dart';
import 'ai/diet_ai.dart';
import 'ai/edge_runtime.dart';
import 'ai/embeddings.dart';
import 'ai/llm_api.dart';
import 'ai/local_models.dart';
import 'ai/local_runtime.dart';
import 'data/db.dart';
import 'domain/fallback_parser.dart';
import 'domain/meal_resolver.dart';
import 'domain/models.dart';
import 'notifications/reminders.dart';
import 'services/off_client.dart';

final dbProvider = Provider<AppDb>((ref) => throw UnimplementedError('override in main'));
final settingsStoreProvider = Provider<AiSettingsStore>((ref) => AiSettingsStore());
final initialAiSettingsProvider =
    Provider<AiSettings>((ref) => throw UnimplementedError('override in main'));
final initialGoalsProvider = Provider<Goals>((ref) => const Goals());

/// Whether the on-device engine initialised (set in main()).
class EngineReady extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final engineReadyProvider = NotifierProvider<EngineReady, bool>(EngineReady.new);
final offProvider = Provider<OffClient>((ref) => OffClient());

final localRuntimeProvider = Provider<LocalRuntime>((ref) {
  final ready = ref.watch(engineReadyProvider);
  if (!ready) return const UnavailableLocalRuntime();
  return EdgeAiRuntime(
    engineReady: true,
    activate: ref.read(modelDownloadsProvider.notifier).activateInEngine,
  );
});

/// Bumped after every write so the read providers below refetch.
class DataVersion extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final dataVersionProvider = NotifierProvider<DataVersion, int>(DataVersion.new);

class AiSettingsController extends Notifier<AiSettings> {
  @override
  AiSettings build() => ref.watch(initialAiSettingsProvider);

  AiSettingsStore get _store => ref.read(settingsStoreProvider);

  Future<void> _update(AiSettings s) async {
    state = s;
    await _store.save(s);
  }

  Future<void> setEngine(AiTask t, AiEngine e) =>
      _update(state.copyWith(engines: {...state.engines, t: e}));

  Future<void> setApi(ApiConfig c) => _update(state.copyWith(api: c));
  Future<void> setPrivacy(PrivacySettings p) => _update(state.copyWith(privacy: p));
  Future<String?> readKey() => _store.readKey();
  Future<void> writeKey(String? k) => _store.writeKey(k);

  Future<void> addTokens(int n, [String cat = 'zapisy']) async {
    await _store.addTokens(n);
    await AiUsage.add(cat, n, state.api.preset.price);
    state = state.copyWith(monthlyTokens: state.monthlyTokens + n);
  }

  Future<LlmApi?> llm() async {
    final cfg = state.api;
    if (cfg.baseUrl.isEmpty || cfg.model.isEmpty) return null;
    final key = await readKey();
    if (cfg.preset.needsKey && (key == null || key.isEmpty)) return null;
    return buildLlmApi(cfg, key);
  }

  Future<DietAi> dietAi() async => DietAi(
        settings: state,
        llm: await llm(),
        local: ref.read(localRuntimeProvider),
        onTokens: addTokens,
        braveKey: await const FlutterSecureStorage().read(key: 'brave_key').catchError((_) => null),
      );

  Future<Embedder?> embedder() async {
    final cfg = state.api;
    if (state.engineFor(AiTask.embeddings) != AiEngine.api ||
        cfg.format != ApiFormat.openai ||
        cfg.embeddingModel.isEmpty ||
        cfg.baseUrl.isEmpty) {
      return null;
    }
    final key = await readKey();
    if (cfg.preset.needsKey && (key == null || key.isEmpty)) return null;
    return OpenAiEmbedder(cfg, key);
  }
}

final aiSettingsProvider =
    NotifierProvider<AiSettingsController, AiSettings>(AiSettingsController.new);

// ---- goals

class GoalsNotifier extends Notifier<Goals> {
  @override
  Goals build() => ref.watch(initialGoalsProvider);

  static Future<Goals> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('goals');
    if (raw == null) return const Goals();
    final m = jsonDecode(raw) as Map;
    return Goals(
        kcal: (m['kcal'] as num).toDouble(),
        p: (m['p'] as num).toDouble(),
        c: (m['c'] as num).toDouble(),
        f: (m['f'] as num).toDouble());
  }

  Future<void> set(Goals g) async {
    state = g;
    final p = await SharedPreferences.getInstance();
    await p.setString('goals', jsonEncode({'kcal': g.kcal, 'p': g.p, 'c': g.c, 'f': g.f}));
  }
}

final goalsProvider = NotifierProvider<GoalsNotifier, Goals>(GoalsNotifier.new);

// ---- data

class SelectedDay extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();
  void shift(int days) => state = state.add(Duration(days: days));
  void today() => state = DateTime.now();
}

final selectedDayProvider = NotifierProvider<SelectedDay, DateTime>(SelectedDay.new);

final dayEntriesProvider = FutureProvider<List<Entry>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.read(dbProvider).entriesFor(dayKey(ref.watch(selectedDayProvider)));
});

final frequentProvider = FutureProvider<List<Entry>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.read(dbProvider).frequentEntries();
});

final recipesProvider = FutureProvider<List<Recipe>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.read(dbProvider).recipes();
});

/// Days with a log in the last 7, no punishment for gaps.
final weekLoggedProvider = FutureProvider<int>((ref) async {
  ref.watch(dataVersionProvider);
  final days = await ref.read(dbProvider).loggedDays(limit: 60);
  final now = DateTime.now();
  return [for (var i = 0; i < 7; i++) dayKey(now.subtract(Duration(days: i)))]
      .where(days.contains)
      .length;
});

final weekKcalProvider = FutureProvider<Map<String, double>>((ref) async {
  ref.watch(dataVersionProvider);
  final now = DateTime.now();
  return ref.read(dbProvider).kcalByDay(dayKey(now.subtract(const Duration(days: 6))), dayKey(now));
});

// ---- logging pipeline

class LogResult {
  LogResult(this.entries, {this.usedAi = true, this.parseError});
  final List<Entry> entries;
  final bool usedAi;

  /// Set when an AI engine was configured but the call failed, so the UI can say why.
  final String? parseError;
}

class FoodLogger {
  FoodLogger(this.ref);
  final Ref ref;

  /// Free text ("2 jajka i kanapka z serem") -> saved entries. Never throws for
  /// AI failures: falls back to the plain parser so logging always works.
  Future<LogResult> logText(String text, {DateTime? when, int? meal}) async {
    final db = ref.read(dbProvider);
    final t0 = when ?? DateTime.now();
    // "śniadanie jak zawsze": a saved set (recipe) named in the sentence wins.
    final spoken = MealResolver.tokens(text).map(MealResolver.stem).toSet();
    for (final r in await db.recipes()) {
      final want = MealResolver.tokens(r.title).map(MealResolver.stem).toSet();
      if (want.isNotEmpty && r.perServing.kcal > 0 && want.every(spoken.contains)) {
        final e = Entry(day: dayKey(t0), meal: meal ?? mealForTime(t0), name: r.title, grams: 0, macros: r.perServing);
        final id = await db.addEntry(e);
        ref.read(dataVersionProvider.notifier).bump();
        return LogResult([Entry(id: id, day: e.day, meal: e.meal, name: e.name, grams: 0, macros: e.macros)]);
      }
    }
    final ai = await ref.read(aiSettingsProvider.notifier).dietAi();
    var usedAi = false;
    List<ParsedItem> items = const [];
    String? parseError;
    if (ai.canRun(AiTask.foodParsing)) {
      try {
        items = await ai.parseMeal(text);
        usedAi = items.isNotEmpty;
        if (items.isEmpty) parseError = 'model nie zwrócił pozycji';
      } catch (e) {
        parseError = '$e';
      }
    }
    if (items.isEmpty) items = fallbackParseMeal(text);
    final resolver = MealResolver(db: db, off: ref.read(offProvider), ai: ai);
    final t = when ?? DateTime.now();
    final saved = <Entry>[];
    for (final it in items) {
      final r = await resolver.resolve(it);
      final e = Entry(
        day: dayKey(t),
        meal: meal ?? mealForTime(t),
        name: r.name,
        grams: r.grams.roundToDouble(),
        macros: r.macros,
        estimated: r.estimated || r.unknown,
        pieceG: r.pieceG,
        pieceLabel: r.pieceLabel,
        source: r.source,
      );
      final id = await db.addEntry(e);
      saved.add(Entry(
          id: id,
          day: e.day,
          meal: e.meal,
          name: e.name,
          grams: e.grams,
          macros: e.macros,
          estimated: e.estimated,
          pieceG: e.pieceG,
          pieceLabel: e.pieceLabel,
          source: e.source));
    }
    ref.read(dataVersionProvider.notifier).bump();
    return LogResult(saved, usedAi: usedAi, parseError: parseError);
  }

  Future<int> addFood(Food food, double grams, {DateTime? when, int? meal}) async {
    final db = ref.read(dbProvider);
    final t = when ?? DateTime.now();
    final id = food.id ?? await db.saveFood(food);
    await db.touchFood(id);
    final eid = await db.addEntry(Entry(
      day: dayKey(t),
      meal: meal ?? mealForTime(t),
      name: food.title,
      grams: grams,
      macros: food.per(grams),
      estimated: food.estimated,
      pieceG: food.pieceG,
      pieceLabel: food.servingLabel,
      source: food.sourceNote,
    ));
    ref.read(dataVersionProvider.notifier).bump();
    return eid;
  }

  Future<void> repeat(Entry e, {DateTime? when}) async {
    final t = when ?? DateTime.now();
    await ref.read(dbProvider).addEntry(Entry(
        day: dayKey(t),
        meal: mealForTime(t),
        name: e.name,
        grams: e.grams,
        macros: e.macros,
        estimated: e.estimated,
        pieceG: e.pieceG,
        pieceLabel: e.pieceLabel,
        source: e.source));
    ref.read(dataVersionProvider.notifier).bump();
  }

  Future<int> copyDay(DateTime from, DateTime to) async {
    final db = ref.read(dbProvider);
    final list = await db.entriesFor(dayKey(from));
    for (final e in list) {
      await db.addEntry(Entry(
          day: dayKey(to),
          meal: e.meal,
          name: e.name,
          grams: e.grams,
          macros: e.macros,
          estimated: e.estimated,
          pieceG: e.pieceG,
          pieceLabel: e.pieceLabel,
          source: e.source));
    }
    ref.read(dataVersionProvider.notifier).bump();
    return list.length;
  }
}

final foodLoggerProvider = Provider<FoodLogger>((ref) => FoodLogger(ref));

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) => ReminderScheduler(ref.read(dbProvider)));

class RemindersNotifier extends AsyncNotifier<ReminderPrefs> {
  @override
  Future<ReminderPrefs> build() => ReminderPrefs.load();

  Future<bool> set(ReminderPrefs p) async {
    final sched = ref.read(reminderSchedulerProvider);
    var prefs = p;
    if (p.enabled && !(state.value?.enabled ?? false)) {
      if (!await sched.requestPermission()) prefs = p.copyWith(enabled: false);
    }
    await prefs.save();
    state = AsyncData(prefs);
    await sched.sync();
    return prefs.enabled == p.enabled;
  }
}

final remindersProvider = AsyncNotifierProvider<RemindersNotifier, ReminderPrefs>(RemindersNotifier.new);

// ---- pantry, shopping list, water, weekly mode

class StringListNotifier extends Notifier<List<String>> {
  StringListNotifier(this.key);
  final String key;
  @override
  List<String> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = p.getStringList(key) ?? const [];
  }

  Future<void> _save(List<String> v) async {
    state = v;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(key, v);
  }

  Future<void> add(Iterable<String> items) async {
    final v = [...state];
    for (final i in items.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      if (!v.any((x) => x.toLowerCase() == i.toLowerCase())) v.add(i);
    }
    await _save(v);
  }

  Future<void> remove(String item) => _save(state.where((e) => e != item).toList());
  Future<void> replace(List<String> v) => _save(v);
}

final pantryProvider = NotifierProvider<StringListNotifier, List<String>>(() => StringListNotifier('pantry'));

/// Shopping items are stored as "0|text" (open) or "1|text" (done).
final shoppingProvider = NotifierProvider<StringListNotifier, List<String>>(() => StringListNotifier('shopping'));

final braveKeyProvider = FutureProvider<String?>((ref) => const FlutterSecureStorage().read(key: 'brave_key'));

final waterProvider = FutureProvider<int>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.read(dbProvider).waterFor(dayKey(ref.watch(selectedDayProvider)));
});

class WeeklyModeNotifier extends Notifier<bool> {
  @override
  bool build() {
    SharedPreferences.getInstance().then((p) => state = p.getBool('weekly_mode') ?? false);
    return false;
  }

  Future<void> set(bool v) async {
    state = v;
    (await SharedPreferences.getInstance()).setBool('weekly_mode', v);
  }
}

final weeklyModeProvider = NotifierProvider<WeeklyModeNotifier, bool>(WeeklyModeNotifier.new);

DateTime weekStart(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

/// kcal eaten Monday..today (the selected day's week).
final weekEatenProvider = FutureProvider<double>((ref) async {
  ref.watch(dataVersionProvider);
  final day = ref.watch(selectedDayProvider);
  final m = await ref.read(dbProvider).kcalByDay(dayKey(weekStart(day)), dayKey(day));
  return m.values.fold<double>(0.0, (a, b) => a + b);
});

final weekMacrosProvider = FutureProvider<Map<String, Macros>>((ref) async {
  ref.watch(dataVersionProvider);
  final now = DateTime.now();
  return ref.read(dbProvider).macrosByDay(dayKey(now.subtract(const Duration(days: 6))), dayKey(now));
});

final skipDayProvider = FutureProvider<bool>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.read(dbProvider).isSkipDay(dayKey(ref.watch(selectedDayProvider)));
});

final skipDaysProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.read(dbProvider).skipDays();
});

/// Whether the first-run flow was completed (set from prefs in main()).
final initialOnboardedProvider = Provider<bool>((ref) => true);

class OnboardedNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(initialOnboardedProvider);
  Future<void> done() async {
    state = true;
    (await SharedPreferences.getInstance()).setBool('onboarded', true);
  }
}

final onboardedProvider = NotifierProvider<OnboardedNotifier, bool>(OnboardedNotifier.new);

/// Recipe links saved while offline, imported later from Przepisy.
final pendingLinksProvider = NotifierProvider<StringListNotifier, List<String>>(() => StringListNotifier('pending_links'));
