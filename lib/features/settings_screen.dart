import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../ai/ai_settings.dart';
import '../core/theme.dart';
import '../domain/csv_import.dart';
import '../domain/models.dart';
import '../notifications/reminders.dart';
import '../providers.dart';
import 'usage_screen.dart';
import 'weight_screen.dart';
import 'api_provider_screen.dart';
import 'common.dart';
import 'local_models_screen.dart';
import 'widgets.dart';

/// Ja per design/Ja: goal as the hero number, then flat settings rows.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);
    final ai = ref.watch(aiSettingsProvider);
    final ctrl = ref.read(aiSettingsProvider.notifier);
    final ready = ref.watch(engineReadyProvider);
    final tasks = AiTask.values.where((t) => t != AiTask.embeddings).toList();
    final allApi = tasks.every((t) => ai.engineFor(t) == AiEngine.api);
    final apiOk = ai.api.model.isNotEmpty && ai.api.baseUrl.isNotEmpty;
    final bottom = 84 + MediaQuery.of(context).padding.bottom + 40;

    Future<void> setMode(bool api) async {
      for (final t in tasks) {
        await ctrl.setEngine(t, api ? AiEngine.api : AiEngine.local);
      }
    }

    Widget switchRow(String title, String sub, bool value, ValueChanged<bool> onChanged, {bool top = true, bool bottomLine = false}) => Container(
          constraints: const BoxConstraints(minHeight: 64),
          decoration: BoxDecoration(border: Border(top: top ? BorderSide(color: AppColors.line) : BorderSide.none, bottom: bottomLine ? BorderSide(color: AppColors.line) : BorderSide.none)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: fig(16, weight: 600)),
                Text(sub, style: fig(14, color: AppColors.text2, height: 20 / 14)),
              ]),
            ),
            Switch(value: value, onChanged: onChanged),
          ]),
        );

    Widget segment(String label, bool selected, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.bg : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                boxShadow: selected ? [BoxShadow(color: const Color(0xFF17201C).withValues(alpha: 0.18), blurRadius: 2, offset: const Offset(0, 1))] : null,
              ),
              child: Text(label, style: fig(15, weight: selected ? 700 : 600, color: selected ? AppColors.text : AppColors.text3)),
            ),
          ),
        );

    return ListView(padding: EdgeInsets.only(bottom: bottom), children: [
      HeroZone(
        bottom: 20,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(height: 48, child: Align(alignment: Alignment.centerLeft, child: Text('Ja', style: fig(18, weight: 700)))),
          const SizedBox(height: 8),
          Text('Twój dzienny cel', style: fig(15, color: AppColors.text3)),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(n0(goals.kcal), style: display(56)),
            const SizedBox(width: 10),
            Text('kcal', style: fig(17, weight: 600)),
          ]),
          const SizedBox(height: 2),
          Text('Białko ${n0(goals.p)} g · węgle ${n0(goals.c)} g · tłuszcz ${n0(goals.f)} g', style: fig(15, color: AppColors.text3)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GoalsScreen())),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(14)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.edit_outlined, size: 20, color: AppColors.accent),
                const SizedBox(width: 8),
                Text('Zmień cele', style: fig(15, weight: 700, color: AppColors.accent)),
              ]),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Cele i pomiary', style: fig(18, weight: 700)),
          const SizedBox(height: 4),
          switchRow('Cel na cały tydzień', 'Gorszy dzień się wyrówna', ref.watch(weeklyModeProvider), (v) => ref.read(weeklyModeProvider.notifier).set(v)),
          NavRow(
            minHeight: 56,
            title: 'Waga i trend',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeightScreen())),
          ),
          const _RemindersCard(),
          const SizedBox(height: 28),
          Text('Rozumienie zdań (AI)', style: fig(18, weight: 700)),
          const SizedBox(height: 2),
          Text('Mikrofon, szacowanie makro i porady używają jednego trybu.', style: fig(14, color: AppColors.text2, height: 20 / 14)),
          const SizedBox(height: 12),
          Container(
            height: 52,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              segment('Na telefonie', !allApi, () => setMode(false)),
              segment('Przez internet', allApi, () => setMode(true)),
            ]),
          ),
          if (!allApi && !ready)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Silnik na telefonie nie wystartował na tym urządzeniu. Użyj trybu przez internet.', style: fig(14, weight: 600, color: AppColors.warn))),
          const SizedBox(height: 4),
          NavRow(
            topLine: false,
            minHeight: 60,
            title: 'Dostawca API',
            subtitle: apiOk ? '${ai.api.providerLabel}, ${ai.api.model}' : 'Nie skonfigurowano. Dodaj klucz',
            subtitleColor: apiOk ? null : AppColors.warn,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiProviderScreen())),
          ),
          NavRow(
            minHeight: 60,
            title: 'Zużycie AI',
            subtitle: 'Szacunkowy koszt w tym miesiącu',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UsageScreen())),
          ),
          NavRow(
            minHeight: 60,
            title: 'Modele na telefonie',
            subtitle: 'Pobierz raz, potem działają bez internetu',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LocalModelsScreen())),
          ),
          const SizedBox(height: 24),
          Text('Twoje dane', style: fig(18, weight: 700)),
          const SizedBox(height: 4),
          NavRow(minHeight: 52, title: 'Zapisz kopię zapasową', onTap: () => _backup(context, ref), trailing: const SizedBox.shrink()),
          NavRow(minHeight: 52, title: 'Przywróć z kopii', onTap: () => _restore(context, ref), trailing: const SizedBox.shrink()),
          NavRow(minHeight: 52, bottomLine: true, title: 'Importuj produkty z CSV', subtitle: 'nazwa; marka; kcal; białko; węgle; tłuszcz; porcja g; na; kod', onTap: () => _importCsv(context, ref), trailing: const SizedBox.shrink()),
          const SizedBox(height: 20),
          Text('Dietownik 1.0 · dane trzymane tylko na telefonie. Wartości oznaczone „~” są szacunkowe. Produkty z kodami: © uczestnicy Open Food Facts, licencja ODbL.',
              style: fig(13, color: AppColors.text2, height: 18 / 13)),
        ]),
      ),
    ]);
  }
}

Future<void> _backup(BuildContext context, WidgetRef ref) async {
  try {
    final data = await ref.read(dbProvider).exportAll();
    final g = ref.read(goalsProvider);
    data['goals'] = {'kcal': g.kcal, 'p': g.p, 'c': g.c, 'f': g.f};
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/dietownik-${dayKey(DateTime.now())}.json');
    await f.writeAsString(jsonEncode(data));
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'Kopia Dietownika'));
  } catch (e) {
    if (context.mounted) toast(context, 'Nie udało się zrobić kopii: $e');
  }
}

Future<bool> restoreBackup(BuildContext context, WidgetRef ref) => _restore(context, ref);

Future<bool> _restore(BuildContext context, WidgetRef ref) async {
  final pick = await FilePicker.pickFiles(type: FileType.any);
  final path = pick.isEmpty ? null : pick.first.path;
  if (path == null || !context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Przywrócić kopię?'),
      content: const Text('Obecne wpisy, przepisy i waga zostaną zastąpione danymi z pliku.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
        FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(120, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Przywróć')),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    final data = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    await ref.read(dbProvider).importAll(data);
    final g = data['goals'];
    if (g is Map) {
      await ref.read(goalsProvider.notifier).set(Goals(
          kcal: (g['kcal'] as num).toDouble(), p: (g['p'] as num).toDouble(), c: (g['c'] as num).toDouble(), f: (g['f'] as num).toDouble()));
    }
    ref.read(dataVersionProvider.notifier).bump();
    if (context.mounted) toast(context, 'Przywrócono kopię.');
    return true;
  } catch (e) {
    if (context.mounted) toast(context, 'Nie udało się przywrócić: $e');
    return false;
  }
}

class _RemindersCard extends ConsumerWidget {
  const _RemindersCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(remindersProvider).value ?? const ReminderPrefs();
    final ctrl = ref.read(remindersProvider.notifier);
    const names = ['Śniadanie', 'Obiad', 'Kolacja'];
    String fmt(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line), bottom: BorderSide(color: AppColors.line))),
      child: Column(children: [
        Container(
          constraints: const BoxConstraints(minHeight: 64),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Przypomnienia o posiłkach', style: fig(16, weight: 600)),
                Text('Tylko gdy posiłku jeszcze nie zapisałeś', style: fig(14, color: AppColors.text2, height: 20 / 14)),
              ]),
            ),
            Switch(
              value: prefs.enabled,
              onChanged: (v) async {
                final ok = await ctrl.set(prefs.copyWith(enabled: v));
                if (!ok && context.mounted) toast(context, 'Brak zgody na powiadomienia. Włącz ją w ustawieniach telefonu.');
              },
            ),
          ]),
        ),
        if (prefs.enabled)
          for (var i = 0; i < 3; i++)
            InkWell(
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: prefs.slots[i] ~/ 60, minute: prefs.slots[i] % 60));
                if (t == null) return;
                final slots = [...prefs.slots]..[i] = t.hour * 60 + t.minute;
                await ctrl.set(prefs.copyWith(slots: slots));
              },
              child: Container(
                height: 48,
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(names[i], style: fig(15)),
                  Text(fmt(prefs.slots[i]), style: fig(16, weight: 700)),
                ]),
              ),
            ),
      ]),
    );
  }
}

Future<void> _importCsv(BuildContext context, WidgetRef ref) async {
  final pick = await FilePicker.pickFiles(type: FileType.any);
  final path = pick.isEmpty ? null : pick.first.path;
  if (path == null) return;
  try {
    final foods = parseFoodsCsv(await File(path).readAsString());
    final db = ref.read(dbProvider);
    for (final f in foods) {
      await db.saveFood(f);
    }
    if (context.mounted) {
      toast(context, foods.isEmpty ? 'Nie znalazłem poprawnych wierszy.' : 'Zaimportowano ${foods.length} produktów.');
    }
  } catch (e) {
    if (context.mounted) toast(context, 'Import nie wyszedł: $e');
  }
}

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});
  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  late final _k = TextEditingController(text: n0(ref.read(goalsProvider).kcal));
  late final _p = TextEditingController(text: n0(ref.read(goalsProvider).p));
  late final _c = TextEditingController(text: n0(ref.read(goalsProvider).c));
  late final _f = TextEditingController(text: n0(ref.read(goalsProvider).f));
  final _age = TextEditingController(text: '30');
  final _h = TextEditingController(text: '175');
  final _w = TextEditingController(text: '75');
  bool _male = true;
  double _act = 1.4;
  double _delta = 0;

  double _d(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  void _calc() {
    final g = Goals.calculate(male: _male, age: _d(_age).round(), heightCm: _d(_h), weightKg: _d(_w), activity: _act, kcalDelta: _delta);
    setState(() { _k.text = n0(g.kcal); _p.text = n0(g.p); _c.text = n0(g.c); _f.text = n0(g.f); });
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String l) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l))));
    return Scaffold(
      appBar: AppBar(title: const Text('Cele dzienne')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Eyebrow('Policz za mnie'),
        const SizedBox(height: 8),
        SegmentedButton<bool>(segments: const [ButtonSegment(value: true, label: Text('Mężczyzna')), ButtonSegment(value: false, label: Text('Kobieta'))], selected: {_male}, onSelectionChanged: (s) => setState(() => _male = s.first)),
        const SizedBox(height: 8),
        Row(children: [field(_age, 'Wiek'), field(_h, 'Wzrost cm'), field(_w, 'Waga kg')]),
        const SizedBox(height: 8),
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
        const SizedBox(height: 8),
        DropdownButtonFormField<double>(
          initialValue: _delta,
          decoration: const InputDecoration(labelText: 'Cel'),
          items: const [
            DropdownMenuItem(value: -500.0, child: Text('Schudnąć (−500 kcal)')),
            DropdownMenuItem(value: -250.0, child: Text('Powoli schudnąć (−250)')),
            DropdownMenuItem(value: 0.0, child: Text('Utrzymać wagę')),
            DropdownMenuItem(value: 300.0, child: Text('Przybrać (+300)')),
          ],
          onChanged: (v) => setState(() => _delta = v ?? 0),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _calc, icon: const Icon(Icons.calculate), label: const Text('Policz kalorie i makro')),
        const SizedBox(height: 20),
        const Eyebrow('Twoje cele'),
        const SizedBox(height: 8),
        Row(children: [field(_k, 'kcal'), field(_p, 'Białko g'), field(_c, 'Węgle g'), field(_f, 'Tłuszcz g')]),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            await ref.read(goalsProvider.notifier).set(Goals(kcal: _d(_k), p: _d(_p), c: _d(_c), f: _d(_f)));
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Zapisz'),
        ),
      ]),
    );
  }
}
