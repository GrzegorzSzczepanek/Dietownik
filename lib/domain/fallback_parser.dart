import '../ai/diet_ai.dart';

const Map<String, double> _numWords = {
  'pół': 0.5, 'pol': 0.5, 'jeden': 1, 'jedna': 1, 'jedno': 1, 'dwa': 2, 'dwie': 2, 'dwóch': 2, 'trzy': 3, 'cztery': 4,
  'pięć': 5, 'sześć': 6, 'siedem': 7, 'osiem': 8, 'dziewięć': 9, 'dziesięć': 10,
};

/// Rough weights for household units, used only by the simple (no-AI) parser.
const _unitGrams = {'łyżk': 15.0, 'lyzk': 15.0, 'łyżecz': 5.0, 'lyzecz': 5.0, 'szklank': 250.0, 'kubek': 250.0, 'kubk': 250.0, 'plaster': 20.0, 'kromk': 35.0};

/// Used when no AI engine is available: splits on commas / "i" / "oraz" / "+"
/// and reads a leading count ("2", "dwie", "pół"), "200 g" and spoon/glass units.
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
      final q = RegExp(r'^(\d+[.,]?\d*|[a-ząćęłńóśźż]+)\s+(.*)$').firstMatch(p);
      if (q != null) {
        final head = q.group(1)!;
        final double? n = double.tryParse(head.replaceAll(',', '.')) ?? _numWords[head]?.toDouble();
        if (n != null) {
          qty = n;
          p = q.group(2)!;
          // "dwie łyżki masła", "pół szklanki mleka": unit + "of" noun
          for (final u in _unitGrams.entries) {
            final m = RegExp('^${u.key}\\w*\\s+(.*)\$').firstMatch(p);
            if (m != null) {
              grams = n * u.value;
              qty = null;
              p = m.group(1)!;
              break;
            }
          }
          if (grams == null) {
            // "pół paczki makaronu": a fraction of a package has no known weight
            final stripped = p.replaceFirst(RegExp(r'^(paczk\w*|opakowani\w*|kostk\w*)\s+'), '');
            if (stripped != p) {
              p = stripped;
              qty = null;
            }
          }
        }
      }
    }
    if (p.isNotEmpty) out.add(ParsedItem(p, grams: grams, qty: qty));
  }
  return out;
}
