import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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
  // Amount is edited in pieces when the food has a piece weight, otherwise in grams;
  // entries without grams (recipes, "na oko") are scaled in portions.
  late bool _pieces = widget.e.hasPieces;
  late double _amount = _initialAmount();
  late final TextEditingController _ctrl = TextEditingController(text: _fmt(_amount));
  late int _meal = widget.e.meal;
  late String _day = widget.e.day;

  bool get _byGrams => widget.e.grams > 0;

  double _initialAmount() {
    final e = widget.e;
    if (!_byGrams) return 1;
    return _pieces ? e.grams / e.pieceG : e.grams;
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

  double get _step => !_byGrams ? 0.5 : (_pieces ? 1 : 10);

  double get _newGrams => !_byGrams ? 0 : (_pieces ? _amount * widget.e.pieceG : _amount);
  double get _factor => !_byGrams ? _amount : _newGrams / widget.e.grams;
  Macros get _macros => widget.e.macros * _factor;

  void _setAmount(double v) {
    final nv = v < _step ? _step : v;
    setState(() => _amount = nv);
    _ctrl.text = _fmt(nv);
  }

  void _switchUnit(bool pieces) {
    if (pieces == _pieces) return;
    final grams = _newGrams;
    setState(() {
      _pieces = pieces;
      _amount = pieces ? grams / widget.e.pieceG : grams;
    });
    _ctrl.text = _fmt(_amount);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final e = widget.e;
    final db = ref.read(dbProvider);
    await db.updateEntry(e.copyWith(meal: _meal, grams: _byGrams ? _newGrams : 0, macros: _macros));
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
    await ref.read(dbProvider).addEntry(e.copyWith(day: dayKey(t), meal: _meal));
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
    Widget unitChip(String label, bool sel, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? AppColors.hero : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sel ? AppColors.accent : AppColors.outline, width: sel ? 2 : 1),
            ),
            child: Text(label, style: fig(14, weight: 700)),
          ),
        );
    final unitLabel = !_byGrams ? 'porcji' : (_pieces ? 'szt.' : 'g');
    final isUrl = e.source.startsWith('http');
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(2)))),
        Text(e.name, style: display(26, height: 1.15)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          round('−', 'Mniej', () => _setAmount(_amount - _step)),
          Column(children: [
            Text('${e.estimated ? '~' : ''}${n0(_macros.kcal)}', style: display(56, height: 60 / 56)),
            Text('kcal', style: fig(15, color: AppColors.text3)),
          ]),
          round('+', 'Więcej', () => _setAmount(_amount + _step)),
        ]),
        const SizedBox(height: 8),
        // Type the amount directly, no stepping needed.
        Center(
          child: SizedBox(
            width: 200,
            child: TextField(
              controller: _ctrl,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: fig(22, weight: 700),
              onChanged: (t) {
                final v = double.tryParse(t.replaceAll(',', '.'));
                if (v != null && v > 0) setState(() => _amount = v);
              },
              decoration: InputDecoration(
                suffixText: ' $unitLabel',
                suffixStyle: fig(18, weight: 600, color: AppColors.text2),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
        if (e.hasPieces && _byGrams)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              unitChip('sztuki', _pieces, () => _switchUnit(true)),
              const SizedBox(width: 8),
              unitChip('gramy', !_pieces, () => _switchUnit(false)),
            ]),
          ),
        const SizedBox(height: 6),
        Center(child: Text('${_byGrams ? '${n0(_newGrams)} g · ' : ''}${macroText(_macros)}', style: fig(14, color: AppColors.text2))),
        if (e.source.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: InkWell(
              onTap: isUrl ? () => launchUrl(Uri.parse(e.source), mode: LaunchMode.externalApplication) : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Center(
                  child: Text(
                    isUrl ? 'Źródło: ${Uri.tryParse(e.source)?.host.replaceFirst('www.', '') ?? e.source}' : 'Źródło: ${e.source}',
                    textAlign: TextAlign.center,
                    style: fig(13, weight: isUrl ? 600 : 400, color: isUrl ? AppColors.accent : AppColors.text2),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
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
