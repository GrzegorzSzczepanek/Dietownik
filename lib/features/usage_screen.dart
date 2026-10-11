import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ai/usage.dart';
import '../core/theme.dart';
import 'widgets.dart';

/// Zużycie AI per design/Zuzycie: a rough, on-device estimate against a monthly limit.
class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key});
  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  Map<String, double> _m = {};
  double _limit = AiUsage.defaultLimitUsd;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await AiUsage.month();
    final l = await AiUsage.limit();
    if (mounted) setState(() { _m = m; _limit = l; _loaded = true; });
  }

  String usd(double v) => '~\$${v.toStringAsFixed(2).replaceAll('.', ',')}';

  Future<void> _changeLimit() async {
    final ctrl = TextEditingController(text: _limit.toStringAsFixed(0));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limit miesięczny'),
        content: TextField(controller: ctrl, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(prefixText: '\$ ', helperText: 'Po przekroczeniu czat odmówi odpowiedzi do końca miesiąca.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 48)), onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.'))), child: const Text('Zapisz')),
        ],
      ),
    );
    if (v != null && v > 0) {
      await AiUsage.setLimit(v);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _m.values.fold<double>(0, (a, b) => a + b);
    final pct = (_limit == 0 ? 0 : total / _limit * 100).round();
    final since = DateFormat('d MMMM', 'pl').format(DateTime(DateTime.now().year, DateTime.now().month, 1));
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListView(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 32), children: [
        HeroZone(
          bottom: 28,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const HeroBackHeader('Zużycie AI w tym miesiącu', size: 15),
            const SizedBox(height: 4),
            Text(usd(total), style: display(56)),
            const SizedBox(height: 6),
            Text('około ${(total * AiUsage.usdToPln).toStringAsFixed(2).replaceAll('.', ',')} zł od $since', style: fig(17, weight: 600)),
            const SizedBox(height: 16),
            ProgressBar(_limit == 0 ? 0 : total / _limit, height: 12),
            const SizedBox(height: 8),
            Text('$pct% twojego limitu \$${_limit.toStringAsFixed(0)} miesięcznie', style: fig(14, color: AppColors.text3)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_loaded)
              for (final e in AiUsage.cats.entries)
                Container(
                  constraints: const BoxConstraints(minHeight: 60),
                  decoration: BoxDecoration(border: Border(top: e.key == 'zapisy' ? BorderSide.none : BorderSide(color: AppColors.line))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(e.value, style: fig(17, weight: 600)),
                    Text(usd(_m[e.key] ?? 0), style: fig(17, weight: 700)),
                  ]),
                ),
            const SizedBox(height: 16),
            Text('Kwoty są szacunkowe i liczone na telefonie. Prawdziwy rachunek zobaczysz u dostawcy.', style: fig(14, color: AppColors.text2, height: 20 / 14)),
            const SizedBox(height: 8),
            TextButton(onPressed: _changeLimit, child: const Text('Zmień limit miesięczny')),
          ]),
        ),
      ]),
    );
  }
}
