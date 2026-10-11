import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'common.dart';
import 'widgets.dart';

/// Statystyki per design/Statystyki: average as the hero number, bars per day with a dashed goal line.
class WeekScreen extends ConsumerWidget {
  const WeekScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(weekMacrosProvider).value ?? const <String, Macros>{};
    final goals = ref.watch(goalsProvider);
    final now = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) now.subtract(Duration(days: i))];
    final logged = [for (final d in days) if (data[dayKey(d)] != null) data[dayKey(d)]!];
    final avg = logged.isEmpty ? Macros.zero : logged.fold(Macros.zero, (a, b) => a + b) * (1 / logged.length);
    final maxKcal = [goals.kcal * 1.15, ...data.values.map((e) => e.kcal)].reduce((a, b) => a > b ? a : b);

    Widget macroRow(String label, double v, double goal, Color c, {required bool last}) => Container(
          constraints: const BoxConstraints(minHeight: 52),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line), bottom: last ? BorderSide(color: AppColors.line) : BorderSide.none)),
          child: Row(children: [
            SizedBox(width: 72, child: Text(label, style: fig(16, weight: 600))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 8,
                  color: AppColors.line,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(widthFactor: goal == 0 ? 0 : (v / goal).clamp(0.0, 1.0), child: Container(color: c)),
                ),
              ),
            ),
            SizedBox(width: 96, child: Text('${n0(v)} / ${n0(goal)} g', textAlign: TextAlign.right, style: fig(15))),
          ]),
        );

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListView(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 32), children: [
        HeroZone(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const HeroBackHeader('Statystyki, ostatnie 7 dni', size: 18),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(n0(avg.kcal), style: display(72)),
              const SizedBox(width: 10),
              Text('kcal dziennie', style: fig(17, weight: 600)),
            ]),
            const SizedBox(height: 6),
            Text('Średnia z dni, w których coś zapisałeś (${logged.length} z 7).', style: fig(15, color: AppColors.text3, height: 22 / 15)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Kalorie po dniach', style: fig(18, weight: 700)),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: LayoutBuilder(builder: (context, c) {
                final plotH = c.maxHeight - 28;
                final goalY = plotH * (1 - goals.kcal / maxKcal);
                return Stack(children: [
                  Positioned(left: 0, right: 0, top: goalY, child: CustomPaint(size: const Size(double.infinity, 2), painter: _DashPainter(AppColors.track))),
                  Positioned(right: 0, top: goalY + 6, child: Text('cel ${n0(goals.kcal)}', style: fig(13, weight: 600, color: AppColors.text3))),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: plotH,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      for (final d in days)
                        Expanded(
                          child: Builder(builder: (_) {
                            final k = data[dayKey(d)]?.kcal;
                            return Padding(
                              padding: EdgeInsets.symmetric(horizontal: k == null ? 8 : 4),
                              child: Container(
                                height: k == null ? 6 : (plotH * (k / maxKcal)).clamp(6.0, plotH),
                                decoration: BoxDecoration(
                                  color: k == null ? AppColors.line : AppColors.accent,
                                  borderRadius: k == null ? BorderRadius.circular(3) : const BorderRadius.vertical(top: Radius.circular(8), bottom: Radius.circular(4)),
                                ),
                              ),
                            );
                          }),
                        ),
                    ]),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 24,
                    child: Row(children: [
                      for (final d in days)
                        Expanded(
                          child: Center(
                            child: Text(dayKey(d) == dayKey(now) ? 'dziś' : DateFormat('E', 'pl').format(d),
                                style: fig(13, weight: dayKey(d) == dayKey(now) ? 700 : 400, color: dayKey(d) == dayKey(now) ? AppColors.accentDeep : AppColors.text2)),
                          ),
                        ),
                    ]),
                  ),
                ]);
              }),
            ),
            const SizedBox(height: 28),
            Text('Makro w dni z wpisem', style: fig(18, weight: 700)),
            const SizedBox(height: 8),
            macroRow('Białko', avg.p, goals.p, AppColors.protein, last: false),
            macroRow('Węgle', avg.c, goals.c, AppColors.carbs, last: false),
            macroRow('Tłuszcz', avg.f, goals.f, AppColors.fat, last: true),
            const SizedBox(height: 24),
            Text('Masz ${logged.length} z 7 dni. Każdy wpis się liczy, a puste dni nie psują średniej.', style: fig(16, color: AppColors.text3, height: 24 / 16)),
          ]),
        ),
      ]),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (double x = 0; x < size.width; x += 10) {
      canvas.drawLine(Offset(x, 0), Offset(x + 6, 0), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter o) => o.color != color;
}
