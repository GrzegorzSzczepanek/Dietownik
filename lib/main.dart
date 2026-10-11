import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai/ai_settings.dart';
import 'ai/edge_runtime.dart';
import 'app.dart';
import 'data/db.dart';
import 'data/food_seed.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting("pl");
  final db = await AppDb.open();
  if (await db.foodCount() == 0) await db.seedFoods(seedFoods);
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
