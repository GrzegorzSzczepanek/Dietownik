import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'core/app_update.dart';
import 'features/onboarding_screen.dart';
import 'features/oko_screen.dart';
import 'features/scan_screen.dart';
import 'features/voice_sheet.dart';
import 'features/shell.dart';
import 'providers.dart';
import 'widget_sync.dart';

final navigatorKey = GlobalKey<NavigatorState>();

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(reminderSchedulerProvider).sync();
      _syncWidget();
      _checkForUpdate();
    });
    // Buttons on the home-screen widget open the matching screen.
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_openFromWidget);
    HomeWidget.widgetClicked.listen(_openFromWidget);
  }

  /// Ask about a new release only when one exists and the user has not postponed it.
  Future<void> _checkForUpdate() async {
    await Future<void>.delayed(const Duration(seconds: 4)); // never compete with startup
    if (!mounted || !ref.read(onboardedProvider)) return;
    final service = UpdateService();
    final u = await service.checkAutomatically();
    final ctx = navigatorKey.currentContext;
    if (u != null && ctx != null && ctx.mounted) showUpdateDialog(ctx, u, service);
  }

  void _syncWidget() => syncHomeWidget(ref.read(dbProvider), ref.read(goalsProvider));

  void _openFromWidget(Uri? uri) {
    final ctx = navigatorKey.currentContext;
    if (uri == null || ctx == null) return;
    switch (uri.host) {
      case 'mic':
        showVoiceSheet(ctx);
      case 'scan':
        Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ScanScreen()));
      case 'oko':
        Navigator.push(ctx, MaterialPageRoute(builder: (_) => const OkoScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(dataVersionProvider, (_, _) {
      ref.read(reminderSchedulerProvider).sync();
      _syncWidget();
    });
    ref.listen(goalsProvider, (_, _) => _syncWidget());
    return MaterialApp(
      title: 'Dietownik',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
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
