import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AiTask { foodParsing, estimation, embeddings, advice }

enum AiEngine { local, api }

enum ApiFormat { openai, anthropic }

extension AiTaskLabel on AiTask {
  String get label => switch (this) {
        AiTask.foodParsing => 'Rozpoznawanie posiłków z mowy',
        AiTask.estimation => 'Szacowanie kalorii i makro',
        AiTask.embeddings => 'Wyszukiwanie (embeddingi)',
        AiTask.advice => 'Porady i pomysły na posiłki',
      };
}

class ApiPreset {
  const ApiPreset(this.id, this.label, this.format, this.baseUrl,
      {this.needsKey = true, this.model = '', this.visionModel = '', this.keyUrl = '', this.note = '', this.price = 0.5});
  final String id;
  final String label;
  final ApiFormat format;
  final String baseUrl;
  final bool needsKey;

  /// Sensible defaults so nobody has to look up model names. All editable.
  final String model;

  /// Used only when a request contains an image (label photos); empty = same as [model].
  final String visionModel;
  final String keyUrl;
  final String note;

  /// Rough blended USD per 1M tokens (input and output averaged). Used only for the usage estimate.
  final double price;
}

const apiPresets = [
  ApiPreset('deepseek', 'DeepSeek', ApiFormat.openai, 'https://api.deepseek.com',
      model: 'deepseek-v4-flash',
      visionModel: 'deepseek-v4-flash-vision-exp',
      keyUrl: 'platform.deepseek.com',
      note: 'Najtańszy. Obraz w trybie eksperymentalnym — jeśli słabo czyta etykiety, zmień model obrazu.', price: 0.2),
  ApiPreset('gemini', 'Gemini', ApiFormat.openai, 'https://generativelanguage.googleapis.com/v1beta/openai',
      model: 'gemini-2.5-flash', keyUrl: 'aistudio.google.com/apikey', note: 'Darmowy limit, dobry obraz.', price: 0.5),
  ApiPreset('openai', 'OpenAI', ApiFormat.openai, 'https://api.openai.com/v1',
      model: 'gpt-4o-mini', keyUrl: 'platform.openai.com/api-keys', price: 0.4),
  ApiPreset('anthropic', 'Anthropic', ApiFormat.anthropic, 'https://api.anthropic.com',
      model: 'claude-haiku-5-5', keyUrl: 'console.anthropic.com', note: 'Bardzo dobry odczyt etykiet.', price: 2.0),
  ApiPreset('groq', 'Groq', ApiFormat.openai, 'https://api.groq.com/openai/v1',
      model: 'llama-3.3-70b-versatile',
      visionModel: 'meta-llama/llama-4-scout-17b-16e-instruct',
      keyUrl: 'console.groq.com/keys',
      note: 'Bardzo szybki, darmowy limit.', price: 0.2),
  ApiPreset('mistral', 'Mistral', ApiFormat.openai, 'https://api.mistral.ai/v1',
      model: 'mistral-small-latest', keyUrl: 'console.mistral.ai', price: 0.3),
  ApiPreset('openrouter', 'OpenRouter', ApiFormat.openai, 'https://openrouter.ai/api/v1',
      model: 'google/gemini-2.5-flash', keyUrl: 'openrouter.ai/keys', note: 'Jeden klucz do wielu modeli.', price: 0.5),
  ApiPreset('ollama', 'Ollama (LAN)', ApiFormat.openai, 'http://localhost:11434/v1',
      needsKey: false,
      price: 0,
      model: 'llama3.2',
      visionModel: 'llama3.2-vision',
      note: 'Model na Twoim komputerze. Z telefonu podaj adres IP komputera zamiast localhost.'),
  ApiPreset('custom', 'Własny', ApiFormat.openai, ''),
];

class ApiConfig {
  const ApiConfig({
    this.presetId = 'deepseek',
    this.format = ApiFormat.openai,
    this.baseUrl = 'https://api.deepseek.com',
    this.model = '',
    this.visionModel = '',
    this.embeddingModel = '',
  });

  final String presetId;
  final ApiFormat format;
  final String baseUrl;
  final String model;
  final String visionModel;

  /// Optional: model name for the provider's `/embeddings` endpoint.
  final String embeddingModel;

  ApiPreset get preset => apiPresets.firstWhere((p) => p.id == presetId,
      orElse: () => apiPresets.last);
  String get providerLabel => preset.label;

  ApiConfig copyWith(
          {String? presetId, ApiFormat? format, String? baseUrl, String? model, String? visionModel, String? embeddingModel}) =>
      ApiConfig(
        presetId: presetId ?? this.presetId,
        format: format ?? this.format,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        visionModel: visionModel ?? this.visionModel,
        embeddingModel: embeddingModel ?? this.embeddingModel,
      );

  Map<String, dynamic> toJson() => {
        'preset': presetId,
        'format': format.name,
        'baseUrl': baseUrl,
        'model': model,
        'visionModel': visionModel,
        'embeddingModel': embeddingModel,
      };

  factory ApiConfig.fromJson(Map<String, dynamic> j) => ApiConfig(
        presetId: j['preset'] as String? ?? 'deepseek',
        format: ApiFormat.values.byName(j['format'] as String? ?? 'openai'),
        baseUrl: j['baseUrl'] as String? ?? '',
        model: j['model'] as String? ?? '',
        visionModel: j['visionModel'] as String? ?? '',
        embeddingModel: j['embeddingModel'] as String? ?? '',
      );
}

class PrivacySettings {
  const PrivacySettings({
    this.maskPersonalData = true,
    this.askBeforeSendingImage = true,
    this.suggestApiRetry = true,
    this.showTokenCounter = true,
  });
  final bool maskPersonalData;
  final bool askBeforeSendingImage;
  final bool suggestApiRetry;
  final bool showTokenCounter;

  PrivacySettings copyWith({bool? mask, bool? ask, bool? retry, bool? tokens}) =>
      PrivacySettings(
        maskPersonalData: mask ?? maskPersonalData,
        askBeforeSendingImage: ask ?? askBeforeSendingImage,
        suggestApiRetry: retry ?? suggestApiRetry,
        showTokenCounter: tokens ?? showTokenCounter,
      );
}

class AiSettings {
  const AiSettings({
    required this.engines,
    this.api = const ApiConfig(),
    this.privacy = const PrivacySettings(),
    this.monthlyTokens = 0,
  });

  final Map<AiTask, AiEngine> engines;
  final ApiConfig api;
  final PrivacySettings privacy;
  final int monthlyTokens;

  /// Defaults favour privacy: everything local except chat, which has no
  /// sensible small local model yet.
  factory AiSettings.defaults() => AiSettings(engines: {
        AiTask.foodParsing: AiEngine.api,
        AiTask.estimation: AiEngine.api,
        AiTask.embeddings: AiEngine.local,
        AiTask.advice: AiEngine.api,
      });

  AiEngine engineFor(AiTask t) => engines[t] ?? AiEngine.local;

  AiSettings copyWith({
    Map<AiTask, AiEngine>? engines,
    ApiConfig? api,
    PrivacySettings? privacy,
    int? monthlyTokens,
  }) =>
      AiSettings(
        engines: engines ?? this.engines,
        api: api ?? this.api,
        privacy: privacy ?? this.privacy,
        monthlyTokens: monthlyTokens ?? this.monthlyTokens,
      );
}

/// Persists settings; the API key goes to the platform keystore, never to prefs.
class AiSettingsStore {
  AiSettingsStore({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();
  final FlutterSecureStorage _secure;

  static const _keyApi = 'api_key';

  Future<AiSettings> load() async {
    final p = await SharedPreferences.getInstance();
    final d = AiSettings.defaults();
    final engines = {
      for (final t in AiTask.values)
        t: AiEngine.values.byName(p.getString('engine_${t.name}') ?? d.engineFor(t).name)
    };
    final apiJson = p.getString('api_config');
    final month = _monthKey();
    return AiSettings(
      engines: engines,
      api: apiJson == null ? d.api : ApiConfig.fromJson(jsonDecode(apiJson)),
      privacy: PrivacySettings(
        maskPersonalData: p.getBool('priv_mask') ?? true,
        askBeforeSendingImage: p.getBool('priv_ask') ?? true,
        suggestApiRetry: p.getBool('priv_retry') ?? true,
        showTokenCounter: p.getBool('priv_tokens') ?? true,
      ),
      monthlyTokens: p.getInt('tokens_$month') ?? 0,
    );
  }

  Future<void> save(AiSettings s) async {
    final p = await SharedPreferences.getInstance();
    for (final e in s.engines.entries) {
      await p.setString('engine_${e.key.name}', e.value.name);
    }
    await p.setString('api_config', jsonEncode(s.api.toJson()));
    await p.setBool('priv_mask', s.privacy.maskPersonalData);
    await p.setBool('priv_ask', s.privacy.askBeforeSendingImage);
    await p.setBool('priv_retry', s.privacy.suggestApiRetry);
    await p.setBool('priv_tokens', s.privacy.showTokenCounter);
  }

  Future<void> addTokens(int n) async {
    final p = await SharedPreferences.getInstance();
    final k = 'tokens_${_monthKey()}';
    await p.setInt(k, (p.getInt(k) ?? 0) + n);
  }

  Future<String?> readKey() => _secure.read(key: _keyApi);
  Future<void> writeKey(String? key) => key == null || key.isEmpty
      ? _secure.delete(key: _keyApi)
      : _secure.write(key: _keyApi, value: key);

  static String _monthKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}';
  }
}
