import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../domain/shopping_parser.dart';
import '../providers.dart';
import 'common.dart';
import 'dictation.dart';
import 'widgets.dart';

/// Zakupy per design/Zakupy: hero with the open-item count, flat checklist, "Kupione" below.
class ShoppingScreen extends ConsumerStatefulWidget {
  const ShoppingScreen({super.key});
  @override
  ConsumerState<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends ConsumerState<ShoppingScreen> {
  final _input = TextEditingController();

  bool _done(String s) => s.startsWith('1|');
  String _text(String s) => s.length > 2 ? s.substring(2) : s;

  void _addText(String text) {
    final items = parseShoppingCommand(text) ?? splitShoppingItems(text);
    if (items.isEmpty) return;
    ref.read(shoppingProvider.notifier).add([for (final x in items) '0|$x']);
    toast(context, 'Dodano: ${items.join(', ')}');
  }

  void _add() {
    final text = _input.text;
    _addText(text);
    _input.clear();
  }

  Future<void> _dictate() async {
    final t = await showDictation(context, hint: 'Powiedz np. „jajka, ser, masło”');
    if (t != null && mounted) _addText(t);
  }

  void _toggle(String it, bool done) {
    final items = ref.read(shoppingProvider);
    ref.read(shoppingProvider.notifier).replace([for (final e in items) e == it ? '${done ? 1 : 0}|${_text(it)}' : e]);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(shoppingProvider);
    final open = items.where((e) => !_done(e)).toList();
    final bought = items.where(_done).toList();
    Widget row(String it, {required bool first, required bool last}) {
      final done = _done(it);
      return InkWell(
        onTap: () => _toggle(it, !done),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          decoration: BoxDecoration(border: Border(top: first && !done ? BorderSide.none : BorderSide(color: AppColors.line), bottom: last && done ? BorderSide(color: AppColors.line) : BorderSide.none)),
          child: Row(children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: done,
                activeColor: AppColors.accent,
                checkColor: AppColors.onAccent,
                side: BorderSide(color: AppColors.outline, width: 2),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => _toggle(it, v == true),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(_text(it),
                  style: fig(17, weight: done ? 400 : 600, color: done ? AppColors.text2 : AppColors.text).copyWith(decoration: done ? TextDecoration.lineThrough : null)),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListView(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 32), children: [
        HeroZone(
          bottom: 20,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const HeroBackHeader('Zakupy'),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text('${open.length}', style: display(72)),
              const SizedBox(width: 10),
              Text('do kupienia', style: fig(17, weight: 600)),
            ]),
            const SizedBox(height: 14),
            HeroField(
              controller: _input,
              hint: 'np. jajka, ser, masło',
              onSubmitted: (_) => _add(),
              actions: [
                IconButton(tooltip: 'Dodaj głosem', icon: Icon(Icons.mic, color: AppColors.accent), onPressed: _dictate),
                AccentSquareButton(onTap: _add, icon: Icons.add, semantics: 'Dodaj do listy'),
              ],
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('Pusto. Powiedz „zakupy jajka, ser, masło” do mikrofonu albo dodaj brakujące składniki z przepisu.',
                    style: fig(16, color: AppColors.text3, height: 24 / 16)),
              ),
            for (var i = 0; i < open.length; i++) row(open[i], first: i == 0, last: i == open.length - 1),
            if (bought.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Kupione', style: fig(16, weight: 700, color: AppColors.text3)),
              const SizedBox(height: 4),
              for (var i = 0; i < bought.length; i++) row(bought[i], first: i == 0, last: i == bought.length - 1),
              Align(
                alignment: Alignment.centerLeft,
                child: Transform.translate(
                  offset: const Offset(-12, 0),
                  child: TextButton(
                    onPressed: () => ref.read(shoppingProvider.notifier).replace(open),
                    child: const Text('Usuń kupione'),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
