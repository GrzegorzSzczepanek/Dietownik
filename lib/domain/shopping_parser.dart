/// Detects "zakupy jajka, ser, masło" style commands and returns the items,
/// or null when the sentence is a normal food log entry.
final _prefix = RegExp(
  r'^\s*(?:dodaj\s+do\s+(?:listy\s+)?(?:zakupów|zakupow|koszyka)|do\s+(?:zakupów|zakupow|koszyka)|lista\s+zakupów|lista\s+zakupow|zakupy|kup(?:ić)?|koszyk)\b[\s:,\-–]*',
  caseSensitive: false,
);

List<String>? parseShoppingCommand(String text) {
  final m = _prefix.firstMatch(text);
  if (m == null) return null;
  final items = splitShoppingItems(text.substring(m.end));
  return items;
}

List<String> splitShoppingItems(String text) {
  return text
      .split(RegExp(r'[,;\n]|\s+i\s+|\s+oraz\s+|\s+plus\s+', caseSensitive: false))
      .map((e) => e.trim().replaceAll(RegExp(r'^[-•*\s]+'), ''))
      .where((e) => e.isNotEmpty)
      .map((e) => e[0].toUpperCase() + e.substring(1))
      .toList();
}
