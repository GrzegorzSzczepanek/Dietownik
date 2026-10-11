import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/theme.dart';
import '../ai/ai_settings.dart';
import '../ai/diet_ai.dart';
import '../domain/meal_resolver.dart';
import '../domain/models.dart';
import '../domain/shopping_parser.dart';
import '../providers.dart';
import 'common.dart';

Future<void> showVoiceSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _VoiceSheet(),
    );

enum _Phase { listening, working, done, typing }

class _VoiceSheet extends ConsumerStatefulWidget {
  const _VoiceSheet();
  @override
  ConsumerState<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends ConsumerState<_VoiceSheet> {
  final _stt = SpeechToText();
  final _text = TextEditingController();
  _Phase _phase = _Phase.listening;
  String _heard = '';
  String? _error;
  List<Entry> _saved = [];
  bool _usedAi = true;
  List<String>? _shopped;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _stt.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.listening;
      _heard = '';
      _error = null;
    });
    final ok = await _stt.initialize(
      onError: (e) {
        if (!mounted || _phase != _Phase.listening) return;
        if (_heard.trim().isNotEmpty) {
          _submit(_heard);
        } else {
          setState(() => _error = 'Nie usłyszałem nic. Spróbuj jeszcze raz albo wpisz.');
        }
      },
    );
    if (!ok) {
      if (mounted) {
        setState(() {
          _phase = _Phase.typing;
          _error = 'Rozpoznawanie mowy niedostępne (sprawdź zgodę na mikrofon). Wpisz posiłek.';
        });
      }
      return;
    }
    await _stt.listen(
      onResult: (r) {
        if (!mounted) return;
        setState(() => _heard = r.recognizedWords);
        if (r.finalResult && _heard.trim().isNotEmpty) _submit(_heard);
      },
      listenOptions: SpeechListenOptions(
          localeId: 'pl_PL', partialResults: true, pauseFor: const Duration(seconds: 3), listenFor: const Duration(seconds: 45)),
    );
  }

  Future<void> _stopAndSubmit() async {
    await _stt.stop();
    if (_heard.trim().isNotEmpty) {
      _submit(_heard);
    } else {
      setState(() => _error = 'Nic nie nagrałem. Dotknij mikrofon i mów.');
    }
  }

  Future<void> _submit(String text) async {
    if (_phase == _Phase.working || _phase == _Phase.done) return;
    final shop = parseShoppingCommand(text);
    if (shop != null) {
      if (shop.isNotEmpty) await ref.read(shoppingProvider.notifier).add([for (final x in shop) '0|$x']);
      if (!mounted) return;
      setState(() {
        _shopped = shop;
        _phase = _Phase.done;
      });
      return;
    }
    setState(() => _phase = _Phase.working);
    try {
      final r = await ref
          .read(foodLoggerProvider)
          .logText(text, when: ref.read(selectedDayProvider));
      if (!mounted) return;
      setState(() {
        _saved = r.entries;
        _usedAi = r.usedAi;
        _phase = _Phase.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.typing;
        _error = 'Coś poszło nie tak: $e';
        _text.text = text;
      });
    }
  }

  /// Fills in an entry the lookup missed: web search + AI, else tells how to enable it.
  Future<void> _estimateEntry(Entry e) async {
    final ai = await ref.read(aiSettingsProvider.notifier).dietAi();
    if (!ai.canRun(AiTask.estimation)) {
      if (mounted) toast(context, 'Podłącz AI (Ja → Dostawca API), a policzę to za Ciebie.');
      return;
    }
    final db = ref.read(dbProvider);
    final r = await MealResolver(db: db, off: ref.read(offProvider), ai: ai)
        .resolve(ParsedItem(e.name, grams: e.grams > 0 ? e.grams : null));
    if (r.unknown) {
      if (mounted) toast(context, 'Nie udało się znaleźć wartości. Dotknij wpis na ekranie Dziś i wpisz ręcznie.');
      return;
    }
    final fixed = Entry(id: e.id, day: e.day, meal: e.meal, name: e.name, grams: r.grams.roundToDouble(), macros: r.macros, estimated: true);
    await db.updateEntry(fixed);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) setState(() => _saved = [for (final x in _saved) x.id == e.id ? fixed : x]);
  }

  Future<void> _undo() async {
    final db = ref.read(dbProvider);
    for (final e in _saved) {
      if (e.id != null) await db.deleteEntry(e.id!);
    }
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + inset),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(9))),
        const SizedBox(height: 16),
        ...switch (_phase) {
          _Phase.listening => _listening(),
          _Phase.working => _working(),
          _Phase.done => _done(),
          _Phase.typing => _typing(),
        },
      ]),
    );
  }

  List<Widget> _listening() => [
        GestureDetector(
          onTap: _stopAndSubmit,
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
            child: Icon(Icons.mic, color: AppColors.onAccent, size: 54),
          ),
        ),
        const SizedBox(height: 16),
        Text(_heard.isEmpty ? 'Słucham… powiedz, co zjadłeś' : _heard,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w600, color: _heard.isEmpty ? AppColors.muted : AppColors.ink)),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: AppColors.amber))),
        const SizedBox(height: 8),
        Text('Dotknij mikrofon, gdy skończysz', style: TextStyle(color: AppColors.muted)),
        TextButton(onPressed: () { _stt.cancel(); setState(() => _phase = _Phase.typing); }, child: const Text('Wolę wpisać')),
      ];

  List<Widget> _working() => [
        const SizedBox(height: 24),
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text('Liczę: „$_heard”', textAlign: TextAlign.center),
        const SizedBox(height: 24),
      ];

  List<Widget> _typing() => [
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: AppColors.amber))),
        TextField(
          controller: _text,
          autofocus: true,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: '2 jajka, kanapka z serem, kawa z mlekiem'),
          onSubmitted: (v) { if (v.trim().isNotEmpty) { _heard = v; _submit(v); } },
        ),
        const SizedBox(height: 12),
        FilledButton(
            onPressed: () { final v = _text.text.trim(); if (v.isNotEmpty) { _heard = v; _submit(v); } },
            child: const Text('Dodaj')),
        TextButton(onPressed: _start, child: const Text('Użyj mikrofonu')),
      ];

  List<Widget> _done() {
    final shopped = _shopped;
    if (shopped != null) {
      return [
        Row(children: [
          Icon(Icons.shopping_cart, color: AppColors.green, size: 28),
          const SizedBox(width: 8),
          Expanded(child: Text(shopped.isEmpty ? 'Nie usłyszałem, co kupić' : 'Dodano do zakupów (${shopped.length})', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [for (final x in shopped) Chip(label: Text(x))]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () { _shopped = null; _start(); }, child: const Text('Dodaj jeszcze'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Gotowe'))),
        ]),
      ];
    }
    final total = _saved.fold(Macros.zero, (a, e) => a + e.macros);
    final unknown = _saved.where((e) => e.macros.kcal == 0).toList();
    return [
      Row(children: [
        Icon(Icons.check_circle, color: AppColors.green, size: 28),
        const SizedBox(width: 8),
        Expanded(child: Text(_saved.isEmpty ? 'Nic nie rozpoznałem' : 'Dodano ${_saved.length} poz. · ${n0(total.kcal)} kcal',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
      ]),
      const SizedBox(height: 8),
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
        child: ListView(shrinkWrap: true, children: [
          for (final e in _saved)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(e.name),
              subtitle: Text('${n0(e.grams)} g · ${macroText(e.macros)}'),
              trailing: e.macros.kcal == 0
                  ? TextButton(onPressed: () => _estimateEntry(e), child: const Text('Oszacuj AI'))
                  : Text('${e.estimated ? '~' : ''}${n0(e.macros.kcal)}', style: figure(size: 15)),
            ),
        ]),
      ),
      if (unknown.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Brak wartości dla: ${unknown.map((e) => e.name).join(', ')}. Dotknij „Oszacuj AI” przy pozycji.',
              style: TextStyle(color: AppColors.amberInk, fontSize: 13)),
        ),
      if (!_usedAi)
        Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Tryb prosty (bez AI) słabo rozumie całe zdania. Podłącz AI w Ja → Dostawca API (np. DeepSeek), a zadziała jak trzeba.',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: _undo, child: const Text('Cofnij'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton(onPressed: () { _start(); }, child: const Text('Dodaj jeszcze'))),
        const SizedBox(width: 8),
        Expanded(child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Gotowe'))),
      ]),
    ];
  }
}
