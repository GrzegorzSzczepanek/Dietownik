import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../ai/ai_settings.dart';
import '../ai/diet_ai.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'common.dart';
import 'food_search_screen.dart';

/// Photo of a nutrition label -> AI reads name/macros/ingredients -> user
/// confirms or fixes -> saved for next time -> logged. Returns true if logged.
Future<bool> scanLabelFlow(BuildContext context, WidgetRef ref, {String? barcode}) async {
  final ai = await ref.read(aiSettingsProvider.notifier).dietAi();
  if (!context.mounted) return false;
  final canRead = ai.canRun(AiTask.estimation);
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Sfotografuj tabelę wartości odżywczych (najlepiej razem ze składem)', textAlign: TextAlign.center),
        ),
        ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Zrób zdjęcie'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library), title: const Text('Wybierz z galerii'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ListTile(leading: const Icon(Icons.edit), title: const Text('Wpisz ręcznie'), onTap: () => Navigator.pop(ctx)),
      ]),
    ),
  );
  if (!context.mounted) return false;

  LabelData? data;
  if (source != null) {
    if (!canRead) {
      toast(context, 'Odczyt zdjęć wymaga AI: wybierz model z obsługą obrazu (Ja → Lokalne AI) albo API. Wpisz ręcznie.');
    } else {
      final img = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (img == null || !context.mounted) return false;
      final bytes = await img.readAsBytes();
      if (!context.mounted) return false;
      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
      try {
        data = await ai.readLabel(bytes);
      } catch (e) {
        if (context.mounted) toast(context, 'Nie udało się odczytać: $e. Uzupełnij ręcznie.');
      }
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }
  if (!context.mounted) return false;

  final initial = data == null
      ? null
      : Food(
          name: data.name,
          brand: data.brand,
          barcode: barcode,
          kcal100: data.kcal100 ?? 0,
          p100: data.p100 ?? 0,
          c100: data.c100 ?? 0,
          f100: data.f100 ?? 0,
          servingG: data.servingG ?? 100,
          ingredients: data.ingredients,
          source: 'ai');
  // Always show the result for confirmation: OCR of labels is error-prone.
  final food = await showCustomFoodDialog(context, barcode: barcode, initial: initial);
  if (food == null || !context.mounted) return false;
  final id = await ref.read(dbProvider).saveFood(food);
  final saved = Food.fromMap({...food.toMap(), 'id': id});
  final g = await askGrams(context, saved);
  if (g == null) return false;
  await ref.read(foodLoggerProvider).addFood(saved, g, when: ref.read(selectedDayProvider));
  if (context.mounted) toast(context, 'Zapisano i dodano: ${saved.title}');
  return true;
}
