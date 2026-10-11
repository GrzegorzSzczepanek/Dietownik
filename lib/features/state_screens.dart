import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers.dart';
import 'api_provider_screen.dart';
import 'oko_screen.dart';
import 'usage_screen.dart';
import 'widgets.dart';

/// Designed empty/error states, per design/Offline and design/Blad-ai.
class OfflineScreen extends ConsumerWidget {
  const OfflineScreen({super.key, this.url, required this.onRetry});

  /// Link that failed to import; offered for later.
  final String? url;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        backgroundColor: AppColors.bg,
        body: Stack(children: [
          ListView(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 110), children: [
            HeroZone(
              bottom: 28,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const HeroBackHeader('Importuj przepis', size: 15),
                const SizedBox(height: 8),
                Text('Nie mam teraz internetu.', style: display(36, height: 40 / 36)),
                const SizedBox(height: 12),
                Text('Import z linku i czat z wyszukiwaniem potrzebują sieci. Reszta działa jak zawsze.', style: fig(17, color: AppColors.text3, height: 26 / 17)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(children: [
                NavRow(topLine: false, bold: true, minHeight: 72, title: 'Zapisz posiłek z listy', subtitle: 'Twoje produkty są na telefonie', onTap: () => Navigator.of(context).popUntil((r) => r.isFirst)),
                NavRow(bold: true, minHeight: 72, title: 'Wpis na oko', subtitle: 'Szybkie kalorie bez szukania', onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const OkoScreen()))),
                if (url != null)
                  NavRow(
                    bold: true,
                    minHeight: 72,
                    bottomLine: true,
                    title: 'Zapamiętaj link na później',
                    subtitle: 'Zaimportuję go, gdy wróci sieć',
                    onTap: () async {
                      await ref.read(pendingLinksProvider.notifier).add([url!]);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zapamiętano link.')));
                        Navigator.pop(context);
                      }
                    },
                  ),
              ]),
            ),
          ]),
          Positioned(left: 24, right: 24, bottom: MediaQuery.of(context).padding.bottom + 24, child: FilledButton(onPressed: () { Navigator.pop(context); onRetry(); }, child: const Text('Spróbuj ponownie'))),
        ]),
      );
}

class AiKeyScreen extends StatelessWidget {
  const AiKeyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bg,
        body: ListView(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 32), children: [
          HeroZone(
            bottom: 28,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const HeroBackHeader('Czat', size: 15),
              const SizedBox(height: 8),
              Text('Czat potrzebuje klucza API.', style: display(36, height: 40 / 36)),
              const SizedBox(height: 12),
              Text('Bez niego rozumiem zdania tylko na telefonie. Dodaj klucz, a odpowiem też na pytania i znajdę źródła.', style: fig(17, color: AppColors.text3, height: 26 / 17)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              NavRow(topLine: false, bold: true, minHeight: 72, title: 'Dodaj klucz', subtitle: 'Ja, Dostawca API', onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ApiProviderScreen()))),
              NavRow(bold: true, minHeight: 72, bottomLine: true, title: 'Wróć do zapisywania', subtitle: 'Głos, skaner i lista działają bez klucza', onTap: () => Navigator.pop(context)),
              const SizedBox(height: 28),
              Text('A gdy limit się skończy', style: fig(16, weight: 700)),
              const SizedBox(height: 8),
              Text('Dostawca czasem ogranicza liczbę zapytań. Zobaczysz wtedy „Limit na dziś wykorzystany”, a czat odblokuje się jutro. Zapisywanie posiłków dalej działa.', style: fig(16, color: AppColors.text3, height: 24 / 16)),
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UsageScreen())), child: const Text('Zobacz zużycie')),
            ]),
          ),
        ]),
      );
}
