import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../domain/models.dart';

String n0(double v) => v.round().toString();
String n1(double v) => v.toStringAsFixed(v >= 10 ? 0 : 1);

String macroText(Macros m) => 'B ${n0(m.p)} · W ${n0(m.c)} · T ${n0(m.f)}';

/// Asks for an amount in grams, pre-filled with the food's usual serving.
Future<double?> askGrams(BuildContext context, Food food, {double? initial}) {
  final ctrl = TextEditingController(text: n0(initial ?? food.servingG));
  return showDialog<double>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final g = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
      final m = food.per(g);
      return AlertDialog(
        title: Text(food.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Ilość (g / ml)', suffixText: 'g'),
            onChanged: (_) => set(() {}),
          ),
          if (food.servingLabel.isNotEmpty) ...[
            const SizedBox(height: 8),
            ActionChip(
              label: Text('${food.servingLabel} = ${n0(food.servingG)} g'),
              onPressed: () => set(() => ctrl.text = n0(food.servingG)),
            ),
          ],
          const SizedBox(height: 12),
          Text('${n0(m.kcal)} kcal', style: mono(size: 22)),
          Text(macroText(m), style: const TextStyle(color: AppColors.muted)),
          if (food.estimated)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('~ wartości szacunkowe', style: TextStyle(color: AppColors.amber)),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
            onPressed: g > 0 ? () => Navigator.pop(ctx, g) : null,
            child: const Text('Dodaj'),
          ),
        ],
      );
    }),
  );
}

void toast(BuildContext context, String msg, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), action: action, duration: const Duration(seconds: 4)));
}
