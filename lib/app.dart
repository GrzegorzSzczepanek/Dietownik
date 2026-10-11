import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/onboarding_screen.dart';
import 'features/shell.dart';
import 'providers.dart';

class DietownikApp extends ConsumerStatefulWidget {
  const DietownikApp({super.key});
  @override
  ConsumerState<DietownikApp> createState() => _DietownikAppState();
}

class _DietownikAppState extends ConsumerState<DietownikApp> {
  @override
  void initState() {
    super.initState();
    // Re-plan reminders on launch; a logged meal drops that slot's nudge.
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(reminderSchedulerProvider).sync());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(dataVersionProvider, (_, _) => ref.read(reminderSchedulerProvider).sync());
    return MaterialApp(
      title: 'Dietownik',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) {
        // Tokens are read through static getters; re-key the tree so every
        // screen picks the new palette when the system theme flips.
        final b = Theme.of(context).brightness;
        AppColors.setBrightness(b);
        return KeyedSubtree(key: ValueKey(b), child: child!);
      },
      home: ref.watch(onboardedProvider) ? const Shell() : const OnboardingScreen(),
    );
  }
}
