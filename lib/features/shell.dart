import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'advice_screen.dart';
import 'recipes_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';
import 'voice_sheet.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;

  static const _pages = <Widget>[TodayScreen(), RecipesScreen(), AdviceScreen(), SettingsScreen()];

  Widget _tab(int i, IconData icon, String label) {
    final sel = _i == i;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _i = i),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: sel ? AppColors.green : AppColors.muted),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: sel ? AppColors.green : AppColors.muted)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(children: [
          SafeArea(bottom: false, child: IndexedStack(index: _i, children: _pages)),
          // Always-available scanner: one tap from any tab.
          Positioned(
            left: 16,
            bottom: 14,
            child: FloatingActionButton.small(
              heroTag: 'scan',
              backgroundColor: Colors.white,
              foregroundColor: AppColors.green,
              elevation: 3,
              tooltip: 'Skaner',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen())),
              child: const Icon(Icons.qr_code_scanner),
            ),
          ),
        ]),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        floatingActionButton: SizedBox(
          width: 76,
          height: 76,
          child: FloatingActionButton(
            heroTag: 'mic',
            elevation: 3,
            backgroundColor: AppColors.green,
            foregroundColor: Colors.white,
            shape: const CircleBorder(),
            onPressed: () => showVoiceSheet(context),
            child: const Icon(Icons.mic, size: 38),
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          color: Colors.white,
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          padding: EdgeInsets.zero,
          child: Row(children: [
            _tab(0, Icons.today_outlined, 'Dziś'),
            _tab(1, Icons.menu_book_outlined, 'Przepisy'),
            const SizedBox(width: 76),
            _tab(2, Icons.lightbulb_outline, 'Porady'),
            _tab(3, Icons.tune, 'Ja'),
          ]),
        ),
      );
}
