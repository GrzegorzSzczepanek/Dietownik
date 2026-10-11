import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_settings.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'common.dart';
import 'widgets.dart';

const _tips = [
  ('Nie licz idealnie', 'Wpis na oko jest lepszy niż brak wpisu. Dokładność przyjdzie sama.'),
  ('Jedz to samo często', 'Trzy–cztery stałe śniadania i obiady = jeden tap z „Zwykle jesz”.'),
  ('Białko najpierw', 'Zacznij od źródła białka — sycisz się dłużej i mniej podjadasz.'),
  ('Zrób dwie porcje', 'Gotujesz raz, jesz dwa razy. Mniej decyzji, mniej zmywania.'),
  ('Wpisuj od razu', 'Powiedz do mikrofonu zaraz po jedzeniu — 5 sekund, zanim zapomnisz.'),
  ('Dziura w logu? Zero dramatu', 'Pominięty dzień nic nie psuje. Wróć do następnego posiłku.'),
];

const _prompts = [
  'Co zjeść teraz?',
  'Szybka kolacja bez gotowania',
  'Mam ochotę na słodkie — co zamiast?',
  'Jak nie podjadać wieczorem?',
  'Plan jedzenia na jutro pod moje kalorie',
  'Podsumuj mój tydzień',
];

class AdviceScreen extends ConsumerStatefulWidget {
  const AdviceScreen({super.key, this.standalone = false, this.autoAsk});
  final bool standalone;
  final String? autoAsk;
  @override
  ConsumerState<AdviceScreen> createState() => _AdviceScreenState();
}

class _AdviceScreenState extends ConsumerState<AdviceScreen> {
  final _q = TextEditingController();
  String? _answer, _asked;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoAsk != null) WidgetsBinding.instance.addPostFrameCallback((_) => _ask(widget.autoAsk!));
  }

  Future<String> _context() async {
    final goals = ref.read(goalsProvider);
    final entries = await ref.read(dbProvider).entriesFor(dayKey(DateTime.now()));
    final t = entries.fold(Macros.zero, (a, e) => a + e.macros);
    final hour = DateTime.now().hour;
    final wk = await ref.read(dbProvider).macrosByDay(dayKey(DateTime.now().subtract(const Duration(days: 6))), dayKey(DateTime.now()));
    final wkLine = wk.isEmpty
        ? 'Ostatnie 7 dni: brak wpisów.'
        : 'Ostatnie 7 dni (kcal/dzień z wpisów): ${wk.entries.map((e) => '${e.key}: ${n0(e.value.kcal)}').join(', ')}.';
    return '$wkLine\nGodzina: $hour:00. Cel dzienny: ${n0(goals.kcal)} kcal, B ${n0(goals.p)} g, W ${n0(goals.c)} g, T ${n0(goals.f)} g.\n'
        'Zjedzone dziś: ${n0(t.kcal)} kcal, B ${n0(t.p)}, W ${n0(t.c)}, T ${n0(t.f)}. '
        'Zostało: ${n0(goals.kcal - t.kcal)} kcal, B ${n0(goals.p - t.p)} g.\n'
        'Zjedzone: ${entries.map((e) => e.name).join(', ')}';
  }

  Future<void> _ask(String q) async {
    if (q.trim().isEmpty) return;
    final ai = await ref.read(aiSettingsProvider.notifier).dietAi();
    setState(() { _asked = q; _answer = null; _busy = true; });
    if (!ai.canRun(AiTask.advice)) {
      setState(() { _busy = false; _answer = 'Do porad potrzebuję AI. Wejdź w Ja → Dostawca API (szybkie, wystarczy klucz) albo Lokalne AI (offline, wymaga pobrania modelu).'; });
      return;
    }
    try {
      final a = await ai.advise(q, await _context());
      if (mounted) setState(() { _answer = a.trim(); _busy = false; });
    } catch (e) {
      if (mounted) setState(() { _answer = 'Nie udało się: $e'; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        if (!widget.standalone) const Text('Porady', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        TextField(
          controller: _q,
          textInputAction: TextInputAction.send,
          decoration: InputDecoration(hintText: 'Zapytaj o cokolwiek…', suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: () => _ask(_q.text))),
          onSubmitted: _ask,
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final p in _prompts) ActionChip(label: Text(p), onPressed: () { _q.text = p; _ask(p); })]),
        const SizedBox(height: 16),
        if (_busy) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (_answer != null)
          SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Eyebrow(_asked ?? ''),
            const SizedBox(height: 8),
            SelectableText(_answer!, style: const TextStyle(fontSize: 16, height: 1.45)),
          ])),
        const SizedBox(height: 20),
        const Eyebrow('Małe zasady dla leniwego mózgu'),
        const SizedBox(height: 8),
        for (final t in _tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SectionCard(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 2),
                Text(t.$2, style: TextStyle(color: AppColors.muted, height: 1.35)),
              ]),
            ),
          ),
      ],
    );
    return widget.standalone ? Scaffold(appBar: AppBar(title: const Text('Co zjeść?')), body: body) : body;
  }
}
