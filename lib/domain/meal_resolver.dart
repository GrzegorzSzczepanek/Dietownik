import '../ai/ai_settings.dart';
import '../ai/diet_ai.dart';
import '../data/db.dart';
import '../services/off_client.dart';
import 'models.dart';

/// A parsed item matched to nutrition data.
class ResolvedItem {
  ResolvedItem(this.name, this.grams, this.macros, {this.estimated = false, this.unknown = false, this.pieceG = 0, this.pieceLabel = '', this.source = ''});
  final String name;
  final double pieceG;
  final String pieceLabel, source;
  final double grams;
  final Macros macros;
  final bool estimated;

  /// Nothing found anywhere: macros are zero and the user should fill them in.
  final bool unknown;
}

/// Offline-first lookup: own/seeded foods -> Open Food Facts -> AI estimate.
class MealResolver {
  MealResolver({required this.db, required this.off, this.ai});
  final AppDb db;
  final OffClient off;
  final DietAi? ai;

  static final _stop = {'z', 'ze', 'i', 'w', 'na', 'do', 'po', 'a', 'oraz'};

  static List<String> tokens(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^a-ząćęłńóśźż0-9]+'))
      .where((t) => t.length > 1 && !_stop.contains(t))
      .toList();

  /// Strip Polish inflection crudely so "jajka"/"jajko" or "serem"/"ser" meet.
  static String stem(String t) => t.length > 5 ? t.substring(0, t.length - 2) : (t.length > 3 ? t.substring(0, t.length - 1) : t);

  Future<Food?> _local(String name) async {
    final toks = tokens(name);
    if (toks.isEmpty) return null;
    final seen = <int, Food>{};
    for (final t in toks) {
      for (final f in await db.searchFoods(stem(t), limit: 30)) {
        if (f.id != null) seen[f.id!] = f;
      }
    }
    Food? best;
    var bestScore = 0.0;
    final want = toks.map(stem).toSet();
    for (final f in seen.values) {
      final have = tokens('${f.name} ${f.brand}').map(stem).toSet();
      final hit = want.where(have.contains).length;
      if (hit == 0) continue;
      // reward coverage of the query, penalise extra words in the food name
      final score = hit / want.length - 0.1 * (have.length - hit).clamp(0, 4);
      if (score > bestScore) {
        bestScore = score;
        best = f;
      }
    }
    return bestScore >= 0.5 ? best : null;
  }

  Future<ResolvedItem> resolve(ParsedItem it) async {
    var food = await _local(it.name);
    var estimated = food?.estimated ?? false;
    if (food == null) {
      final hits = await off.search(it.name, limit: 5);
      if (hits.isNotEmpty) {
        food = hits.first;
        final id = await db.saveFood(food);
        food = Food.fromMap({...food.toMap(), 'id': id});
      }
    }
    if (food == null && ai != null && ai!.canRun(AiTask.estimation)) {
      try {
        final e = await ai!.estimate(it.name);
        final f = Food(
            name: it.name,
            kcal100: e.kcal100,
            p100: e.p100,
            c100: e.c100,
            f100: e.f100,
            servingG: e.servingG,
            ingredients: (e.sourceUrl ?? '').isEmpty ? '' : 'Źródło: ${e.sourceUrl}',
            source: (e.sourceUrl ?? '').isEmpty ? 'ai' : 'web');
        final id = await db.saveFood(f);
        food = Food.fromMap({...f.toMap(), 'id': id});
        estimated = true;
      } catch (_) {}
    }
    if (food == null) {
      return ResolvedItem(it.name, it.grams ?? 100, Macros.zero, unknown: true);
    }
    if (food.id != null) await db.touchFood(food.id!);
    final grams = _gramsFor(it, food);
    return ResolvedItem(food.title, grams, food.per(grams),
        estimated: estimated, pieceG: food.pieceG, pieceLabel: food.servingLabel, source: food.sourceNote);
  }

  /// Quantity -> grams. A count only multiplies a real piece weight ("2 jajka" = 2 x 55 g);
  /// for foods without one the model's total estimate is used, never count x 100 g.
  double _gramsFor(ParsedItem it, Food f) {
    final hasPiece = f.pieceG > 0;
    final qty = (it.qty != null && it.qty! > 0) ? it.qty! : null;
    if (qty != null && hasPiece) return qty * f.servingG;
    if (it.grams != null && it.grams! > 0) return it.grams!;
    return hasPiece ? (qty ?? 1) * f.servingG : f.servingG;
  }
}
