import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'advice_screen.dart';
import 'recipes_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';
import 'voice_sheet.dart';

/// Bottom navigation from design/Main.dc.html: 84 px bar, four tabs and a 70 px
/// microphone button with a white 6 px ring that rises 28 px above the bar.
/// The scanner is no longer a floating button (it lives in Dziś, Przepisy and Szukaj).
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;

  static const _navHeight = 84.0;
  static const _micSize = 70.0;
  static const _micRise = 28.0;

  // Every tab draws its own hero or header under the status bar.
  static const _pages = <Widget>[
    TodayScreen(),
    RecipesScreen(),
    AdviceScreen(),
    SettingsScreen(),
  ];

  Widget _tab(int i, IconData icon, String label) {
    final sel = _i == i;
    final color = sel ? AppColors.accent : AppColors.text2;
    return Expanded(
      child: Semantics(
        button: true,
        selected: sel,
        label: label,
        child: InkWell(
          onTap: () => setState(() => _i = i),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 24, color: color, weight: sel ? 700 : 400),
                const SizedBox(height: 3),
                Text(label, style: fig(12, weight: sel ? 700 : 600, color: color)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).padding.bottom;
    final navTotal = _navHeight + inset;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        Column(children: [
          Expanded(child: IndexedStack(index: _i, children: _pages)),
          Container(
            height: navTotal,
            padding: EdgeInsets.fromLTRB(8, 0, 8, inset),
            decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.line))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _tab(0, Icons.calendar_today_outlined, 'Dziś'),
              _tab(1, Icons.menu_book_outlined, 'Przepisy'),
              const SizedBox(width: 92),
              _tab(2, Icons.chat_bubble_outline, 'Czat'),
              _tab(3, Icons.tune, 'Ja'),
            ]),
          ),
        ]),
        Positioned(
          left: 0,
          right: 0,
          bottom: navTotal - (_micSize - _micRise),
          child: Center(
            child: Semantics(
              button: true,
              label: 'Powiedz, co zjadłeś',
              child: GestureDetector(
                onTap: () => showVoiceSheet(context),
                child: Container(
                  width: _micSize,
                  height: _micSize,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.bg, width: 6),
                  ),
                  child: Icon(Icons.mic, size: 28, color: AppColors.onAccent),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
