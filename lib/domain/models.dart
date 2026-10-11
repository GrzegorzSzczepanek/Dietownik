import 'dart:convert';

class Macros {
  const Macros({this.kcal = 0, this.p = 0, this.c = 0, this.f = 0});
  final double kcal, p, c, f;
  Macros operator +(Macros o) => Macros(kcal: kcal + o.kcal, p: p + o.p, c: c + o.c, f: f + o.f);
  Macros operator *(double k) => Macros(kcal: kcal * k, p: p * k, c: c * k, f: f * k);
  static const zero = Macros();
}

const mealNames = ['Śniadanie', 'Obiad', 'Kolacja', 'Przekąska'];

/// Guess the meal from the clock so nobody has to pick one.
int mealForTime(DateTime t) {
  final h = t.hour;
  if (h >= 4 && h < 11) return 0;
  if (h >= 11 && h < 17) return 1;
  if (h >= 17 && h < 22) return 2;
  return 3;
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class Food {
  const Food({
    this.id,
    required this.name,
    this.brand = '',
    this.barcode,
    required this.kcal100,
    this.p100 = 0,
    this.c100 = 0,
    this.f100 = 0,
    this.servingG = 100,
    this.servingLabel = '',
    this.source = 'own',
    this.ingredients = '',
  });
  final int? id;
  final String name, brand, ingredients;
  final String? barcode;
  final double kcal100, p100, c100, f100, servingG;
  final String servingLabel;

  /// own | off | chain | ai
  final String source;

  Macros per(double grams) =>
      Macros(kcal: kcal100, p: p100, c: c100, f: f100) * (grams / 100);

  String get title => brand.isEmpty ? name : '$name · $brand';
  bool get estimated => source == 'ai' || source == 'chain';

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'brand': brand,
        'barcode': barcode,
        'kcal100': kcal100,
        'p100': p100,
        'c100': c100,
        'f100': f100,
        'serving_g': servingG,
        'serving_label': servingLabel,
        'source': source,
        'ingredients': ingredients,
      };

  factory Food.fromMap(Map<String, Object?> m) => Food(
        id: m['id'] as int?,
        name: m['name'] as String,
        brand: (m['brand'] as String?) ?? '',
        barcode: m['barcode'] as String?,
        kcal100: (m['kcal100'] as num).toDouble(),
        p100: (m['p100'] as num).toDouble(),
        c100: (m['c100'] as num).toDouble(),
        f100: (m['f100'] as num).toDouble(),
        servingG: (m['serving_g'] as num).toDouble(),
        servingLabel: (m['serving_label'] as String?) ?? '',
        source: (m['source'] as String?) ?? 'own',
        ingredients: (m['ingredients'] as String?) ?? '',
      );
}

class Entry {
  const Entry({
    this.id,
    required this.day,
    required this.meal,
    required this.name,
    required this.grams,
    required this.macros,
    this.estimated = false,
  });
  final int? id;
  final String day, name;
  final int meal;
  final double grams;
  final Macros macros;
  final bool estimated;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'day': day,
        'meal': meal,
        'name': name,
        'grams': grams,
        'kcal': macros.kcal,
        'p': macros.p,
        'c': macros.c,
        'f': macros.f,
        'estimated': estimated ? 1 : 0,
      };

  factory Entry.fromMap(Map<String, Object?> m) => Entry(
        id: m['id'] as int?,
        day: m['day'] as String,
        meal: m['meal'] as int,
        name: m['name'] as String,
        grams: (m['grams'] as num).toDouble(),
        macros: Macros(
          kcal: (m['kcal'] as num).toDouble(),
          p: (m['p'] as num).toDouble(),
          c: (m['c'] as num).toDouble(),
          f: (m['f'] as num).toDouble(),
        ),
        estimated: (m['estimated'] as int? ?? 0) == 1,
      );
}

class Recipe {
  const Recipe({
    this.id,
    required this.title,
    this.servings = 1,
    this.ingredients = const [],
    this.steps = '',
    this.sourceUrl = '',
    this.perServing = Macros.zero,
    this.favorite = false,
  });
  final int? id;
  final String title, steps, sourceUrl;
  final int servings;
  final List<String> ingredients;
  final Macros perServing;
  final bool favorite;

  Recipe copyWith({Macros? perServing, bool? favorite}) => Recipe(
        id: id,
        title: title,
        servings: servings,
        ingredients: ingredients,
        steps: steps,
        sourceUrl: sourceUrl,
        perServing: perServing ?? this.perServing,
        favorite: favorite ?? this.favorite,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'servings': servings,
        'ingredients': jsonEncode(ingredients),
        'steps': steps,
        'source_url': sourceUrl,
        'kcal': perServing.kcal,
        'p': perServing.p,
        'c': perServing.c,
        'f': perServing.f,
        'favorite': favorite ? 1 : 0,
      };

  factory Recipe.fromMap(Map<String, Object?> m) => Recipe(
        id: m['id'] as int?,
        title: m['title'] as String,
        servings: (m['servings'] as int?) ?? 1,
        ingredients: (jsonDecode((m['ingredients'] as String?) ?? '[]') as List).cast<String>(),
        steps: (m['steps'] as String?) ?? '',
        sourceUrl: (m['source_url'] as String?) ?? '',
        perServing: Macros(
          kcal: (m['kcal'] as num?)?.toDouble() ?? 0,
          p: (m['p'] as num?)?.toDouble() ?? 0,
          c: (m['c'] as num?)?.toDouble() ?? 0,
          f: (m['f'] as num?)?.toDouble() ?? 0,
        ),
        favorite: (m['favorite'] as int? ?? 0) == 1,
      );
}

/// Daily targets.
class Goals {
  const Goals({this.kcal = 2000, this.p = 120, this.c = 220, this.f = 65});
  final double kcal, p, c, f;
  Goals copyWith({double? kcal, double? p, double? c, double? f}) =>
      Goals(kcal: kcal ?? this.kcal, p: p ?? this.p, c: c ?? this.c, f: f ?? this.f);

  /// Mifflin-St Jeor + activity factor; macros split 30/45/25 (P/C/F by kcal),
  /// protein floored at 1.6 g/kg.
  static Goals calculate({
    required bool male,
    required int age,
    required double heightCm,
    required double weightKg,
    required double activity,
    required double kcalDelta,
  }) {
    final bmr = 10 * weightKg + 6.25 * heightCm - 5 * age + (male ? 5 : -161);
    final kcal = (bmr * activity + kcalDelta).clamp(1200, 5000).toDouble();
    final p = (kcal * 0.30 / 4).clamp(weightKg * 1.6, 400).toDouble();
    final f = kcal * 0.25 / 9;
    final c = ((kcal - p * 4 - f * 9) / 4).clamp(0, 1000).toDouble();
    return Goals(
        kcal: kcal.roundToDouble(), p: p.roundToDouble(), c: c.roundToDouble(), f: f.roundToDouble());
  }
}
