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
import '../speech_helper.dart';
import 'api_provider_screen.dart';
import 'common.dart';
import 'edit_entry_sheet.dart';

Future<void> showVoiceSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      barrierColor: const Color(0xFF17201C).withValues(alpha: 0.5),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
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
  String? _parseError;
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
          _stt.cancel();
          setState(() => _error = speechErrorText(e.errorMsg));
        }
      },
    );
    if (!ok) {
      if (mounted) {
        setState(() {
          _phase = _Phase.typing;
          _error = speechUnavailableText;
        });
      }
      return;
    }
    final locale = await pickPolishLocale(_stt);
    await _stt.listen(
      onResult: (r) {
        if (!mounted) return;
        setState(() => _heard = r.recognizedWords);
        if (r.finalResult && _heard.trim().isNotEmpty) _submit(_heard);
      },
      listenOptions: SpeechListenOptions(
        localeId: locale,
        partialResults: true,
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(seconds: 60),
      ),
    );
  }

  Future<void> _stopAndSubmit() async {
    // After an error the big button simply tries again.
    if (_error != null) {
      await _start();
      return;
    }
    await _stt.stop();
    if (_heard.trim().isNotEmpty) {
      _submit(_heard);
    } else {
      setState(() => _error = speechErrorText('brak nagrania'));
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
        _parseError = r.parseError;
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
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + inset + bottomSafe),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(2)))),
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
        const SizedBox(height: 24),
        Center(child: Text('Słucham…', style: fig(16, weight: 600, color: AppColors.accent))),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 116),
          child: Center(
            child: Text(_heard.isEmpty ? 'Powiedz, co zjadłeś' : _heard,
                textAlign: TextAlign.center,
                style: display(30, weight: 700, height: 38 / 30, color: _heard.isEmpty ? AppColors.text2 : AppColors.text)),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: SizedBox(
            width: 144,
            height: 144,
            child: Stack(alignment: Alignment.center, children: [
              Container(decoration: BoxDecoration(color: AppColors.hero, shape: BoxShape.circle)),
              Positioned.fill(
                  child: Padding(padding: const EdgeInsets.all(18), child: Container(decoration: BoxDecoration(color: AppColors.track, shape: BoxShape.circle)))),
              Semantics(
                button: true,
                label: 'Skończyłem mówić',
                child: GestureDetector(
                  onTap: _stopAndSubmit,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                    child: Icon(Icons.mic, color: AppColors.onAccent, size: 40),
                  ),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Center(child: Text(_error ?? 'Dotknij mikrofon, gdy skończysz', style: fig(15, color: _error == null ? AppColors.text3 : AppColors.warn))),
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            onPressed: () { _stt.cancel(); setState(() => _phase = _Phase.typing); },
            icon: const Icon(Icons.keyboard_outlined),
            label: const Text('Wolę wpisać'),
          ),
        ),
      ];

  List<Widget> _working() => [
        const SizedBox(height: 40),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 20),
        Center(child: Text('Liczę: „$_heard”', textAlign: TextAlign.center, style: fig(16, color: AppColors.text3))),
        const SizedBox(height: 40),
      ];

  List<Widget> _typing() => [
        const SizedBox(height: 20),
        Text('Co zjadłeś?', style: display(26)),
        const SizedBox(height: 12),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: fig(14, weight: 600, color: AppColors.warn))),
        TextField(
          controller: _text,
          autofocus: true,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: '2 jajka, kanapka z serem, kawa z mlekiem'),
          onSubmitted: (v) { if (v.trim().isNotEmpty) { _heard = v; _submit(v); } },
        ),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: () { final v = _text.text.trim(); if (v.isNotEmpty) { _heard = v; _submit(v); } },
            child: const Text('Dodaj')),
        Center(child: TextButton.icon(onPressed: _start, icon: const Icon(Icons.mic_none), label: const Text('Użyj mikrofonu'))),
      ];

  /// Opens the full edit sheet (amount in pieces or grams, meal, source) and refreshes the row.
  Future<void> _editRow(Entry e) async {
    await showEditEntry(context, e);
    if (!mounted || e.id == null) return;
    final fresh = await ref.read(dbProvider).entryById(e.id!);
    setState(() {
      _saved = [
        for (final x in _saved)
          if (x.id != e.id) x else ?fresh
      ];
    });
  }

  Widget _resultRow(Entry e, {required bool last}) {
    final unknown = e.macros.kcal == 0;
    return InkWell(
      onTap: unknown ? () => _estimateEntry(e) : () => _editRow(e),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line), bottom: last ? BorderSide(color: AppColors.line) : BorderSide.none)),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(e.name, style: fig(16, weight: 600)),
              Text(unknown ? 'Brak wartości, dotknij, żeby oszacować AI' : '${n0(e.grams)} g · ${macroText(e.macros)}',
                  style: fig(14, color: unknown ? AppColors.warn : AppColors.text2)),
              if (!unknown && e.source.isNotEmpty)
                Text(_shortSource(e.source), maxLines: 1, overflow: TextOverflow.ellipsis, style: fig(12, color: AppColors.text2)),
            ]),
          ),
          if (unknown)
            TextButton(onPressed: () => _estimateEntry(e), child: const Text('Oszacuj AI'))
          else
            Text('${e.estimated ? '~' : ''}${n0(e.macros.kcal)}', style: fig(18, weight: 600)),
        ]),
      ),
    );
  }

  String _shortSource(String s) => s.startsWith('http') ? 'Źródło: ${Uri.tryParse(s)?.host.replaceFirst('www.', '') ?? s}' : 'Źródło: $s';

  List<Widget> _done() {
    final shopped = _shopped;
    if (shopped != null) {
      return [
        const SizedBox(height: 20),
        Row(children: [
          Icon(Icons.shopping_cart_outlined, color: AppColors.accent, size: 28),
          const SizedBox(width: 10),
          Expanded(child: Text(shopped.isEmpty ? 'Nie usłyszałem, co kupić' : 'Dodano do zakupów (${shopped.length})', style: display(26))),
        ]),
        const SizedBox(height: 12),
        for (var i = 0; i < shopped.length; i++)
          Container(
            height: 52,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line), bottom: i == shopped.length - 1 ? BorderSide(color: AppColors.line) : BorderSide.none)),
            child: Text(shopped[i], style: fig(16, weight: 600)),
          ),
        const SizedBox(height: 20),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Gotowe')),
        Center(child: TextButton(onPressed: () { _shopped = null; _start(); }, child: const Text('Dodaj jeszcze'))),
      ];
    }
    final total = _saved.fold(Macros.zero, (a, e) => a + e.macros);
    final meal = _saved.isEmpty ? null : const ['śniadania', 'obiadu', 'kolacji', 'przekąsek'][_saved.first.meal];
    return [
      const SizedBox(height: 20),
      if (_saved.isEmpty)
        Text('Nic nie rozpoznałem', style: display(26))
      else
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(n0(total.kcal), style: display(56)),
          const SizedBox(width: 10),
          Flexible(child: Text('kcal dodane do $meal', style: fig(17, weight: 600))),
        ]),
      const SizedBox(height: 12),
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
        child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
          for (var i = 0; i < _saved.length; i++) _resultRow(_saved[i], last: i == _saved.length - 1),
        ]),
      ),
      const SizedBox(height: 12),
      Text.rich(TextSpan(style: fig(14, color: AppColors.text3, height: 20 / 14), children: [
        const TextSpan(text: 'Dotknij pozycję, żeby zmienić ilość (sztuki lub gramy).'),
        if (!_usedAi && _parseError != null)
          TextSpan(text: ' AI nie odpowiedziało ($_parseError), więc użyłem trybu prostego.')
        else if (!_usedAi) ...[
          const TextSpan(text: ' Bez AI zdania rozumiem słabo. '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiProviderScreen()));
              },
              child: Text('Podłącz AI', style: fig(14, weight: 600, color: AppColors.warn)),
            ),
          ),
        ],
      ])),
      const SizedBox(height: 20),
      FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Gotowe')),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        TextButton(onPressed: _start, child: const Text('Dodaj jeszcze')),
        const SizedBox(width: 8),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: AppColors.text3),
          onPressed: _undo,
          icon: const Icon(Icons.undo, size: 18),
          label: const Text('Cofnij wszystko'),
        ),
      ]),
    ];
  }
}
