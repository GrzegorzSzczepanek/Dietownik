import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'widgets.dart';

final weightsProvider = FutureProvider<List<MapEntry<String, double>>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.read(dbProvider).weights();
});

Future<void> addWeightDialog(BuildContext context, WidgetRef ref, {double? last}) async {
  final ctrl = TextEditingController(text: last == null ? '' : last.toStringAsFixed(1));
  final v = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Dzisiejsza waga'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(suffixText: 'kg'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
          onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.'))),
          child: const Text('Zapisz'),
        ),
      ],
    ),
  );
  if (v == null || v < 20 || v > 400) return;
  await ref.read(dbProvider).setWeight(dayKey(DateTime.now()), v);
  ref.read(dataVersionProvider.notifier).bump();
}

class WeightScreen extends ConsumerWidget {
  const WeightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(weightsProvider).value ?? const <MapEntry<String, double>>[];
    final pts = all.length > 60 ? all.sublist(all.length - 60) : all;
    final last = all.isEmpty ? null : all.last.value;
    String trend() {
      if (all.length < 2) return 'Dodaj kilka pomiarów, a pokażę trend.';
      final recent = all.where((e) => DateTime.parse(e.key).isAfter(DateTime.now().subtract(const Duration(days: 14)))).toList();
      if (recent.length < 2) return 'Ostatni pomiar jest sprzed ponad 2 tygodni.';
      final d = recent.last.value - recent.first.value;
      return '${d >= 0 ? '+' : ''}${d.toStringAsFixed(1)} kg w ostatnich 14 dniach';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Waga')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => addWeightDialog(context, ref, last: last),
        icon: const Icon(Icons.add),
        label: const Text('Zważ się'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(last == null ? '—' : '${last.toStringAsFixed(1)} kg', style: figure(size: 34)),
            const SizedBox(height: 4),
            Text(trend(), style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: pts.length < 2
                  ? Center(child: Text('Wykres pojawi się po dwóch pomiarach.', style: TextStyle(color: AppColors.muted)))
                  : _Chart(pts),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        for (final e in all.reversed.take(30))
          ListTile(
            title: Text('${e.value.toStringAsFixed(1)} kg', style: figure(size: 16)),
            subtitle: Text(e.key),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref.read(dbProvider).deleteWeight(e.key);
                ref.read(dataVersionProvider.notifier).bump();
              },
            ),
          ),
      ]),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart(this.pts);
  final List<MapEntry<String, double>> pts;
  @override
  Widget build(BuildContext context) {
    final t0 = DateTime.parse(pts.first.key);
    final spots = [for (final e in pts) FlSpot(DateTime.parse(e.key).difference(t0).inDays.toDouble(), e.value)];
    final ys = pts.map((e) => e.value);
    final lo = ys.reduce((a, b) => a < b ? a : b), hi = ys.reduce((a, b) => a > b ? a : b);
    return LineChart(LineChartData(
      minY: (lo - 1).floorToDouble(),
      maxY: (hi + 1).ceilToDouble(),
      gridData: const FlGridData(drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: const FlTitlesData(
        topTitles: AxisTitles(),
        rightTitles: AxisTitles(),
        bottomTitles: AxisTitles(),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
      ),
      lineBarsData: [
        LineChartBarData(spots: spots, isCurved: true, color: AppColors.green, barWidth: 3, dotData: FlDotData(show: pts.length < 25)),
      ],
    ));
  }
}
