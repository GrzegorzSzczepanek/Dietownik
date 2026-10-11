import 'models.dart';

/// Parses a product list. Columns (header optional, order fixed):
/// nazwa; marka; kcal; białko; węgle; tłuszcz; porcja_g; na (100g|porcja); kod_kreskowy
/// Delimiter `;`, `,` or tab is detected; decimal commas are accepted.
/// When `na` is "porcja", values are per serving and converted to per 100 g.
List<Food> parseFoodsCsv(String text, {String source = 'own'}) {
  final lines = text.replaceAll('\r', '').split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) return [];
  final first = lines.first;
  final delim = first.contains(';') ? ';' : (first.contains('\t') ? '\t' : ',');
  double? num_(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  final out = <Food>[];
  for (final line in lines) {
    final c = _split(line, delim);
    if (c.length < 3) continue;
    final kcal = num_(c[2]);
    if (kcal == null) continue; // header or junk row
    final name = c[0].trim();
    if (name.isEmpty) continue;
    final serving = c.length > 6 ? num_(c[6]) : null;
    final perServing = c.length > 7 && c[7].toLowerCase().contains('por');
    final k = (perServing && serving != null && serving > 0) ? 100 / serving : 1.0;
    final barcode = c.length > 8 ? c[8].trim() : '';
    out.add(Food(
      name: name,
      brand: c.length > 1 ? c[1].trim() : '',
      kcal100: kcal * k,
      p100: (c.length > 3 ? (num_(c[3]) ?? 0) : 0) * k,
      c100: (c.length > 4 ? (num_(c[4]) ?? 0) : 0) * k,
      f100: (c.length > 5 ? (num_(c[5]) ?? 0) : 0) * k,
      servingG: (serving != null && serving > 0) ? serving : 100,
      servingLabel: (serving != null && serving > 0) ? 'porcja' : '',
      barcode: barcode.isEmpty ? null : barcode,
      source: source,
    ));
  }
  return out;
}

List<String> _split(String line, String d) {
  final out = <String>[];
  final b = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      quoted = !quoted;
    } else if (ch == d && !quoted) {
      out.add(b.toString());
      b.clear();
    } else {
      b.write(ch);
    }
  }
  out.add(b.toString());
  return out;
}
