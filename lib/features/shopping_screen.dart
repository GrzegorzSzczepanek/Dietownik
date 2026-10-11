import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

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
          decoration: InputDecoration(hintText: 'Dodaj do listy…', suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _add)),
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
    ref.read(shoppingProvider.notifier).add([for (final x in _input.text.split(RegExp(r'[,;\n]'))) if (x.trim().isNotEmpty) '0|${x.trim()}']);
    _input.clear();
  }
}
