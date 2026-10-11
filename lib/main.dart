import 'dart:async';

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
import 'services/web_search.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting("pl");
  await SearchBackend.load();
  final db = await AppDb.open();
  await seedFoodsOnce(db);
  final settings = await AiSettingsStore().load();
  final goals = await GoalsNotifier.load();
  final onboarded = (await SharedPreferences.getInstance()).getBool('onboarded') ?? false;
  // The big product pack loads in the background so first launch stays fast.
  unawaited(loadOffPackOnce(db));
  final container = ProviderContainer(
    overrides: [
      dbProvider.overrideWithValue(db),
      initialAiSettingsProvider.overrideWithValue(settings),
      initialGoalsProvider.overrideWithValue(goals),
      initialOnboardedProvider.overrideWithValue(onboarded),
    ],
  );
  // On-device model engine starts in the background; the UI does not wait for it.
  unawaited(initEdgeAi().then((ok) => container.read(engineReadyProvider.notifier).set(ok)));
  runApp(UncontrolledProviderScope(container: container, child: const DietownikApp()));
}

/// Inserts built-in foods; bumping [version] adds newly shipped items on update.
Future<void> seedFoodsOnce(AppDb db, {int version = 2}) async {
  final prefs = await SharedPreferences.getInstance();
  if ((prefs.getInt('seed_version') ?? 0) >= version) return;
  await db.seedFoodsIfMissing([...seedFoods, ...genericFoods]);
  await prefs.setInt('seed_version', version);
}
