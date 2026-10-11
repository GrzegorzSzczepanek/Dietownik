import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dietownik is Polish-first; the few strings shared with the copied AI
/// settings screens live here.
class AppStrings {
  const AppStrings();
  bool get isEnglish => false;
  String get apiProvider => 'Dostawca API';
  String get cancel => 'Anuluj';
  String get save => 'Zapisz';
  String get testConnection => 'Testuj połączenie';
}

final appStringsProvider = Provider<AppStrings>((ref) => const AppStrings());
