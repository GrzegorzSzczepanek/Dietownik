import 'package:dio/dio.dart';

import '../domain/models.dart';

/// Open Food Facts: free, community database with Polish products and barcodes.
class OffClient {
  OffClient([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
              headers: {'User-Agent': 'Dietownik/1.0 (personal diet tracker)'},
            ));
  final Dio _dio;

  static const _fields = 'code,product_name,product_name_pl,brands,nutriments,serving_quantity';

  Future<Food?> byBarcode(String code) async {
    try {
      final r = await _dio.get('https://world.openfoodfacts.org/api/v2/product/$code.json',
          queryParameters: {'fields': _fields});
      final data = r.data;
      if (data is! Map || data['status'] != 1) return null;
      return _parse(data['product'] as Map, code);
    } on DioException {
      return null;
    }
  }

  Future<List<Food>> search(String q, {int limit = 8}) async {
    try {
      final r = await _dio.get('https://world.openfoodfacts.org/cgi/search.pl', queryParameters: {
        'search_terms': q,
        'search_simple': 1,
        'action': 'process',
        'json': 1,
        'page_size': limit * 2,
        'cc': 'pl',
        'lc': 'pl',
        'sort_by': 'unique_scans_n',
        'fields': _fields,
      });
      final products = (r.data is Map ? r.data['products'] : null) as List? ?? const [];
      return products
          .whereType<Map>()
          .map((p) => _parse(p, p['code']?.toString()))
          .whereType<Food>()
          .take(limit)
          .toList();
    } on DioException {
      return [];
    }
  }

  Food? _parse(Map p, String? code) {
    final n = p['nutriments'];
    if (n is! Map) return null;
    double? num_(String k) => (n[k] as num?)?.toDouble();
    var kcal = num_('energy-kcal_100g');
    final kj = num_('energy_100g');
    kcal ??= kj == null ? null : kj / 4.184;
    if (kcal == null) return null;
    final name = ((p['product_name_pl'] ?? p['product_name']) as String? ?? '').trim();
    if (name.isEmpty) return null;
    final brand = ((p['brands'] as String?) ?? '').split(',').first.trim();
    final sq = double.tryParse('${p['serving_quantity'] ?? ''}');
    return Food(
      name: name,
      brand: brand,
      barcode: code,
      kcal100: kcal,
      p100: num_('proteins_100g') ?? 0,
      c100: num_('carbohydrates_100g') ?? 0,
      f100: num_('fat_100g') ?? 0,
      servingG: (sq != null && sq > 0) ? sq : 100,
      servingLabel: (sq != null && sq > 0) ? 'porcja' : '',
      source: 'off',
    );
  }
}
