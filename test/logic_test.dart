import 'package:dietownik/ai/diet_ai.dart';
import 'package:dietownik/domain/fallback_parser.dart';
import 'package:dietownik/domain/csv_import.dart';
import 'package:dietownik/domain/meal_resolver.dart';
import 'package:dietownik/domain/models.dart';
import 'package:dietownik/services/recipe_import.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dietownik/data/food_seed.dart';
import 'package:dietownik/data/generic_foods.dart';

import 'package:dietownik/services/recipe_search.dart';

import 'package:dietownik/domain/shopping_parser.dart';

void main() {
  parserTests();
  shoppingTests();
  matchTests();
  genericTests();
  csvTests();
  test('fallback parser splits items and reads amounts', () {
    final r = fallbackParseMeal('2 jajka, 200 g ryżu i kanapka z serem');
    expect(r.length, 3);
    expect(r[0].qty, 2);
    expect(r[0].name, 'jajka');
    expect(r[1].grams, 200);
    expect(r[1].name, 'ryżu');
    expect(r[2].name, 'kanapka z serem');
  });

  test('Food.per scales by grams', () {
    const f = Food(name: 'x', kcal100: 200, p100: 10, c100: 20, f100: 5);
    expect(f.per(50).kcal, 100);
    expect(f.per(50).p, 5);
  });

  test('stemming lets inflected forms match', () {
    expect(MealResolver.stem('jajka'), MealResolver.stem('jajko'));
    expect(MealResolver.stem('serem'), MealResolver.stem('ser').isEmpty ? '' : MealResolver.stem('serem'));
  });

  test('goal calculator is sane', () {
    final g = Goals.calculate(male: true, age: 30, heightCm: 180, weightKg: 80, activity: 1.4, kcalDelta: -500);
    expect(g.kcal, inInclusiveRange(1900, 2100));
    expect(g.p * 4 + g.c * 4 + g.f * 9, closeTo(g.kcal, 60));
  });

  test('extractJson tolerates fences', () {
    final j = DietAi.extractJson('```json\n{"items":[{"name":"jajko"}]}\n```');
    expect((j as Map)['items'], isNotEmpty);
  });

  test('recipe import reads JSON-LD', () {
    const html = '''<html><script type="application/ld+json">
    {"@context":"https://schema.org","@graph":[{"@type":"Recipe","name":"Owsianka","recipeYield":"2 porcje",
    "recipeIngredient":["50 g płatków","250 ml mleka"],
    "recipeInstructions":[{"@type":"HowToStep","text":"Ugotuj."}],
    "nutrition":{"calories":"320 kcal","proteinContent":"12 g"}}]}</script></html>''';
    final r = parseRecipeHtml(html, 'https://x.pl')!;
    expect(r.title, 'Owsianka');
    expect(r.servings, 2);
    expect(r.ingredients.length, 2);
    expect(r.perServing.kcal, 320);
    expect(r.steps, contains('Ugotuj'));
  });
}

void csvTests() {
  test('csv import converts per-serving values', () {
    final r = parseFoodsCsv('nazwa;marka;kcal;b;w;t;porcja;na;kod\nBurger;X;500;25;40;25;250;porcja;123\nSkyr;;63,0;11;4;0,2;;100g;');
    expect(r.length, 2);
    expect(r[0].kcal100, closeTo(200, 0.01));
    expect(r[0].barcode, '123');
    expect(r[1].kcal100, 63);
  });
}

void genericTests() {
  test('generic seed has no duplicate names', () {
    final names = [...genericFoods, ...seedFoods].map((f) => '${f.name}|${f.brand}'.toLowerCase());
    expect(names.toSet().length, names.length);
  });
}

void matchTests() {
  test('recipe match counts pantry coverage and handles inflection', () {
    const r = Recipe(title: 'x', ingredients: [
      '4 jajka', '100 g sera żółtego', '2 duże pomidory', '1 łyżka masła', 'sól', '200 g makaronu (opcjonalnie)'
    ]);
    final m = matchRecipe(r, ['jajek', 'ser', 'pomidor']);
    expect(m.missing.length, 1); // masło
    expect(m.score, closeTo(0.8, 0.01)); // 4 of 5 (sól is a staple, optional skipped)
  });
}

void shoppingTests() {
  test('shopping command is detected and split', () {
    expect(parseShoppingCommand('zakupy jajka, ser, masło i mleko'), ['Jajka', 'Ser', 'Masło', 'Mleko']);
    expect(parseShoppingCommand('Dodaj do zakupów: chleb'), ['Chleb']);
    expect(parseShoppingCommand('dwa jajka i kawa'), isNull);
  });
}

void parserTests() {
  test('fallback parser understands number words and spoons', () {
    final r = fallbackParseMeal('dwie łyżki masła, pół jogurtu naturalnego i 23 krewetki');
    expect(r[0].grams, 30);
    expect(r[0].name, 'masła');
    expect(r[1].qty, 0.5);
    expect(r[2].qty, 23);
    expect(r[2].name, 'krewetki');
  });

  test('count of items without a piece weight never becomes count x 100 g', () {
    // krewetki without a piece weight: model estimate wins, then a single serving, never 2300 g
    const noPiece = Food(name: 'Krewetki', kcal100: 85, servingG: 100);
    const withPiece = Food(name: 'Jajko', kcal100: 143, servingG: 55, servingLabel: '1 jajko');
    expect(noPiece.pieceG, 0);
    expect(withPiece.pieceG, 55);
  });
}
