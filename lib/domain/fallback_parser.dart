import '../ai/diet_ai.dart';

/// Used when no AI engine is available: splits on commas / "i" / "oraz" / "+"
/// and reads a leading count or "200 g".
List<ParsedItem> fallbackParseMeal(String text) {
  final parts = text
      .toLowerCase()
      .split(RegExp(r',|;|\+|\s+i\s+|\s+oraz\s+|\s+plus\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty);
  final out = <ParsedItem>[];
  for (var p in parts) {
    double? grams, qty;
    final g = RegExp(r'^(\d+[.,]?\d*)\s*(kg|dag|g|gram[ówy]*|ml|l)\b\s*(.*)$').firstMatch(p);
    if (g != null) {
      var v = double.parse(g.group(1)!.replaceAll(',', '.'));
      final u = g.group(2)!;
      if (u == 'kg' || u == 'l') v *= 1000;
      if (u == 'dag') v *= 10;
      grams = v;
      p = g.group(3)!.replaceFirst(RegExp(r'^(of|z|ze)\s+'), '');
    } else {
      final q = RegExp(r'^(\d+[.,]?\d*)\s+(.*)$').firstMatch(p);
      if (q != null) {
        qty = double.parse(q.group(1)!.replaceAll(',', '.'));
        p = q.group(2)!;
      }
    }
    if (p.isNotEmpty) out.add(ParsedItem(p, grams: grams, qty: qty));
  }
  return out;
}
