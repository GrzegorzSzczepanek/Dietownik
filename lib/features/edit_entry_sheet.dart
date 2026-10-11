import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'common.dart';
import 'widgets.dart';

/// Edycja wpisu per design/Edycja-wpisu: amount stepper, meal, move/copy, correct product, delete.
Future<void> showEditEntry(BuildContext context, Entry e) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      barrierColor: const Color(0xFF17201C).withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _EditEntry(e),
    );

class _EditEntry extends ConsumerStatefulWidget {
  const _EditEntry(this.e);
  final Entry e;
  @override
  ConsumerState<_EditEntry> createState() => _EditEntryState();
}

class _EditEntryState extends ConsumerState<_EditEntry> {
  late double _amount = widget.e.grams > 0 ? widget.e.grams : 1; // grams, or portions when grams == 0
  late int _meal = widget.e.meal;
  late String _day = widget.e.day;

  bool get _byGrams => widget.e.grams > 0;
  double get _factor => _byGrams ? _amount / widget.e.grams : _amount;
  Macros get _macros => widget.e.macros * _factor;

  Future<void> _save() async {
    final e = widget.e;
    final db = ref.read(dbProvider);
    await db.updateEntry(Entry(id: e.id, day: e.day, meal: _meal, name: e.name, grams: _byGrams ? _amount : 0, macros: _macros, estimated: e.estimated));
    if (_day != e.day) await db.moveEntry(e.id!, _day, _meal);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDay() async {
    final cur = DateTime.parse(_day);
    final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 30)), locale: const Locale('pl'));
    if (d != null) setState(() => _day = dayKey(d));
  }

  Future<void> _copyTomorrow() async {
    final e = widget.e;
    final t = DateTime.parse(_day).add(const Duration(days: 1));
    await ref.read(dbProvider).addEntry(Entry(day: dayKey(t), meal: _meal, name: e.name, grams: e.grams, macros: e.macros, estimated: e.estimated));
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) {
      toast(context, 'Skopiowano na jutro');
      Navigator.pop(context);
    }
  }

  Future<void> _delete() async {
    final e = widget.e;
    final db = ref.read(dbProvider);
    final messenger = ScaffoldMessenger.of(context);
    await db.deleteEntry(e.id!);
    ref.read(dataVersionProvider.notifier).bump();
    if (!mounted) return;
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('Usunięto: ${e.name}'),
          action: SnackBarAction(label: 'Cofnij', onPressed: () async {
            await db.addEntry(e);
            ref.read(dataVersionProvider.notifier).bump();
          })));
  }

  String _dayLabel(String d) {
    final dt = DateTime.parse(d);
    if (d == dayKey(DateTime.now())) return 'Dziś';
    return DateFormat('d MMM', 'pl').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.e;
    final step = _byGrams ? 10.0 : 0.5;
    Widget round(String t, String label, VoidCallback onTap) => Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.outline)),
              alignment: Alignment.center,
              child: Text(t, style: fig(24, weight: 700)),
            ),
          ),
        );
    Widget action(String title, String? trailing, VoidCallback onTap, {Color? color}) => InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(title, style: fig(16, weight: 600, color: color)),
              if (trailing != null) Flexible(child: Text(trailing, textAlign: TextAlign.right, style: fig(14, weight: 500, color: AppColors.text2))),
            ]),
          ),
        );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(2)))),
        Text(e.name, style: display(26, height: 1.15)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          round('−', 'Mniej', () => setState(() => _amount = (_amount - step).clamp(step, 5000))),
          Column(children: [
            Text('${e.estimated ? '~' : ''}${n0(_macros.kcal)}', style: display(56, height: 60 / 56)),
            Text(_byGrams ? 'kcal, ${n0(_amount)} g' : 'kcal, ${_amount == _amount.roundToDouble() ? n0(_amount) : _amount.toStringAsFixed(1)} porcji', style: fig(15, color: AppColors.text3)),
          ]),
          round('+', 'Więcej', () => setState(() => _amount = _amount + step)),
        ]),
        const SizedBox(height: 4),
        Center(child: Text(macroText(_macros), style: fig(14, color: AppColors.text2))),
        const SizedBox(height: 16),
        Row(children: [
          for (var m = 0; m < 4; m++) ...[
            if (m > 0) const SizedBox(width: 6),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _meal = m),
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _meal == m ? AppColors.hero : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _meal == m ? AppColors.accent : AppColors.outline, width: _meal == m ? 2 : 1),
                  ),
                  child: FittedBox(child: Text(mealNames[m], style: fig(13, weight: 700))),
                ),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        action('Przenieś na inny dzień', _dayLabel(_day), _pickDay),
        action('Skopiuj na jutro', null, _copyTomorrow),
        action('Popraw wartości produktu', 'Zmieni się też w przyszłych wpisach', () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (_) => CorrectProductScreen(entry: e)));
        }),
        action('Usuń wpis', 'Zawsze możesz cofnąć', _delete),
        const SizedBox(height: 8),
        FilledButton(onPressed: _save, child: const Text('Zapisz')),
      ]),
    );
  }
}

/// Korekta produktu per design/Korekta-produktu: per 100 g values, saved from now on.
class CorrectProductScreen extends ConsumerStatefulWidget {
  const CorrectProductScreen({super.key, required this.entry});
  final Entry entry;
  @override
  ConsumerState<CorrectProductScreen> createState() => _CorrectProductScreenState();
}

class _CorrectProductScreenState extends ConsumerState<CorrectProductScreen> {
  late final Macros _per100 = widget.entry.grams > 0 ? widget.entry.macros * (100 / widget.entry.grams) : widget.entry.macros;
  late final _k = TextEditingController(text: n0(_per100.kcal));
  late final _p = TextEditingController(text: n1(_per100.p));
  late final _c = TextEditingController(text: n1(_per100.c));
  late final _f = TextEditingController(text: n1(_per100.f));

  double _d(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  Future<void> _save() async {
    final parts = widget.entry.name.split(' · ');
    await ref.read(dbProvider).saveCorrectedFood(Food(
          name: parts.first,
          brand: parts.length > 1 ? parts.sublist(1).join(' · ') : '',
          kcal100: _d(_k),
          p100: _d(_p),
          c100: _d(_c),
          f100: _d(_f),
          servingG: widget.entry.grams > 0 ? widget.entry.grams : 100,
          source: 'own',
        ));
    if (mounted) {
      toast(context, 'Zapisano poprawkę. Działa od teraz.');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget row(String label, TextEditingController c, String unit, Color color, {bool last = false}) => Container(
          constraints: const BoxConstraints(minHeight: 60),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line), bottom: last ? BorderSide(color: AppColors.line) : BorderSide.none)),
          child: Row(children: [
            Expanded(child: Text(label, style: fig(17, weight: 600, color: color))),
            SizedBox(
              width: 120,
              child: TextField(
                controller: c,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: fig(17, weight: 600),
                decoration: InputDecoration(suffixText: ' $unit', suffixStyle: fig(14, weight: 500, color: AppColors.text2), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
              ),
            ),
          ]),
        );
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        ListView(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 110), children: [
          HeroZone(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const HeroBackHeader('Popraw produkt', size: 15),
              const SizedBox(height: 4),
              Text(widget.entry.name, style: display(30, height: 34 / 30)),
              const SizedBox(height: 6),
              Text('Wartości na 100 g. Zapamiętam je dla tego produktu.', style: fig(15, color: AppColors.text3, height: 22 / 15)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              row('Kalorie', _k, 'kcal', AppColors.text),
              row('Białko', _p, 'g', AppColors.protein),
              row('Węglowodany', _c, 'g', AppColors.carbs),
              row('Tłuszcz', _f, 'g', AppColors.fat, last: true),
              const SizedBox(height: 16),
              Text('Dotychczasowe wpisy zostają bez zmian. Poprawka działa od teraz.', style: fig(14, color: AppColors.text2, height: 20 / 14)),
            ]),
          ),
        ]),
        Positioned(left: 24, right: 24, bottom: MediaQuery.of(context).padding.bottom + 24, child: FilledButton(onPressed: _save, child: const Text('Zapisz poprawkę'))),
      ]),
    );
  }
}
