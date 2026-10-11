import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import 'db.dart';

const _prefKey = 'off_pack_v1';

/// Loads the bundled Polish product pack (Open Food Facts, ODbL) once, so
/// common barcodes resolve offline from the first scan.
Future<void> loadOffPackOnce(AppDb db) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_prefKey) ?? false) return;
  try {
    final bytes = (await rootBundle.load('assets/off_pl.tsv.gz')).buffer.asUint8List();
    final text = utf8.decode(GZipCodec().decode(bytes));
    final foods = <Food>[];
    for (final line in const LineSplitter().convert(text)) {
      final c = line.split('\t');
      if (c.length < 8) continue;
      final serving = double.tryParse(c[7]) ?? 0;
      foods.add(Food(
        barcode: c[0],
        name: c[1],
        brand: c[2],
        kcal100: double.tryParse(c[3]) ?? 0,
        p100: double.tryParse(c[4]) ?? 0,
        c100: double.tryParse(c[5]) ?? 0,
        f100: double.tryParse(c[6]) ?? 0,
        servingG: serving > 0 ? serving : 100,
        servingLabel: serving > 0 ? 'porcja' : '',
        source: 'off',
      ));
    }
    await db.seedFoods(foods);
    await prefs.setBool(_prefKey, true);
  } catch (_) {
    // Missing or corrupt pack: the app still works through the online lookup.
  }
}
