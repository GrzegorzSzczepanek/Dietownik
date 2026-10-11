import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/chat_ai.dart';
import '../chat_controller.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'chat_access_screen.dart';
import 'common.dart';
import 'state_screens.dart';
import 'widgets.dart';

const _starters = [
  'Co zjeść na kolację, żeby domknąć białko?',
  'Szybki obiad z tego, co mam w lodówce',
  'Mam ochotę na słodkie, co zamiast?',
  'Plan jedzenia na jutro pod moje kalorie',
  'Podsumuj mój tydzień',
];

/// Czat per design/Porady, Czat-rozmowa, Czat-zrodla: start screen with prompts, then a conversation
/// with numbered web sources, a recipe card and follow-up chips.
class AdviceScreen extends ConsumerStatefulWidget {
  const AdviceScreen({super.key});
  @override
  ConsumerState<AdviceScreen> createState() => _AdviceScreenState();
}

class _AdviceScreenState extends ConsumerState<AdviceScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty) return;
    final ai = await ref.read(aiSettingsProvider.notifier).dietAi();
    if (!ai.canChat) {
      if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const AiKeyScreen()));
      return;
    }
    _input.clear();
    final f = ref.read(chatProvider.notifier).send(q);
    _toBottom();
    await f;
    _toBottom();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 200, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final msgs = chat.current;
    final top = MediaQuery.of(context).padding.top;
    return Column(children: [
      Expanded(child: msgs.isEmpty && !chat.busy ? _start(context) : _conversation(context, msgs, chat.busy, top)),
      _bottom(msgs, chat.busy),
    ]);
  }

  // ----------------------------------------------------------- start

  Widget _start(BuildContext context) {
    final goals = ref.watch(goalsProvider);
    final entries = ref.watch(dayEntriesProvider).value ?? const <Entry>[];
    final t = entries.fold(Macros.zero, (a, e) => a + e.macros);
    final web = ref.watch(chatPrefsProvider).web;
    return ListView(padding: EdgeInsets.zero, children: [
      HeroZone(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 52,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Czat', style: fig(18, weight: 700)),
              Transform.translate(
                offset: const Offset(12, 0),
                child: IconButton(
                  tooltip: 'Do czego czat ma dostęp',
                  icon: const Icon(Icons.tune),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatAccessScreen())),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Text('O czym pogadamy?', style: display(36, height: 42 / 36)),
          const SizedBox(height: 10),
          Text(
            '${goals.kcal - t.kcal >= 0 ? 'Znam twój dzień: zostało ${n0(goals.kcal - t.kcal)} kcal i ${n0((goals.p - t.p).clamp(0, 9999))} g białka.' : 'Znam twój dzień: jesteś ${n0(t.kcal - goals.kcal)} kcal ponad plan, to zdarza się każdemu.'} ${web ? 'Szukam też w internecie i podaję źródła.' : 'Szukanie w internecie jest wyłączone.'}',
            style: fig(16, color: AppColors.text3, height: 24 / 16),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(children: [
          for (var i = 0; i < _starters.length; i++)
            InkWell(
              onTap: () => _send(_starters[i]),
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(border: Border(top: i == 0 ? BorderSide.none : BorderSide(color: AppColors.line), bottom: i == _starters.length - 1 ? BorderSide(color: AppColors.line) : BorderSide.none)),
                child: Text(_starters[i], style: fig(16, weight: 600)),
              ),
            ),
        ]),
      ),
    ]);
  }

  // ----------------------------------------------------------- conversation

  Widget _conversation(BuildContext context, List<ChatMsg> msgs, bool busy, double top) {
    final prefs = ref.watch(chatPrefsProvider);
    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(20, top, 8, 0),
        child: SizedBox(
          height: 52,
          child: Row(children: [
            Text('Czat', style: fig(18, weight: 700)),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatAccessScreen())),
              child: Text(prefs.summary, style: fig(14, weight: 600)),
            ),
            IconButton(
              tooltip: 'Nowa rozmowa',
              icon: Icon(Icons.edit_square, color: AppColors.accent),
              onPressed: () => ref.read(chatProvider.notifier).newConversation(),
            ),
          ]),
        ),
      ),
      Expanded(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          children: [
            for (final m in msgs) m.role == 'user' ? _userBubble(m.text) : _assistant(context, m),
            if (busy)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Row(children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  const SizedBox(width: 12),
                  Text(prefs.web ? 'Szukam i myślę…' : 'Myślę…', style: fig(15, color: AppColors.text2)),
                ]),
              ),
          ],
        ),
      ),
    ]);
  }

  Widget _userBubble(String text) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: AppColors.hero, borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(20), bottomRight: Radius.circular(6))),
          child: Text(text, style: fig(16, height: 24 / 16)),
        ),
      );

  /// Text with [n] markers turned into small tappable number badges.
  Widget _cited(BuildContext context, ChatReply r) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\[(\d+)\]');
    var last = 0;
    final text = r.answer;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final n = int.parse(m.group(1)!);
      if (n >= 1 && n <= r.sources.length) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: () => _showSources(context, r),
            child: Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.hero, borderRadius: BorderRadius.circular(10)),
              child: Text('$n', style: fig(12, weight: 700, color: AppColors.accentDeep)),
            ),
          ),
        ));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(children: spans, style: fig(16, height: 24 / 16)));
  }

  Widget _assistant(BuildContext context, ChatMsg m) {
    final r = m.reply ?? ChatReply(answer: m.text);
    final web = ref.watch(chatPrefsProvider).web;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (r.searched && r.sources.isNotEmpty)
        InkWell(
          onTap: () => _showSources(context, r),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.language, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Text('Przeszukałem ${r.sources.length} ${r.sources.length == 1 ? 'stronę' : (r.sources.length < 5 ? 'strony' : 'stron')}', style: fig(14, weight: 600, color: AppColors.accent)),
              ]),
            ),
          ),
        )
      else if (r.searched)
        Padding(padding: const EdgeInsets.only(top: 16), child: Text('Nie znalazłem źródeł w internecie. Odpowiadam z ogólnej wiedzy.', style: fig(13, color: AppColors.text2)))
      else if (!web)
        Padding(padding: const EdgeInsets.only(top: 16), child: Text('Bez szukania w internecie, odpowiedź bez źródeł.', style: fig(13, color: AppColors.text2))),
      const SizedBox(height: 4),
      _cited(context, r),
      if (r.used.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Użyłem: ${r.used.join(', ')}', style: fig(13, color: AppColors.text2, height: 18 / 13))),
      if (r.recipe != null) _RecipeCard(r.recipe!),
      if (r.recipe != null && r.recipe!.missing.isNotEmpty) _MissingRow(r.recipe!.missing),
      if (r.sources.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (var i = 0; i < r.sources.length && i < 2; i++)
              GestureDetector(
                onTap: () => _showSources(context, r),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(22)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${i + 1}', style: fig(14, weight: 700)),
                    const SizedBox(width: 6),
                    Flexible(child: Text(r.sources[i].host, overflow: TextOverflow.ellipsis, style: fig(14))),
                  ]),
                ),
              ),
            if (r.sources.length > 2)
              TextButton(onPressed: () => _showSources(context, r), child: Text('+${r.sources.length - 2}')),
          ]),
        ),
    ]);
  }

  void _showSources(BuildContext context, ChatReply r) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.bg,
        barrierColor: const Color(0xFF17201C).withValues(alpha: 0.5),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        builder: (ctx) => _SourcesSheet(r.sources),
      );

  // ----------------------------------------------------------- input

  Widget _bottom(List<ChatMsg> msgs, bool busy) {
    final prefs = ref.watch(chatPrefsProvider);
    final last = msgs.isEmpty ? null : msgs.last;
    final chips = (last?.role == 'assistant' && !busy) ? (last!.reply?.suggestions ?? const <String>[]) : const <String>[];
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (chips.isNotEmpty)
          SizedBox(
            height: 60,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: chips.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _send(chips[i]),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.outline)),
                  child: Text(chips[i], style: fig(14, weight: 600)),
                ),
              ),
            ),
          )
        else
          const SizedBox(height: 8),
        Container(
          height: 56,
          padding: const EdgeInsets.fromLTRB(4, 0, 6, 0),
          decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(28)),
          child: Row(children: [
            Semantics(
              button: true,
              toggled: prefs.web,
              label: 'Szukanie w internecie: ${prefs.web ? 'włączone' : 'wyłączone'}',
              child: GestureDetector(
                onTap: () => ref.read(chatPrefsProvider.notifier).set(5, !prefs.web),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: prefs.web ? AppColors.track : Colors.transparent, shape: BoxShape.circle),
                  child: Icon(Icons.language, color: prefs.web ? AppColors.accentDeep : AppColors.text2),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _input,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: fig(16, weight: 500),
                decoration: InputDecoration(
                  hintText: msgs.isEmpty ? 'Zapytaj o jedzenie, przepisy, plan' : 'Napisz wiadomość',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Wyślij',
              child: GestureDetector(
                onTap: busy ? null : _send,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: busy ? AppColors.outline : AppColors.accent, shape: BoxShape.circle),
                  child: Icon(Icons.arrow_upward, color: AppColors.onAccent),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _RecipeCard extends ConsumerWidget {
  const _RecipeCard(this.r);
  final ChatRecipe r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final macros = Macros(kcal: r.kcal, p: r.p, c: r.c, f: r.f);
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: AppColors.outline), borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r.title, style: fig(17, weight: 700)),
        const SizedBox(height: 4),
        Text('~${n0(r.kcal)} kcal · B ~${n0(r.p)} g · W ~${n0(r.c)} g · T ~${n0(r.f)} g', style: fig(15)),
        if (r.note.isNotEmpty || r.missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('${r.note.isEmpty ? 'Szacunek, nie z etykiety.' : r.note}${r.missing.isEmpty ? '' : ' Brakuje: ${r.missing.join(', ')}'}', style: fig(13, color: AppColors.text2, height: 18 / 13)),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: () async {
                  final t = DateTime.now();
                  await ref.read(dbProvider).addEntry(Entry(day: dayKey(t), meal: mealForTime(t), name: r.title, grams: 0, macros: macros, estimated: true));
                  ref.read(dataVersionProvider.notifier).bump();
                  if (context.mounted) toast(context, 'Dodano porcję: ${r.title}');
                },
                child: Text('Zjadłem porcję', style: fig(15, weight: 700, color: AppColors.onAccent)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: () async {
                  await ref.read(dbProvider).saveRecipe(Recipe(title: r.title, ingredients: r.ingredients, perServing: macros));
                  ref.read(dataVersionProvider.notifier).bump();
                  if (context.mounted) toast(context, 'Zapisano przepis: ${r.title}');
                },
                child: Text('Zapisz przepis', style: fig(15, weight: 600)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _MissingRow extends ConsumerWidget {
  const _MissingRow(this.missing);
  final List<String> missing;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Brakuje: ${missing.join(', ')}', style: fig(16, weight: 600)),
              Text('Dodać do zakupów?', style: fig(14, color: AppColors.text2)),
            ]),
          ),
          GestureDetector(
            onTap: () {
              ref.read(shoppingProvider.notifier).add([for (final x in missing) '0|$x']);
              toast(context, 'Dodano do zakupów: ${missing.join(', ')}');
            },
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.hero, borderRadius: BorderRadius.circular(12)),
              child: Text('Dodaj', style: fig(14, weight: 700, color: AppColors.accentDeep)),
            ),
          ),
        ]),
      );
}

class _SourcesSheet extends StatelessWidget {
  const _SourcesSheet(this.sources);
  final List<ChatSource> sources;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Źródła (${sources.length})', style: display(28)),
              Transform.translate(offset: const Offset(12, 0), child: IconButton(tooltip: 'Zamknij', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))),
            ]),
            const SizedBox(height: 4),
            Text('Odpowiedź streścił AI. Sprawdź szczegóły na stronie, a kcal i makro traktuj jako szacunek.', style: fig(15, color: AppColors.text3, height: 22 / 15)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                for (var i = 0; i < sources.length; i++)
                  InkWell(
                    onTap: () => launchUrl(Uri.parse(sources[i].url), mode: LaunchMode.externalApplication),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line), bottom: i == sources.length - 1 ? BorderSide(color: AppColors.line) : BorderSide.none)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: AppColors.hero, borderRadius: BorderRadius.circular(14)),
                          child: Text('${i + 1}', style: fig(14, weight: 700, color: AppColors.accentDeep)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(sources[i].title, style: fig(16, weight: 700)),
                            Text(sources[i].host, style: fig(14, color: AppColors.text2)),
                            if (sources[i].snippet.isNotEmpty)
                              Padding(padding: const EdgeInsets.only(top: 2), child: Text(sources[i].snippet, maxLines: 3, overflow: TextOverflow.ellipsis, style: fig(14, color: AppColors.text3))),
                          ]),
                        ),
                        Icon(Icons.open_in_new, size: 20, color: AppColors.text2),
                      ]),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            Text('Bez internetu albo z wyłączonym globusem odpowiem bez źródeł i zaznaczę to w wiadomości.', style: fig(14, color: AppColors.text2, height: 20 / 14)),
          ]),
        ),
      );
}
