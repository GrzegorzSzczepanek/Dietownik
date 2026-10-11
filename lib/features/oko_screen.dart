import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'common.dart';
import 'widgets.dart';

/// Wpis na oko per design/Oko: kcal only, no invented macros.
class OkoScreen extends ConsumerStatefulWidget {
  const OkoScreen({super.key, this.initialMeal});
  final int? initialMeal;
  @override
  ConsumerState<OkoScreen> createState() => _OkoScreenState();
}

class _OkoScreenState extends ConsumerState<OkoScreen> {
  double _kcal = 400;
  int _size = 1;
  late int _meal = widget.initialMeal ?? mealForTime(DateTime.now());
  final _name = TextEditingController();

  static const _sizes = [('Przekąska', 200.0), ('Lekki', 400.0), ('Pełny', 700.0)];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Widget _round(String t, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(t, style: fig(28, weight: 700, color: AppColors.accentDeep)),
          ),
        ),
      );

  Future<void> _save() async {
    final t = ref.read(selectedDayProvider);
    final name = _name.text.trim().isEmpty ? 'Wpis na oko' : _name.text.trim();
    final id = await ref.read(dbProvider).addEntry(Entry(day: dayKey(t), meal: _meal, name: name, grams: 0, macros: Macros(kcal: _kcal), estimated: true));
    ref.read(dataVersionProvider.notifier).bump();
    if (!mounted) return;
    final db = ref.read(dbProvider);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Dodano ~${n0(_kcal)} kcal'),
        action: SnackBarAction(
            label: 'Cofnij',
            onPressed: () async {
              await db.deleteEntry(id);
              ref.read(dataVersionProvider.notifier).bump();
            }),
      ));
  }

  @override
  Widget build(BuildContext context) {
    Widget choice(String label, bool sel, VoidCallback onTap, {double radius = 14, String? sub}) => GestureDetector(
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? AppColors.hero : Colors.transparent,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: sel ? AppColors.accent : AppColors.outline, width: sel ? 2 : 1),
            ),
            child: Text(label, style: fig(15, weight: 700)),
          ),
        );
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        ListView(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 120), children: [
          HeroZone(
            bottom: 28,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const HeroBackHeader('Wpis na oko', size: 15),
              const SizedBox(height: 4),
              Text('Nie wiesz dokładnie? Wystarczy w przybliżeniu.', style: fig(17, weight: 600, height: 24 / 17)),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _round('−', 'Mniej o 50', () => setState(() => _kcal = (_kcal - 50).clamp(50, 3000))),
                Column(children: [
                  Text('~${n0(_kcal)}', style: display(72)),
                  Text('kcal', style: fig(17, weight: 600)),
                ]),
                _round('+', 'Więcej o 50', () => setState(() => _kcal = (_kcal + 50).clamp(50, 3000))),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Jak duże to było?', style: fig(16, weight: 700)),
              const SizedBox(height: 10),
              Row(children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: choice(_sizes[i].$1, _size == i, () => setState(() { _size = i; _kcal = _sizes[i].$2; }))),
                ],
              ]),
              const SizedBox(height: 6),
              Row(children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: Center(child: Text('~${n0(_sizes[i].$2)}', style: fig(14, color: AppColors.text2)))),
                ],
              ]),
              const SizedBox(height: 24),
              Text('Do którego posiłku?', style: fig(16, weight: 700)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var m = 0; m < 4; m++) choice(mealNames[m], _meal == m, () => setState(() => _meal = m), radius: 24),
              ]),
              const SizedBox(height: 24),
              TextField(controller: _name, decoration: const InputDecoration(hintText: 'Nazwa, np. pizza u Kasi (opcjonalnie)')),
              const SizedBox(height: 12),
              Text('Zapiszę jako ~${n0(_kcal)} kcal. Makro zostaną puste, żeby niczego nie zmyślać.', style: fig(14, color: AppColors.text2, height: 20 / 14)),
            ]),
          ),
        ]),
        Positioned(
          left: 24,
          right: 24,
          bottom: MediaQuery.of(context).padding.bottom + 24,
          child: FilledButton(onPressed: _save, child: Text('Dodaj ~${n0(_kcal)} kcal')),
        ),
      ]),
    );
  }
}
