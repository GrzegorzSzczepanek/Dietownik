import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai/ai_settings.dart';
import 'ai/edge_runtime.dart';
import 'app.dart';
import 'data/db.dart';
import 'data/food_seed.dart';
import 'data/generic_foods.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/off_pack.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting("pl");
  final db = await AppDb.open();
  await seedFoodsOnce(db);
  await loadOffPackOnce(db);
  final settings = await AiSettingsStore().load();
  final engineReady = await initEdgeAi();
  final goals = await GoalsNotifier.load();
  runApp(ProviderScope(
    overrides: [
      dbProvider.overrideWithValue(db),
      initialAiSettingsProvider.overrideWithValue(settings),
      engineReadyProvider.overrideWithValue(engineReady),
      initialGoalsProvider.overrideWithValue(goals),
    ],
    child: const DietownikApp(),
  ));
}

/// Inserts built-in foods; bumping [version] adds newly shipped items on update.
Future<void> seedFoodsOnce(AppDb db, {int version = 2}) async {
  final prefs = await SharedPreferences.getInstance();
  if ((prefs.getInt('seed_version') ?? 0) >= version) return;
  for (final f in [...seedFoods, ...genericFoods]) {
    await db.saveFood(f);
  }
  await prefs.setInt('seed_version', version);
}
