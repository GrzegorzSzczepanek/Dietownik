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
import 'weight_screen.dart';
import 'api_provider_screen.dart';
import 'common.dart';
import 'local_models_screen.dart';
import 'widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);
    final ai = ref.watch(aiSettingsProvider);
    final ctrl = ref.read(aiSettingsProvider.notifier);
    final ready = ref.watch(engineReadyProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        const Text('Ja', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        SectionCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            title: Text('${n0(goals.kcal)} kcal dziennie', style: mono(size: 18)),
            subtitle: Text('Białko ${n0(goals.p)} g · węgle ${n0(goals.c)} g · tłuszcz ${n0(goals.f)} g'),
            trailing: const Icon(Icons.edit),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GoalsScreen())),
          ),
        ),
        const SizedBox(height: 8),
        SectionCard(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            secondary: const Icon(Icons.date_range, color: AppColors.green),
            title: const Text('Cel tygodniowy'),
            subtitle: const Text('Kalorie liczone na cały tydzień. Gorszy dzień się wyrównuje.'),
            value: ref.watch(weeklyModeProvider),
            onChanged: (v) => ref.read(weeklyModeProvider.notifier).set(v),
          ),
        ),
        const SizedBox(height: 8),
        SectionCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.monitor_weight_outlined, color: AppColors.green),
            title: const Text('Waga i trend'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeightScreen())),
          ),
        ),
        const SizedBox(height: 8),
        const _RemindersCard(),
        const SizedBox(height: 16),
        const Eyebrow('AI — CO GDZIE DZIAŁA'),
        const SizedBox(height: 8),
        SectionCard(
          child: Column(children: [
            for (final t in AiTask.values.where((t) => t != AiTask.embeddings))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(child: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                  EngineToggle(api: ai.engineFor(t) == AiEngine.api, onChanged: (api) => ctrl.setEngine(t, api ? AiEngine.api : AiEngine.local)),
                ]),
              ),
            if (!ready)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Silnik lokalny nie wystartował na tym telefonie — używaj API.', style: TextStyle(color: AppColors.amberInk)),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        SectionCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.memory, color: AppColors.green),
              title: const Text('Lokalne AI (modele offline)'),
              subtitle: const Text('Pobierz model raz, potem działa bez internetu'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LocalModelsScreen())),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.cloud_outlined, color: AppColors.green),
              title: const Text('Dostawca API'),
              subtitle: Text(ai.api.model.isEmpty ? 'Nie skonfigurowano' : ai.api.model),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiProviderScreen())),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        SectionCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.upload_file, color: AppColors.green),
            title: const Text('Importuj produkty z CSV'),
            subtitle: const Text('nazwa; marka; kcal; białko; węgle; tłuszcz; porcja g; na (100g/porcja); kod'),
            onTap: () => _importCsv(context, ref),
          ),
        ),
        const SizedBox(height: 8),
        SectionCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.ios_share, color: AppColors.green),
              title: const Text('Zrób kopię zapasową'),
              subtitle: const Text('Plik JSON z wpisami, przepisami, wagą i produktami'),
              onTap: () => _backup(context, ref),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.restore, color: AppColors.green),
              title: const Text('Przywróć z kopii'),
              subtitle: const Text('Zastąpi wpisy, przepisy i wagę'),
              onTap: () => _restore(context, ref),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        const Text('Dietownik 1.0 · dane trzymane tylko na telefonie. Wartości oznaczone „~” są szacunkowe. Produkty z kodami: © uczestnicy Open Food Facts, licencja ODbL.',
            style: TextStyle(color: AppColors.muted, fontSize: 12)),
      ],
    );
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

Future<void> _restore(BuildContext context, WidgetRef ref) async {
  final pick = await FilePicker.pickFiles(type: FileType.any);
  final path = pick.isEmpty ? null : pick.first.path;
  if (path == null || !context.mounted) return;
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
  if (ok != true) return;
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
  } catch (e) {
    if (context.mounted) toast(context, 'Nie udało się przywrócić: $e');
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
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        SwitchListTile(
          secondary: const Icon(Icons.notifications_outlined, color: AppColors.green),
          title: const Text('Przypomnienia o posiłkach'),
          subtitle: const Text('Tylko gdy posiłku jeszcze nie zapisałeś'),
          value: prefs.enabled,
          onChanged: (v) async {
            final ok = await ctrl.set(prefs.copyWith(enabled: v));
            if (!ok && context.mounted) toast(context, 'Brak zgody na powiadomienia. Włącz ją w ustawieniach telefonu.');
          },
        ),
        if (prefs.enabled)
          for (var i = 0; i < 3; i++)
            ListTile(
              dense: true,
              title: Text(names[i]),
              trailing: Text(fmt(prefs.slots[i]), style: mono(size: 16)),
              onTap: () async {
                final t = await showTimePicker(
                    context: context, initialTime: TimeOfDay(hour: prefs.slots[i] ~/ 60, minute: prefs.slots[i] % 60));
                if (t == null) return;
                final slots = [...prefs.slots]..[i] = t.hour * 60 + t.minute;
                await ctrl.set(prefs.copyWith(slots: slots));
              },
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
        const Eyebrow('POLICZ ZA MNIE'),
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
        const Eyebrow('TWOJE CELE'),
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
