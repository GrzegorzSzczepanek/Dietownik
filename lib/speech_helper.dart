import 'package:speech_to_text/speech_to_text.dart';

/// Turns the Android recognizer's error code into something a person can act on.
String speechErrorText(String code) {
  final c = code.toLowerCase();
  final hint = switch (c) {
    String s when s.contains('no_match') => 'Nie rozpoznałem mowy. Powiedz głośniej i dotknij mikrofon, żeby spróbować ponownie.',
    String s when s.contains('speech_timeout') => 'Nic nie usłyszałem. Zacznij mówić od razu po dotknięciu mikrofonu.',
    String s when s.contains('network') || s.contains('server') => 'Rozpoznawanie mowy potrzebuje internetu. Sprawdź połączenie i spróbuj ponownie.',
    String s when s.contains('audio') => 'Mikrofon jest zajęty albo niedostępny. Zamknij inne aplikacje, które go używają.',
    String s when s.contains('permission') => 'Brak zgody na mikrofon. Włącz ją w ustawieniach telefonu dla Dietownika.',
    String s when s.contains('busy') => 'Rozpoznawanie jest zajęte. Dotknij mikrofon po chwili.',
    String s when s.contains('language') => 'Telefon nie ma polskiego rozpoznawania mowy. Pobierz je w Ustawienia → Google → Mowa (lub w aplikacji Google).',
    _ => 'Rozpoznawanie mowy nie zadziałało. Dotknij mikrofon, żeby spróbować jeszcze raz.',
  };
  return '$hint ($code)';
}

/// Picks the phone's Polish voice-recognition locale, whatever it is called there
/// (pl_PL, pl-PL). Returns null to let the system default decide.
Future<String?> pickPolishLocale(SpeechToText stt) async {
  try {
    final all = await stt.locales();
    for (final l in all) {
      if (l.localeId.toLowerCase().replaceAll('-', '_').startsWith('pl')) return l.localeId;
    }
  } catch (_) {}
  return null;
}

const speechUnavailableText =
    'Telefon nie udostępnia rozpoznawania mowy. Zainstaluj lub zaktualizuj aplikację Google, włącz zgodę na mikrofon, albo wpisz posiłek.';
