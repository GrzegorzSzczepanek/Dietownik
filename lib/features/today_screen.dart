import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../ai/local_models.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'api_provider_screen.dart';
import 'common.dart';
import 'food_search_screen.dart';
import 'scan_screen.dart';
import 'week_screen.dart';

/// Dziś, per design/Main, Dzis-pusty and Dzis-przewiniete: a hero zone with
/// one big number that collapses to a compact bar, then flat, line-separated lists.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(selectedDayProvider);
    final entries = ref.watch(dayEntriesProvider).value ?? const <Entry>[];
    final goals = ref.watch(goalsProvider);
    final total = entries.fold(Macros.zero, (a, e) => a + e.macros);
    final top = MediaQuery.of(context).padding.top;
    final bottom = 84 + MediaQuery.of(context).padding.bottom + 40;

    return CustomScrollView(slivers: [
      SliverPersistentHeader(pinned: true, delegate: _HeroDelegate(top: top, total: total, goals: goals, day: day, ref: ref)),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, bottom),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            const _QuickActions(),
            const _WeeklyLine(),
            if (entries.isEmpty) _EmptyDay(day: day) else ...[
              const _Frequent(),
              for (var m = 0; m < 4; m++) _MealSection(meal: m, entries: [for (final e in entries) if (e.meal == m) e]),
            ],
            const SizedBox(height: 24),
            const _WaterRow(),
            const SizedBox(height: 32),
            const _WeekStrip(),
          ]),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- hero

class _HeroDelegate extends SliverPersistentHeaderDelegate {
  _HeroDelegate({required this.top, required this.total, required this.goals, required this.day, required this.ref});
  final double top;
  final Macros total;
  final Goals goals;
  final DateTime day;
  final WidgetRef ref;

  static const _fullBody = 288.0;
  static const _miniBody = 66.0;

  @override
  double get maxExtent => top + _fullBody;
  @override
  double get minExtent => top + _miniBody;

  @override
  bool shouldRebuild(_HeroDelegate o) => o.total != total || o.goals != goals || o.day != day || o.top != top;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final span = maxExtent - minExtent;
    final t = (shrinkOffset / span).clamp(0.0, 1.0);
    final left = goals.kcal - total.kcal;
    final over = left < 0;
    final isToday = dayKey(day) == dayKey(DateTime.now());
    final numColor = over ? AppColors.warn : AppColors.text;
    final barColor = over ? AppColors.carbs : AppColors.accent;
    final frac = goals.kcal == 0 ? 0.0 : (total.kcal / goals.kcal).clamp(0.0, 1.0);

    Widget macro(String label, double v, double goal, Color c) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: fig(13, color: AppColors.text3)),
            Text('${n0(v)} / ${n0(goal)} g', style: fig(15, weight: 600)),
            const SizedBox(height: 5),
            _Bar(goal == 0 ? 0 : v / goal, c, 4),
          ]),
        );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.hero,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32 - 8 * t)),
      ),
      padding: EdgeInsets.fromLTRB(20, top, 20, 0),
      child: Stack(children: [
        // full hero
        Opacity(
          opacity: (1 - t * 2.2).clamp(0.0, 1.0),
          child: IgnorePointer(
            ignoring: t > 0.4,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                height: 52,
                child: Row(children: [
                  Transform.translate(
                    offset: const Offset(-12, 0),
                    child: IconButton(
                        tooltip: 'Poprzedni dzień',
                        onPressed: () => ref.read(selectedDayProvider.notifier).shift(-1),
                        icon: const Icon(Icons.chevron_left, size: 26)),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => ref.read(selectedDayProvider.notifier).today(),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(isToday ? 'Dziś' : DateFormat('EEEE', 'pl').format(day), style: fig(18, weight: 700)),
                        Text(DateFormat('EEEE, d MMMM', 'pl').format(day), style: fig(13, color: AppColors.text3)),
                      ]),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(12, 0),
                    child: IconButton(
                        tooltip: 'Następny dzień',
                        onPressed: isToday ? null : () => ref.read(selectedDayProvider.notifier).shift(1),
                        icon: Icon(Icons.chevron_right, size: 26, color: isToday ? AppColors.text2.withValues(alpha: 0.5) : null)),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text(n0(left.abs()), style: display(72, color: numColor)),
                const SizedBox(width: 10),
                Flexible(child: Text(over ? 'kcal ponad plan' : (total.kcal == 0 ? 'kcal na dziś' : 'kcal zostało'), style: fig(17, weight: 600))),
              ]),
              const SizedBox(height: 12),
              _Bar(frac, barColor, 12),
              const SizedBox(height: 8),
              Text('Zjedzone ${n0(total.kcal)} z ${n0(goals.kcal)}', style: fig(14, color: AppColors.text3)),
              const SizedBox(height: 16),
              Row(children: [
                macro('Białko', total.p, goals.p, AppColors.protein),
                const SizedBox(width: 16),
                macro('Węgle', total.c, goals.c, AppColors.carbs),
                const SizedBox(width: 16),
                macro('Tłuszcz', total.f, goals.f, AppColors.fat),
              ]),
            ]),
          ),
        ),
        // collapsed bar
        Opacity(
          opacity: ((t - 0.55) / 0.45).clamp(0.0, 1.0),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(
              height: 46,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: n0(left.abs()), style: display(26, color: numColor)),
                  TextSpan(text: over ? ' kcal ponad' : ' kcal zostało', style: fig(17, weight: 700)),
                ])),
                Text('B ${n0(total.p)} · W ${n0(total.c)} · T ${n0(total.f)}', style: fig(14, color: AppColors.text3)),
              ]),
            ),
            _Bar(frac, barColor, 6),
          ]),
        ),
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.fraction, this.color, this.height);
  final double fraction;
  final Color color;
  final double height;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: Container(
          height: height,
          color: AppColors.track,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(widthFactor: fraction.clamp(0.0, 1.0), child: Container(color: color)),
        ),
      );
}

// ---------------------------------------------------------------- actions

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget btn(IconData icon, Color iconColor, String label, VoidCallback onTap) => Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: onTap,
              icon: Icon(icon, size: 20, color: iconColor),
              label: Text(label, style: fig(15, weight: 600)),
            ),
          ),
        );
    return Row(children: [
      btn(Icons.qr_code_scanner, AppColors.accent, 'Skanuj',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen()))),
      const SizedBox(width: 8),
      btn(Icons.search, AppColors.accent, 'Szukaj',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FoodSearchScreen()))),
      const SizedBox(width: 8),
      btn(Icons.water_drop_outlined, AppColors.protein, '+250 ml', () => _addWater(ref, 250)),
    ]);
  }
}

Future<void> _addWater(WidgetRef ref, int ml) async {
  await ref.read(dbProvider).addWater(dayKey(ref.read(selectedDayProvider)), ml);
  ref.read(dataVersionProvider.notifier).bump();
}

class _WeeklyLine extends ConsumerWidget {
  const _WeeklyLine();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(weeklyModeProvider)) return const SizedBox.shrink();
    final goals = ref.watch(goalsProvider);
    final eaten = ref.watch(weekEatenProvider).value ?? 0;
    final day = ref.watch(selectedDayProvider);
    final daysLeft = 7 - (day.weekday - 1);
    final left = goals.kcal * 7 - eaten;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        left >= 0
            ? 'Tydzień: zostało ${n0(left)} kcal, czyli ok. ${n0(left / daysLeft)} na dzień do niedzieli.'
            : 'Tydzień: ${n0(-left)} kcal ponad. Spokojnie, kolejne dni to wyrównają.',
        style: fig(15, weight: 600, color: AppColors.text3),
      ),
    );
  }
}

// ---------------------------------------------------------------- empty day

class _EmptyDay extends ConsumerWidget {
  const _EmptyDay({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(aiSettingsProvider).api;
    final local = ref.watch(activeModelsProvider);
    final needsAi = !(api.model.isNotEmpty && api.baseUrl.isNotEmpty) && local.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Powiedz, co dziś jadłeś', style: display(26, height: 1.25)),
        const SizedBox(height: 8),
        Text('Dotknij mikrofon i mów normalnie, np. „dwa jajka, kanapka z serem i kawa z mlekiem”. Zapiszę wszystko naraz.',
            style: fig(16, color: AppColors.text3, height: 1.5)),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          onPressed: () async {
            final n = await ref.read(foodLoggerProvider).copyDay(day.subtract(const Duration(days: 1)), day);
            if (context.mounted) toast(context, n == 0 ? 'Wczoraj nic nie było.' : 'Skopiowano $n wpisów z poprzedniego dnia.');
          },
          icon: const Icon(Icons.copy_all_outlined, size: 20),
          label: Text('Powtórz wczorajszy dzień', style: fig(15, weight: 600)),
        ),
        if (needsAi)
          InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiProviderScreen())),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  Icon(Icons.auto_awesome, size: 18, color: AppColors.warn),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Podłącz AI (1 minuta), żeby mikrofon rozumiał całe zdania', style: fig(14, weight: 600, color: AppColors.warn))),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- frequent + meals

class _Frequent extends ConsumerWidget {
  const _Frequent();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(frequentProvider).value ?? const <Entry>[];
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Zwykle jesz', style: fig(16, weight: 700)),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView.separated(
            clipBehavior: Clip.none,
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final e = list[i];
              return Material(
                color: AppColors.hero,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () async {
                    await ref.read(foodLoggerProvider).repeat(e, when: ref.read(selectedDayProvider));
                    if (context.mounted) toast(context, 'Dodano: ${e.name}');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(child: Text('${e.name} · ${n0(e.macros.kcal)}', style: fig(14, weight: 600, color: AppColors.accentDeep))),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _MealSection extends ConsumerWidget {
  const _MealSection({required this.meal, required this.entries});
  final int meal;
  final List<Entry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final kcal = entries.fold<double>(0, (a, e) => a + e.macros.kcal);
    final dodaj = const ['do śniadania', 'do obiadu', 'do kolacji', 'do przekąsek'][meal];
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 32,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(mealNames[meal], style: fig(18, weight: 700)),
            Row(children: [
              Text('${n0(kcal)} kcal', style: fig(15, color: AppColors.text3)),
              Transform.translate(
                offset: const Offset(12, 0),
                child: IconButton(
                  tooltip: 'Zapisz jako zestaw',
                  icon: Icon(Icons.bookmark_add_outlined, size: 22, color: AppColors.accent),
                  onPressed: () => _saveSet(context, ref, meal, entries),
                ),
              ),
            ]),
          ]),
        ),
        for (final e in entries) _EntryRow(e),
        InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FoodSearchScreen(initialMeal: meal))),
          child: Container(
            height: 52,
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: Row(children: [
              Icon(Icons.add, size: 20, color: AppColors.accent),
              const SizedBox(width: 8),
              Text('Dodaj $dodaj', style: fig(15, weight: 600, color: AppColors.accent)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Saves the meal as a one-portion recipe so "śniadanie jak zawsze" works by voice.
Future<void> _saveSet(BuildContext context, WidgetRef ref, int meal, List<Entry> entries) async {
  final ctrl = TextEditingController(text: mealNames[meal].toLowerCase());
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Zapisz jako zestaw'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Nazwa, którą powiesz')),
        const SizedBox(height: 8),
        Text('Potem wystarczy powiedzieć tę nazwę do mikrofonu.', style: fig(13, color: AppColors.text2)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
        FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 48)),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Zapisz')),
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

class _EntryRow extends ConsumerWidget {
  const _EntryRow(this.e);
  final Entry e;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Dismissible(
        key: ValueKey('e${e.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
            color: AppColors.hero,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: Icon(Icons.delete_outline, color: AppColors.warn)),
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
        child: InkWell(
          onTap: () => _edit(context, ref),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: fig(16, weight: 600)),
                  Text('${e.grams > 0 ? '${n0(e.grams)} g · ' : ''}${macroText(e.macros)}', style: fig(14, color: AppColors.text2)),
                ]),
              ),
              Text('${e.estimated ? '~' : ''}${n0(e.macros.kcal)}', style: fig(18, weight: 600)),
            ]),
          ),
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

// ---------------------------------------------------------------- water + week

class _WaterRow extends ConsumerWidget {
  const _WaterRow();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ml = ref.watch(waterProvider).value ?? 0;
    const goal = 2000;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: AppColors.line))),
      child: Row(children: [
        Icon(Icons.water_drop_outlined, color: AppColors.protein),
        const SizedBox(width: 12),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: 'Woda ', style: fig(16, weight: 600)),
              TextSpan(text: '$ml / $goal ml', style: fig(16, color: AppColors.text2)),
            ])),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Container(
                height: 5,
                color: AppColors.protein.withValues(alpha: 0.18),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(widthFactor: (ml / goal).clamp(0.0, 1.0), child: Container(color: AppColors.protein)),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 44,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: () => _addWater(ref, 250),
            child: Text('+250', style: fig(15, weight: 600)),
          ),
        ),
        Transform.translate(
          offset: const Offset(8, 0),
          child: IconButton(
            tooltip: 'Cofnij wodę',
            onPressed: ml > 0 ? () => _addWater(ref, -250) : null,
            icon: Icon(Icons.undo, color: AppColors.text2),
          ),
        ),
      ]),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final r = (size.width - 1.5) / 2;
    const dashes = 18;
    for (var i = 0; i < dashes; i++) {
      final a = i * 2 * math.pi / dashes;
      canvas.drawArc(Rect.fromCircle(center: size.center(Offset.zero), radius: r), a, 2 * math.pi / dashes * 0.55, false, p);
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter o) => o.color != color;
}

/// Gentle consistency view: days with a log are filled, empty days are dashed, never red.
class _WeekStrip extends ConsumerWidget {
  const _WeekStrip();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kcal = ref.watch(weekKcalProvider).value ?? const {};
    final n = ref.watch(weekLoggedProvider).value ?? 0;
    final now = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) now.subtract(Duration(days: i))];
    final msg = switch (n) {
      0 => 'Nowy tydzień, czysta karta. Jeden wpis wystarczy na start.',
      1 || 2 => 'Masz $n z 7 dni. Każdy wpis się liczy.',
      3 || 4 => 'Masz $n z 7 dni. Fajnie idzie.',
      _ => 'Masz $n z 7 dni. Super konsekwencja!',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Ostatnie 7 dni', style: fig(18, weight: 700)),
        Transform.translate(
          offset: const Offset(8, 0),
          child: TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeekScreen())),
            child: Text('Statystyki', style: fig(15, weight: 600, color: AppColors.accent)),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      Row(children: [
        for (final d in days)
          Expanded(
            child: Builder(builder: (_) {
              final logged = kcal[dayKey(d)] != null;
              final isToday = dayKey(d) == dayKey(now);
              return Column(children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: logged
                      ? DecoratedBox(
                          decoration: BoxDecoration(color: AppColors.hero, shape: BoxShape.circle),
                          child: Icon(Icons.check, size: 20, color: AppColors.accent),
                        )
                      : CustomPaint(painter: _DashedCirclePainter(AppColors.outline)),
                ),
                const SizedBox(height: 6),
                Text(DateFormat('E', 'pl').format(d),
                    style: fig(13, weight: isToday ? 700 : 400, color: isToday ? AppColors.accentDeep : AppColors.text2)),
              ]);
            }),
          ),
      ]),
      const SizedBox(height: 12),
      Text(msg, style: fig(14, color: AppColors.text3)),
    ]);
  }
}
