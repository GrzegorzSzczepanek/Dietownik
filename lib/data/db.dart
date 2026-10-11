import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';

class AppDb {
  AppDb._(this._db);
  final Database _db;

  static Future<AppDb> open() async {
    final path = p.join(await getDatabasesPath(), 'dietownik.db');
    final db = await openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute('''CREATE TABLE foods(
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, brand TEXT, barcode TEXT,
        kcal100 REAL, p100 REAL, c100 REAL, f100 REAL, serving_g REAL, serving_label TEXT,
        source TEXT, uses INTEGER DEFAULT 0, last_used INTEGER DEFAULT 0)''');
      await db.execute('CREATE INDEX foods_barcode ON foods(barcode)');
      await db.execute('''CREATE TABLE entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT, day TEXT NOT NULL, meal INTEGER, name TEXT,
        grams REAL, kcal REAL, p REAL, c REAL, f REAL, estimated INTEGER DEFAULT 0, ts INTEGER)''');
      await db.execute('CREATE INDEX entries_day ON entries(day)');
      await db.execute('''CREATE TABLE recipes(
        id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, servings INTEGER, ingredients TEXT,
        steps TEXT, source_url TEXT, kcal REAL, p REAL, c REAL, f REAL, favorite INTEGER DEFAULT 0)''');
    });
    return AppDb._(db);
  }

  // ---- entries
  Future<List<Entry>> entriesFor(String day) async =>
      (await _db.query('entries', where: 'day = ?', whereArgs: [day], orderBy: 'ts'))
          .map(Entry.fromMap)
          .toList();

  Future<int> addEntry(Entry e) =>
      _db.insert('entries', {...e.toMap(), 'ts': DateTime.now().millisecondsSinceEpoch});

  Future<void> deleteEntry(int id) => _db.delete('entries', where: 'id = ?', whereArgs: [id]);

  Future<void> updateEntry(Entry e) =>
      _db.update('entries', e.toMap(), where: 'id = ?', whereArgs: [e.id]);

  /// Distinct days that have at least one entry, newest first.
  Future<Set<String>> loggedDays({int limit = 400}) async => (await _db.rawQuery(
          'SELECT DISTINCT day FROM entries ORDER BY day DESC LIMIT ?', [limit]))
      .map((r) => r['day'] as String)
      .toSet();

  Future<Map<String, double>> kcalByDay(String from, String to) async {
    final rows = await _db.rawQuery(
        'SELECT day, SUM(kcal) k FROM entries WHERE day BETWEEN ? AND ? GROUP BY day', [from, to]);
    return {for (final r in rows) r['day'] as String: (r['k'] as num).toDouble()};
  }

  // ---- foods
  Future<int> saveFood(Food f) async {
    if (f.barcode != null && f.barcode!.isNotEmpty) {
      final ex = await _db.query('foods', where: 'barcode = ?', whereArgs: [f.barcode], limit: 1);
      if (ex.isNotEmpty) return ex.first['id'] as int;
    }
    final ex = await _db.query('foods',
        where: 'LOWER(name) = ? AND LOWER(IFNULL(brand, "")) = ?',
        whereArgs: [f.name.toLowerCase(), f.brand.toLowerCase()],
        limit: 1);
    if (ex.isNotEmpty) return ex.first['id'] as int;
    return _db.insert('foods', f.toMap());
  }

  Future<Food?> foodByBarcode(String code) async {
    final r = await _db.query('foods', where: 'barcode = ?', whereArgs: [code], limit: 1);
    return r.isEmpty ? null : Food.fromMap(r.first);
  }

  Future<void> touchFood(int id) => _db.rawUpdate(
      'UPDATE foods SET uses = uses + 1, last_used = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, id]);

  Future<List<Food>> searchFoods(String q, {int limit = 20}) async {
    final like = '%${q.toLowerCase()}%';
    return (await _db.query('foods',
            where: 'LOWER(name) LIKE ? OR LOWER(IFNULL(brand, "")) LIKE ?',
            whereArgs: [like, like],
            orderBy: 'uses DESC, last_used DESC',
            limit: limit))
        .map(Food.fromMap)
        .toList();
  }

  Future<int> foodCount() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM foods')) ?? 0;

  Future<void> seedFoods(List<Food> foods) async {
    final b = _db.batch();
    for (final f in foods) {
      b.insert('foods', f.toMap());
    }
    await b.commit(noResult: true);
  }

  /// Most frequent meals from the log, so the usual stuff is one tap away.
  Future<List<Entry>> frequentEntries({int limit = 8}) async {
    final rows = await _db.rawQuery('''
      SELECT name, ROUND(AVG(grams)) grams, ROUND(AVG(kcal)) kcal, ROUND(AVG(p),1) p,
             ROUND(AVG(c),1) c, ROUND(AVG(f),1) f, MAX(estimated) estimated, COUNT(*) n
      FROM entries GROUP BY LOWER(name) ORDER BY n DESC, MAX(ts) DESC LIMIT ?''', [limit]);
    return rows
        .map((r) => Entry.fromMap({...r, 'day': '', 'meal': 0}))
        .toList();
  }

  // ---- recipes
  Future<List<Recipe>> recipes() async =>
      (await _db.query('recipes', orderBy: 'favorite DESC, id DESC')).map(Recipe.fromMap).toList();

  Future<int> saveRecipe(Recipe r) async {
    if (r.id == null) return _db.insert('recipes', r.toMap());
    await _db.update('recipes', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
    return r.id!;
  }

  Future<void> deleteRecipe(int id) => _db.delete('recipes', where: 'id = ?', whereArgs: [id]);
}
