import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'common.dart';
import 'widgets.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Ostatnie 7 dni')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Eyebrow('KALORIE DZIENNIE'),
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              child: BarChart(BarChartData(
                maxY: [goals.kcal * 1.3, ...data.values.map((e) => e.kcal)].reduce((a, b) => a > b ? a : b),
                gridData: const FlGridData(drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                  bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, _) => Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(DateFormat('E', 'pl').format(days[v.toInt()]), style: const TextStyle(fontSize: 11))))),
                ),
                extraLinesData: ExtraLinesData(horizontalLines: [HorizontalLine(y: goals.kcal, color: AppColors.muted, dashArray: [6, 4], strokeWidth: 1.5)]),
                barGroups: [
                  for (var i = 0; i < 7; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: data[dayKey(days[i])]?.kcal ?? 0,
                        width: 22,
                        borderRadius: BorderRadius.circular(6),
                        color: (data[dayKey(days[i])]?.kcal ?? 0) > goals.kcal * 1.1 ? AppColors.amber : AppColors.green,
                      )
                    ]),
                ],
              )),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Eyebrow('ŚREDNIA Z DNI Z WPISAMI'),
            const SizedBox(height: 8),
            Text('${n0(avg.kcal)} kcal', style: mono(size: 26)),
            const SizedBox(height: 4),
            Text('${macroText(avg)}  ·  cel ${n0(goals.kcal)} kcal', style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 8),
            Text('Dni z wpisem: ${logged.length} z 7', style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }
}
