import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'common.dart';
import 'settings_screen.dart' show restoreBackup;
import 'widgets.dart';

/// First run, per design/Start-1..3: welcome, daily calories, permissions.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  double _kcal = 2000;
  int _goal = 1; // 0 lose, 1 keep, 2 gain
  final _perm = <String, bool>{};

  static const _delta = [-400.0, 0.0, 300.0];
  double _base = 2000;

  void _setGoal(int g) => setState(() {
        _goal = g;
        _kcal = (_base + _delta[g]).clamp(1200, 5000);
      });

  Future<void> _finish() async {
    await ref.read(goalsProvider.notifier).set(Goals.fromKcal(_kcal));
    await ref.read(onboardedProvider.notifier).done();
  }

  Future<void> _ask(String key, Future<bool> Function() f) async {
    final ok = await f();
    if (mounted) setState(() => _perm[key] = ok);
  }

  Future<void> _calc() async {
    final r = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (_) => const _CalcSheet(),
    );
    if (r != null) setState(() { _base = r; _kcal = r; _goal = 1; });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + 32;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: switch (_step) {
        0 => _welcome(bottom),
        1 => _calories(bottom),
        _ => _permissions(bottom),
      },
    );
  }

  Widget _cta(String label, VoidCallback onTap, {Widget? below}) => Positioned(
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).padding.bottom + 24,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FilledButton(onPressed: onTap, child: Text(label)),
          if (below != null) ...[const SizedBox(height: 4), below],
        ]),
      );

  Widget _welcome(double bottom) => Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            height: 360,
            width: double.infinity,
            decoration: BoxDecoration(color: AppColors.hero, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(48))),
            alignment: Alignment.center,
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
              child: Icon(Icons.mic, size: 60, color: AppColors.onAccent),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Powiedz, co zjadłeś. Reszta dzieje się sama.', style: display(40, height: 44 / 40)),
              const SizedBox(height: 16),
              Text('Mów, skanuj kod albo tapnij „zwykle jem”. Dziura w logu nikomu nie szkodzi. Dane zostają na telefonie.', style: fig(17, color: AppColors.text3, height: 26 / 17)),
            ]),
          ),
        ]),
        _cta('Zacznij', () => setState(() => _step = 1),
            below: TextButton(
                onPressed: () async {
                  if (await restoreBackup(context, ref)) await ref.read(onboardedProvider.notifier).done();
                },
                child: const Text('Mam kopię zapasową'))),
      ]);

  Widget _stepper() => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _roundBtn('−', 'Mniej o 50', () => setState(() => _kcal = (_kcal - 50).clamp(1200, 5000))),
        Column(children: [
          Text(n0(_kcal), style: display(72)),
          Text('kcal dziennie', style: fig(17, weight: 600)),
        ]),
        _roundBtn('+', 'Więcej o 50', () => setState(() => _kcal = (_kcal + 50).clamp(1200, 5000))),
      ]);

  Widget _roundBtn(String t, String label, VoidCallback onTap) => Semantics(
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

  Widget _calories(double bottom) => Stack(children: [
        ListView(padding: EdgeInsets.only(bottom: bottom + 80), children: [
          HeroZone(
            bottom: 28,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                height: 52,
                child: Row(children: [
                  Transform.translate(offset: const Offset(-12, 0), child: IconButton(tooltip: 'Wróć', icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _step = 0))),
                  Text('Krok 1 z 2', style: fig(15, color: AppColors.text3)),
                ]),
              ),
              const SizedBox(height: 8),
              Text('Ile chcesz jeść dziennie?', style: display(30, height: 34 / 30)),
              const SizedBox(height: 20),
              _stepper(),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Twój cel', style: fig(16, weight: 700)),
              const SizedBox(height: 10),
              Container(
                height: 52,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  for (final e in [(0, 'Schudnąć'), (1, 'Utrzymać'), (2, 'Przytyć')])
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _setGoal(e.$1),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _goal == e.$1 ? AppColors.bg : Colors.transparent,
                            borderRadius: BorderRadius.circular(11),
                            boxShadow: _goal == e.$1 ? [BoxShadow(color: const Color(0xFF17201C).withValues(alpha: 0.18), blurRadius: 2, offset: const Offset(0, 1))] : null,
                          ),
                          child: Text(e.$2, style: fig(14, weight: _goal == e.$1 ? 700 : 600, color: _goal == e.$1 ? AppColors.text : AppColors.text3)),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              NavRow(
                title: 'Policz z moich danych',
                subtitle: 'Wiek, wzrost, waga, aktywność',
                bottomLine: true,
                minHeight: 56,
                onTap: _calc,
              ),
              const SizedBox(height: 16),
              Text('Cele makro ustawię z tego automatycznie. Zmienisz je później w zakładce Ja.', style: fig(14, color: AppColors.text2, height: 20 / 14)),
            ]),
          ),
        ]),
        _cta('Dalej', () => setState(() => _step = 2)),
      ]);

  Widget _permissions(double bottom) {
    Widget row(String key, String title, String sub, Future<bool> Function() ask, {bool last = false}) {
      final ok = _perm[key] == true;
      return Container(
        constraints: const BoxConstraints(minHeight: 84),
        decoration: BoxDecoration(border: Border(top: key == 'mic' ? BorderSide.none : BorderSide(color: AppColors.line), bottom: last ? BorderSide(color: AppColors.line) : BorderSide.none)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: fig(17, weight: 700)),
              Text(sub, style: fig(14, color: AppColors.text2, height: 20 / 14)),
            ]),
          ),
          const SizedBox(width: 12),
          ok
              ? Icon(Icons.check_circle, color: AppColors.accent, size: 28)
              : OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: () => _ask(key, ask),
                  child: Text('Zezwól', style: fig(15, weight: 700)),
                ),
        ]),
      );
    }

    return Stack(children: [
      ListView(padding: EdgeInsets.only(bottom: bottom + 110), children: [
        HeroZone(
          bottom: 28,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 52,
              child: Row(children: [
                Transform.translate(offset: const Offset(-12, 0), child: IconButton(tooltip: 'Wróć', icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _step = 1))),
                Text('Krok 2 z 2', style: fig(15, color: AppColors.text3)),
              ]),
            ),
            const SizedBox(height: 8),
            Text('Zezwolenia, żeby wszystko działało', style: display(30, height: 34 / 30)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            row('mic', 'Mikrofon', 'Żeby zapisywać posiłki głosem', () async => (await Permission.microphone.request()).isGranted),
            row('cam', 'Aparat', 'Żeby skanować kody i zdjęcia etykiet', () async => (await Permission.camera.request()).isGranted),
            row('notif', 'Powiadomienia', 'Opcjonalne. Tylko gdy nie zapisałeś posiłku', () async => ref.read(reminderSchedulerProvider).requestPermission(), last: true),
            const SizedBox(height: 16),
            Text('Zdjęcia etykiet i pytania do AI wysyłam do dostawcy tylko wtedy, gdy sam podłączysz AI.', style: fig(14, color: AppColors.text2, height: 20 / 14)),
          ]),
        ),
      ]),
      _cta('Gotowe, zaczynam', _finish, below: TextButton(onPressed: _finish, child: Text('Pomiń, włączę później', style: fig(15, weight: 600, color: AppColors.text3)))),
    ]);
  }
}

class _CalcSheet extends StatefulWidget {
  const _CalcSheet();
  @override
  State<_CalcSheet> createState() => _CalcSheetState();
}

class _CalcSheetState extends State<_CalcSheet> {
  final _age = TextEditingController(text: '30');
  final _h = TextEditingController(text: '175');
  final _w = TextEditingController(text: '75');
  bool _male = true;
  double _act = 1.4;

  double _d(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Policz z moich danych', style: display(26)),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: true, label: Text('Mężczyzna')), ButtonSegment(value: false, label: Text('Kobieta'))],
            selected: {_male},
            onSelectionChanged: (s) => setState(() => _male = s.first),
          ),
          const SizedBox(height: 12),
          Row(children: [
            for (final e in [(_age, 'Wiek'), (_h, 'Wzrost cm'), (_w, 'Waga kg')])
              Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: TextField(controller: e.$1, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: e.$2)))),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<double>(
            initialValue: _act,
            decoration: const InputDecoration(labelText: 'Aktywność'),
            items: const [
              DropdownMenuItem(value: 1.2, child: Text('Siedzący tryb życia')),
              DropdownMenuItem(value: 1.4, child: Text('Lekko aktywny')),
              DropdownMenuItem(value: 1.6, child: Text('Aktywny')),
              DropdownMenuItem(value: 1.8, child: Text('Bardzo aktywny')),
            ],
            onChanged: (v) => setState(() => _act = v ?? 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context, Goals.calculate(male: _male, age: _d(_age).round(), heightCm: _d(_h), weightKg: _d(_w), activity: _act, kcalDelta: 0).kcal),
            child: const Text('Policz'),
          ),
        ]),
      );
}
