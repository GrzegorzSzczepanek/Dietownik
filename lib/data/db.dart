import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';

class AppDb {
  AppDb._(this._db);
  final Database _db;

  static Future<AppDb> open() async {
    final path = p.join(await getDatabasesPath(), 'dietownik.db');
    final db = await openDatabase(path, version: 4, onUpgrade: (db, o, n) async {
      if (o < 2) await db.execute('ALTER TABLE foods ADD COLUMN ingredients TEXT');
      if (o < 3) await db.execute('CREATE TABLE IF NOT EXISTS weights(day TEXT PRIMARY KEY, kg REAL)');
      if (o < 4) await db.execute('CREATE TABLE IF NOT EXISTS water(day TEXT PRIMARY KEY, ml INTEGER)');
    }, onCreate: (db, v) async {
      await db.execute('''CREATE TABLE foods(
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, brand TEXT, barcode TEXT,
        kcal100 REAL, p100 REAL, c100 REAL, f100 REAL, serving_g REAL, serving_label TEXT,
        source TEXT, ingredients TEXT, uses INTEGER DEFAULT 0, last_used INTEGER DEFAULT 0)''');
      await db.execute('CREATE TABLE weights(day TEXT PRIMARY KEY, kg REAL)');
      await db.execute('CREATE TABLE water(day TEXT PRIMARY KEY, ml INTEGER)');
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

  Future<Set<String>> barcodes() async => (await _db.rawQuery("SELECT barcode FROM foods WHERE barcode IS NOT NULL AND barcode != ''")).map((r) => r['barcode'] as String).toSet();

  /// Inserts foods whose name+brand is not present yet, in one batch.
  Future<void> seedFoodsIfMissing(List<Food> foods) async {
    final have = (await _db.rawQuery('SELECT LOWER(name) n, LOWER(IFNULL(brand, "")) b FROM foods'))
        .map((r) => '${r['n']}|${r['b']}')
        .toSet();
    final b = _db.batch();
    for (final f in foods) {
      if (have.add('${f.name.toLowerCase()}|${f.brand.toLowerCase()}')) b.insert('foods', f.toMap());
    }
    await b.commit(noResult: true);
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

  // ---- water
  Future<int> waterFor(String day) async {
    final r = await _db.query('water', where: 'day = ?', whereArgs: [day], limit: 1);
    return r.isEmpty ? 0 : (r.first['ml'] as int);
  }

  Future<void> addWater(String day, int ml) async {
    final now = await waterFor(day);
    await _db.insert('water', {'day': day, 'ml': (now + ml).clamp(0, 10000)},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Per-day totals (kcal, protein, carbs, fat) between two day keys inclusive.
  Future<Map<String, Macros>> macrosByDay(String from, String to) async {
    final rows = await _db.rawQuery(
        'SELECT day, SUM(kcal) k, SUM(p) p, SUM(c) c, SUM(f) f FROM entries WHERE day BETWEEN ? AND ? GROUP BY day',
        [from, to]);
    return {
      for (final r in rows)
        r['day'] as String: Macros(
            kcal: (r['k'] as num).toDouble(),
            p: (r['p'] as num).toDouble(),
            c: (r['c'] as num).toDouble(),
            f: (r['f'] as num).toDouble())
    };
  }

  // ---- weight
  Future<void> setWeight(String day, double kg) =>
      _db.insert('weights', {'day': day, 'kg': kg}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteWeight(String day) => _db.delete('weights', where: 'day = ?', whereArgs: [day]);

  Future<List<MapEntry<String, double>>> weights() async =>
      (await _db.query('weights', orderBy: 'day'))
          .map((r) => MapEntry(r['day'] as String, (r['kg'] as num).toDouble()))
          .toList();

  // ---- backup
  Future<Map<String, Object?>> exportAll() async => {
        'app': 'dietownik',
        'version': 1,
        'foods': await _db.query('foods'),
        'entries': await _db.query('entries'),
        'recipes': await _db.query('recipes'),
        'weights': await _db.query('weights'),
        'water': await _db.query('water'),
      };

  /// Replaces entries, recipes and weights; merges foods (the bundled pack stays).
  Future<void> importAll(Map<String, dynamic> data) async {
    if (data['app'] != 'dietownik') throw const FormatException('To nie jest kopia Dietownika.');
    List<Map<String, Object?>> rows(String k) =>
        ((data[k] as List?) ?? const []).map((e) => Map<String, Object?>.from(e as Map)).toList();
    await _db.transaction((txn) async {
      for (final t in ['entries', 'recipes', 'weights', 'water']) {
        await txn.delete(t);
      }
      for (final t in ['entries', 'recipes', 'weights', 'water']) {
        for (final r in rows(t)) {
          await txn.insert(t, r, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      for (final r in rows('foods')) {
        final code = r['barcode'] as String?;
        final dup = await txn.query('foods',
            where: code != null && code.isNotEmpty ? 'barcode = ?' : 'LOWER(name) = ? AND LOWER(IFNULL(brand, "")) = ?',
            whereArgs: code != null && code.isNotEmpty
                ? [code]
                : [(r['name'] as String).toLowerCase(), ((r['brand'] as String?) ?? '').toLowerCase()],
            limit: 1);
        if (dup.isEmpty) await txn.insert('foods', {...r}..remove('id'));
      }
    });
  }
}
