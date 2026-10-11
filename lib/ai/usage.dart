import 'package:shared_preferences/shared_preferences.dart';

/// Monthly AI usage counted on the phone: tokens per feature, converted to a rough USD estimate.
/// The real bill is at the provider; this is only meant to keep costs visible.
class AiUsage {
  static const cats = {'zapisy': 'Zapisy głosem i tekstem', 'czat': 'Czat ze źródłami', 'przepisy': 'Przepisy z AI'};
  static const defaultLimitUsd = 3.0;
  static const usdToPln = 4.0;

  static String _month() {
    final n = DateTime.now();
    return '${n.year}-${n.month}';
  }

  static Future<void> add(String cat, int tokens, double usdPerMillion) async {
    final p = await SharedPreferences.getInstance();
    final k = 'usage_${_month()}_$cat';
    p.setInt('${k}_t', (p.getInt('${k}_t') ?? 0) + tokens);
    p.setDouble('${k}_usd', (p.getDouble('${k}_usd') ?? 0) + tokens / 1e6 * usdPerMillion);
  }

  /// category -> estimated USD this month.
  static Future<Map<String, double>> month() async {
    final p = await SharedPreferences.getInstance();
    return {for (final c in cats.keys) c: p.getDouble('usage_${_month()}_${c}_usd') ?? 0};
  }

  static Future<int> tokens() async {
    final p = await SharedPreferences.getInstance();
    return cats.keys.fold<int>(0, (a, c) => a + (p.getInt('usage_${_month()}_${c}_t') ?? 0));
  }

  static Future<double> limit() async => (await SharedPreferences.getInstance()).getDouble('usage_limit_usd') ?? defaultLimitUsd;
  static Future<void> setLimit(double v) async => (await SharedPreferences.getInstance()).setDouble('usage_limit_usd', v);

  static Future<bool> overLimit() async {
    final m = await month();
    return m.values.fold<double>(0, (a, b) => a + b) >= await limit();
  }
}
