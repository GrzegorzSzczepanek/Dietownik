import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';

import '../domain/shopping_parser.dart';
import '../providers.dart';
import 'common.dart';
import 'dictation.dart';

class ShoppingScreen extends ConsumerStatefulWidget {
  const ShoppingScreen({super.key});
  @override
  ConsumerState<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends ConsumerState<ShoppingScreen> {
  final _input = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(shoppingProvider);
    final n = ref.read(shoppingProvider.notifier);
    bool done(String s) => s.startsWith('1|');
    String text(String s) => s.length > 2 ? s.substring(2) : s;
    return Scaffold(
      appBar: AppBar(title: const Text('Zakupy'), actions: [
        if (items.any(done))
          TextButton(onPressed: () => n.replace(items.where((e) => !done(e)).toList()), child: const Text('Usuń kupione')),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
        TextField(
          controller: _input,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'np. jajka, ser, masło',
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.mic, color: AppColors.green), onPressed: _dictate),
              IconButton(icon: const Icon(Icons.add), onPressed: _add),
            ]),
          ),
          onSubmitted: (_) => _add(),
        ),
        if (items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Pusto. Dodaj brakujące składniki z przepisu albo z „Co mam w lodówce”.', textAlign: TextAlign.center)),
        for (final it in items)
          CheckboxListTile(
            value: done(it),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(text(it), style: TextStyle(decoration: done(it) ? TextDecoration.lineThrough : null)),
            onChanged: (v) => n.replace([for (final e in items) e == it ? '${v == true ? 1 : 0}|${text(it)}' : e]),
          ),
      ]),
    );
  }

  void _add() {
    final text = _input.text;
    _addText(text);
    _input.clear();
  }

  void _addText(String text) {
    final items = parseShoppingCommand(text) ?? splitShoppingItems(text);
    if (items.isEmpty) return;
    ref.read(shoppingProvider.notifier).add([for (final x in items) '0|$x']);
    toast(context, 'Dodano: ${items.join(', ')}');
  }

  Future<void> _dictate() async {
    final t = await showDictation(context, hint: 'Powiedz np. „jajka, ser, masło”');
    if (t != null && mounted) _addText(t);
  }
}
