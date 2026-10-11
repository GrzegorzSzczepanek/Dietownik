import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import '../ai/local_models.dart';
import 'advice_screen.dart';
import 'api_provider_screen.dart';
import 'common.dart';
import 'food_search_screen.dart';
import 'scan_screen.dart';
import 'week_screen.dart';
import 'widgets.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(selectedDayProvider);
    final isToday = dayKey(day) == dayKey(DateTime.now());
    final entries = ref.watch(dayEntriesProvider).value ?? const <Entry>[];
    final goals = ref.watch(goalsProvider);
    final total = entries.fold(Macros.zero, (a, e) => a + e.macros);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        Row(children: [
          IconButton(
              onPressed: () => ref.read(selectedDayProvider.notifier).shift(-1),
              icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: GestureDetector(
              onTap: () => ref.read(selectedDayProvider.notifier).today(),
              child: Text(
                isToday ? 'Dziś' : DateFormat('EEEE, d MMM', 'pl').format(day),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          IconButton(
              onPressed: isToday ? null : () => ref.read(selectedDayProvider.notifier).shift(1),
              icon: const Icon(Icons.chevron_right)),
        ]),
        const SizedBox(height: 8),
        const _AiBanner(),
        _SummaryCard(total: total, goals: goals),
        const _WeeklyLine(),
        const SizedBox(height: 10),
        const _WaterRow(),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _QuickButton(Icons.qr_code_scanner, 'Skanuj', () async {
            await Navigator.push(
                context, MaterialPageRoute(builder: (_) => const ScanScreen()));
          })),
          const SizedBox(width: 8),
          Expanded(
              child: _QuickButton(Icons.search, 'Szukaj', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const FoodSearchScreen()));
          })),
          const SizedBox(width: 8),
          Expanded(
              child: _QuickButton(Icons.auto_awesome, 'Co zjeść?', () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdviceScreen(
                        standalone: true, autoAsk: 'Co mogę zjeść teraz, żeby wpasować się w resztę dnia?')));
          })),
        ]),
        const SizedBox(height: 16),
        const _Frequent(),
        if (entries.isEmpty) _EmptyDay(isToday: isToday, day: day),
        for (var m = 0; m < 4; m++) _MealSection(meal: m, entries: [for (final e in entries) if (e.meal == m) e]),
        const SizedBox(height: 8),
        const _WeekStrip(),
      ],
    );
  }
}

/// Nudges once: without an AI engine voice input only understands simple lists.
class _AiBanner extends ConsumerWidget {
  const _AiBanner();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(aiSettingsProvider).api;
    final local = ref.watch(activeModelsProvider);
    if (api.model.isNotEmpty && api.baseUrl.isNotEmpty || local.isNotEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiProviderScreen())),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.auto_awesome, color: AppColors.amberInk),
              SizedBox(width: 10),
              Expanded(
                child: Text('Podłącz AI (1 minuta), żeby mikrofon rozumiał całe zdania i szukał brakujących produktów. Dotknij, wybierz dostawcę i wklej klucz.',
                    style: TextStyle(color: AppColors.amberInk, fontWeight: FontWeight.w600)),
              ),
              Icon(Icons.chevron_right, color: AppColors.amberInk),
            ]),
          ),
        ),
      ),
    );
  }
}

class _WeeklyLine extends ConsumerWidget {
  const _WeeklyLine();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(weeklyModeProvider)) return const SizedBox.shrink();
    final goals = ref.watch(goalsProvider);
    final eaten = ref.watch(weekEatenProvider).value ?? 0;
    final day = ref.watch(selectedDayProvider);
    final daysLeft = 7 - (day.weekday - 1); // including this day
    final left = goals.kcal * 7 - eaten;
    final perDay = left / daysLeft;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SectionCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(Icons.date_range, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              left >= 0
                  ? 'Tydzień: zostało ${n0(left)} kcal, czyli ok. ${n0(perDay)} na dzień do niedzieli.'
                  : 'Tydzień: ${n0(-left)} kcal ponad. Spokojnie, kolejne dni to wyrównają.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
    );
  }
}

class _WaterRow extends ConsumerWidget {
  const _WaterRow();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ml = ref.watch(waterProvider).value ?? 0;
    const goal = 2000;
    Future<void> add(int v) async {
      await ref.read(dbProvider).addWater(dayKey(ref.read(selectedDayProvider)), v);
      ref.read(dataVersionProvider.notifier).bump();
    }

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(children: [
        Icon(Icons.water_drop_outlined, color: AppColors.blue),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Woda  $ml / $goal ml', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            ProgressBar(ml / goal, color: AppColors.blue, height: 7),
          ]),
        ),
        const SizedBox(width: 8),
        ActionChip(label: const Text('+250'), onPressed: () => add(250)),
        const SizedBox(width: 4),
        IconButton(onPressed: ml > 0 ? () => add(-250) : null, icon: const Icon(Icons.undo, size: 20)),
      ]),
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18), side: BorderSide(color: AppColors.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(children: [
              Icon(icon, color: AppColors.green, size: 26),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
        ),
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.total, required this.goals});
  final Macros total;
  final Goals goals;

  @override
  Widget build(BuildContext context) {
    final left = goals.kcal - total.kcal;
    final over = left < 0;
    return SectionCard(
      child: Column(children: [
        Row(children: [
          SizedBox(
            width: 120,
            height: 120,
            child: CustomPaint(
              painter: _RingPainter(total.kcal / goals.kcal, over ? AppColors.amber : AppColors.green),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(n0(left.abs()), style: figure(size: 28)),
                  Text(over ? 'ponad' : 'zostało',
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${n0(total.kcal)} / ${n0(goals.kcal)} kcal', style: figure(size: 16)),
              const SizedBox(height: 12),
              _MacroBar('Białko', total.p, goals.p, AppColors.blue),
              const SizedBox(height: 8),
              _MacroBar('Węgle', total.c, goals.c, AppColors.amber),
              const SizedBox(height: 8),
              _MacroBar('Tłuszcz', total.f, goals.f, AppColors.green),
            ]),
          ),
        ]),
      ]),
    );
  }
}

class _MacroBar extends StatelessWidget {
  const _MacroBar(this.label, this.v, this.goal, this.color);
  final String label;
  final double v, goal;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(fontSize: 12, color: AppColors.muted)),
          Text('${n0(v)}/${n0(goal)} g', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 3),
        ProgressBar(goal == 0 ? 0 : v / goal, color: color, height: 7),
      ]);
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, this.color);
  final double fraction;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = AppColors.track;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * fraction.clamp(0, 1), false, base..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.fraction != fraction || o.color != color;
}

class _Frequent extends ConsumerWidget {
  const _Frequent();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(frequentProvider).value ?? const <Entry>[];
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Eyebrow('Zwykle jesz'),
      const SizedBox(height: 8),
      SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final e = list[i];
            return ActionChip(
              backgroundColor: AppColors.greenSoft,
              side: BorderSide.none,
              label: Text('${e.name} · ${n0(e.macros.kcal)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              onPressed: () async {
                await ref.read(foodLoggerProvider).repeat(e, when: ref.read(selectedDayProvider));
                if (context.mounted) toast(context, 'Dodano: ${e.name}');
              },
            );
          },
        ),
      ),
      const SizedBox(height: 16),
    ]);
  }
}

class _EmptyDay extends ConsumerWidget {
  const _EmptyDay({required this.isToday, required this.day});
  final bool isToday;
  final DateTime day;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: SectionCard(
          child: Column(children: [
            Icon(Icons.mic_none, size: 40, color: AppColors.green),
            const SizedBox(height: 8),
            Text(isToday ? 'Nic jeszcze. Naciśnij mikrofon i powiedz, co jadłeś.' : 'Brak wpisów tego dnia.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('np. „dwa jajka, kanapka z serem i kawa z mlekiem”',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final from = day.subtract(const Duration(days: 1));
                final n = await ref.read(foodLoggerProvider).copyDay(from, day);
                if (context.mounted) {
                  toast(context, n == 0 ? 'Wczoraj nic nie było.' : 'Skopiowano $n wpisów z poprzedniego dnia.');
                }
              },
              icon: const Icon(Icons.copy_all),
              label: const Text('Powtórz poprzedni dzień'),
            ),
          ]),
        ),
      );
}

class _MealSection extends ConsumerWidget {
  const _MealSection({required this.meal, required this.entries});
  final int meal;
  final List<Entry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final kcal = entries.fold<double>(0, (a, e) => a + e.macros.kcal);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onLongPress: () => _saveSet(context, ref),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Eyebrow(mealNames[meal]),
              Row(children: [
                Text('${n0(kcal)} kcal', style: figure(size: 14)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Zapisz jako zestaw',
                  icon: Icon(Icons.bookmark_add_outlined, size: 20, color: AppColors.muted),
                  onPressed: () => _saveSet(context, ref),
                ),
              ]),
            ]),
          ),
          for (final e in entries) _EntryTile(e),
        ]),
      ),
    );
  }
}

extension on _MealSection {
  /// Saves the meal as a one-portion recipe so "śniadanie jak zawsze" works by voice.
  Future<void> _saveSet(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: mealNames[meal].toLowerCase());
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zapisz jako zestaw'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Nazwa, którą powiesz')),
          const SizedBox(height: 8),
          Text('Potem wystarczy powiedzieć tę nazwę do mikrofonu.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Zapisz')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final total = entries.fold(Macros.zero, (a, e) => a + e.macros);
    await ref.read(dbProvider).saveRecipe(Recipe(
        title: name, ingredients: [for (final e in entries) '${e.name} ${n0(e.grams)} g'], perServing: total));
    ref.read(dataVersionProvider.notifier).bump();
    if (context.mounted) toast(context, 'Zapisano zestaw „$name”. Powiedz: „$name”.');
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile(this.e);
  final Entry e;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Dismissible(
        key: ValueKey('e${e.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
            color: AppColors.amberSoft,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: Icon(Icons.delete_outline, color: AppColors.amberInk)),
        onDismissed: (_) async {
          final db = ref.read(dbProvider);
          await db.deleteEntry(e.id!);
          ref.read(dataVersionProvider.notifier).bump();
          if (context.mounted) {
            toast(context, 'Usunięto: ${e.name}',
                action: SnackBarAction(
                    label: 'Cofnij',
                    onPressed: () async {
                      await db.addEntry(e);
                      ref.read(dataVersionProvider.notifier).bump();
                    }));
          }
        },
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${n0(e.grams)} g · ${macroText(e.macros)}',
              style: const TextStyle(fontSize: 12)),
          trailing: Text('${e.estimated ? '~' : ''}${n0(e.macros.kcal)}', style: figure(size: 15)),
          onTap: () => _edit(context, ref),
        ),
      );

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final per100 = e.grams > 0 ? e.macros * (100 / e.grams) : Macros.zero;
    final food = Food(
        name: e.name,
        kcal100: per100.kcal,
        p100: per100.p,
        c100: per100.c,
        f100: per100.f,
        servingG: e.grams,
        source: e.estimated ? 'ai' : 'own');
    final g = await askGrams(context, food, initial: e.grams);
    if (g == null) return;
    await ref.read(dbProvider).updateEntry(Entry(
        id: e.id, day: e.day, meal: e.meal, name: e.name, grams: g, macros: food.per(g), estimated: e.estimated));
    ref.read(dataVersionProvider.notifier).bump();
  }
}

/// Gentle consistency view: no streak to break, just "days logged this week".
class _WeekStrip extends ConsumerWidget {
  const _WeekStrip();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(weekLoggedProvider).value ?? 0;
    final kcal = ref.watch(weekKcalProvider).value ?? const {};
    final goals = ref.watch(goalsProvider);
    final now = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) now.subtract(Duration(days: i))];
    final msg = switch (n) {
      0 => 'Nowy tydzień, czysta karta. Jeden wpis wystarczy na start.',
      1 || 2 => 'Masz $n z 7 dni. Każdy wpis się liczy.',
      3 || 4 => 'Masz $n z 7 dni. Fajnie idzie.',
      _ => 'Masz $n z 7 dni. Super konsekwencja!',
    };
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeekScreen())),
      child: SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Eyebrow('Ostatnie 7 dni  ·  szczegóły ›'),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final d in days)
            Builder(builder: (_) {
              final k = kcal[dayKey(d)];
              final logged = k != null;
              final ok = logged && k <= goals.kcal * 1.1;
              return Column(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: !logged ? AppColors.chip : (ok ? AppColors.greenSoft : AppColors.amberSoft),
                  ),
                  child: Icon(logged ? Icons.check : Icons.remove,
                      size: 18, color: !logged ? AppColors.muted : (ok ? AppColors.green : AppColors.amber)),
                ),
                const SizedBox(height: 4),
                Text(DateFormat('E', 'pl').format(d), style: TextStyle(fontSize: 11, color: AppColors.muted)),
              ]);
            }),
        ]),
        const SizedBox(height: 10),
        Text(msg, style: TextStyle(color: AppColors.muted)),
      ]),
    ));
  }
}
