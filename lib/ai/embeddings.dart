import 'package:dio/dio.dart';

import 'ai_settings.dart';
import 'llm_api.dart';

/// Turns text into vectors. Only the OpenAI-compatible `/embeddings` endpoint
/// is implemented (OpenAI, Gemini's compatibility layer, Ollama, OpenRouter);
/// Anthropic has no embeddings API.
abstract class Embedder {
  /// Stable identity of the vector space: vectors from different ids must
  /// never be compared.
  String get id;
  Future<List<List<double>>> embed(List<String> texts);
}

class OpenAiEmbedder implements Embedder {
  OpenAiEmbedder(this.cfg, this.apiKey, {Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 60)));

  final ApiConfig cfg;
  final String? apiKey;
  final Dio _dio;

  @override
  String get id => '${cfg.presetId}:${cfg.embeddingModel}';

  @override
  Future<List<List<double>>> embed(List<String> texts) async {
    if (texts.isEmpty) return [];
    final base = cfg.baseUrl.endsWith('/') ? cfg.baseUrl.substring(0, cfg.baseUrl.length - 1) : cfg.baseUrl;
    try {
      final r = await _dio.post(
        '$base/embeddings',
        options: Options(headers: {if (apiKey != null && apiKey!.isNotEmpty) 'Authorization': 'Bearer $apiKey'}),
        data: {'model': cfg.embeddingModel, 'input': texts},
      );
      final data = (r.data as Map)['data'] as List;
      // Providers may reorder; `index` says which input a vector belongs to.
      final sorted = [...data]..sort((a, b) => ((a['index'] ?? 0) as int).compareTo((b['index'] ?? 0) as int));
      if (sorted.length != texts.length) {
        throw LlmException('Dostawca zwrócił ${sorted.length} wektorów dla ${texts.length} tekstów.');
      }
      return [
        for (final d in sorted) [for (final v in (d['embedding'] as List)) (v as num).toDouble()]
      ];
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      throw LlmException(status == null
          ? 'Brak połączenia z ${e.requestOptions.uri.host}: ${e.message}'
          : 'Błąd embeddingów ($status). Sprawdź nazwę modelu embeddingów.');
    }
  }
}
