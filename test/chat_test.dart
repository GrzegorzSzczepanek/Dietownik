import 'dart:typed_data';

import 'package:dietownik/ai/ai_settings.dart';
import 'package:dietownik/ai/chat_ai.dart';
import 'package:dietownik/ai/diet_ai.dart';
import 'package:dietownik/ai/llm_api.dart';
import 'package:dietownik/ai/local_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLlm implements LlmApi {
  _FakeLlm(this.reply);
  final String reply;
  String? lastUser;
  @override
  Future<LlmResult> complete({required String system, required String user, Uint8List? image, String imageMime = 'image/jpeg', bool json = false, int maxTokens = 2048}) async {
    lastUser = user;
    return LlmResult(reply);
  }
}

void main() {
  DietAi ai(_FakeLlm llm) => DietAi(settings: AiSettings.defaults(), llm: llm, local: const UnavailableLocalRuntime());

  test('chat parses answer, recipe card and suggestions', () async {
    final llm = _FakeLlm('''{"answer":"Zrób omlet [1].","recipe":{"title":"Omlet","kcal":420,"p":31,"c":6,"f":30,"note":"szacunek","ingredients":["3 jajka"],"missing":["masło"]},"suggestions":["Coś bez jajek"],"used":["lodówka"]}''');
    final r = await ai(llm).chat(question: 'kolacja?', history: const [], context: 'LODÓWKA: jajka', webSearch: false);
    expect(r.answer, contains('omlet'));
    expect(r.recipe?.title, 'Omlet');
    expect(r.recipe?.missing, ['masło']);
    expect(r.suggestions, ['Coś bez jajek']);
    expect(r.searched, isFalse);
    expect(llm.lastUser, contains('LODÓWKA: jajka'));
    expect(llm.lastUser, contains('brak'));
  });

  test('plain text reply still becomes an answer', () async {
    final r = await ai(_FakeLlm('Po prostu zjedz coś białkowego.')).chat(question: 'x', history: const [], context: '', webSearch: false);
    expect(r.answer, contains('białkowego'));
    expect(r.recipe, isNull);
  });

  test('source host strips www', () {
    expect(const ChatSource('t', 'https://www.example.com/a', '').host, 'example.com');
  });
}
