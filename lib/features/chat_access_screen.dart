import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat_controller.dart';
import '../core/theme.dart';
import 'widgets.dart';

/// Czat-prywatnosc: which parts of the app the chat may read.
class ChatAccessScreen extends ConsumerWidget {
  const ChatAccessScreen({super.key});

  static const _rows = [
    ('Dzisiejszy bilans', 'Kalorie i makro z dziś'),
    ('Historia wpisów', 'Ostatnie 90 dni, z godzinami'),
    ('Cele i statystyki', 'Cel dzienny, średnie, woda'),
    ('Lodówka i zakupy', 'Co masz i czego brakuje'),
    ('Zapisane przepisy', 'Własne i zaimportowane'),
    ('Szukanie w internecie', 'Wysyłam tylko samo pytanie'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(chatPrefsProvider);
    final values = prefs.all;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListView(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 32), children: [
        HeroZone(
          bottom: 20,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const HeroBackHeader('Czat', size: 15),
            const SizedBox(height: 4),
            Text('Do czego czat ma dostęp?', style: display(30, height: 34 / 30)),
            const SizedBox(height: 8),
            Text('Domyślnie do wszystkiego z aplikacji, żeby radził na twoich danych. Każde źródło wyłączysz.', style: fig(16, color: AppColors.text3, height: 24 / 16)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < _rows.length; i++)
              Container(
                constraints: const BoxConstraints(minHeight: 64),
                decoration: BoxDecoration(border: Border(top: i == 0 ? BorderSide.none : BorderSide(color: AppColors.line), bottom: i == _rows.length - 1 ? BorderSide(color: AppColors.line) : BorderSide.none)),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_rows[i].$1, style: fig(16, weight: 700)),
                      Text(_rows[i].$2, style: fig(14, color: AppColors.text2)),
                    ]),
                  ),
                  Switch(value: values[i], onChanged: (v) => ref.read(chatPrefsProvider.notifier).set(i, v)),
                ]),
              ),
            const SizedBox(height: 12),
            Text('Wybrane dane trafiają do dostawcy AI razem z pytaniem. Rozmowy zostają tylko na telefonie.', style: fig(14, color: AppColors.text2, height: 20 / 14)),
            InkWell(
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Usunąć historię czatu?'),
                    content: const Text('Wszystkie rozmowy znikną z telefonu. Tego nie da się cofnąć.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
                      TextButton(style: TextButton.styleFrom(foregroundColor: AppColors.fat), onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref.read(chatProvider.notifier).clearAll();
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(alignment: Alignment.centerLeft, child: Text('Usuń historię czatu', style: fig(16, weight: 600, color: AppColors.fat))),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
