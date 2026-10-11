import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../ai/ai_settings.dart';
import '../ai/diet_ai.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'common.dart';
import 'food_search_screen.dart';

/// Photo of a label -> AI reads name/macros/ingredients -> user confirms or
/// fixes -> saved for next time. Returns the saved food (without logging it).
Future<Food?> labelToFood(BuildContext context, WidgetRef ref, {String? barcode, bool askSource = true}) async {
  final ai = await ref.read(aiSettingsProvider.notifier).dietAi();
  if (!context.mounted) return null;
  final canRead = ai.canRun(AiTask.estimation);
  ImageSource? source = ImageSource.camera;
  if (askSource) {
    source = await showModalBottomSheet<ImageSource>(
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
  }
  if (!context.mounted) return null;

  LabelData? data;
  if (source != null) {
    if (!canRead) {
      toast(context, 'Odczyt zdjęć wymaga AI: model z obsługą obrazu (Ja → Lokalne AI) albo API. Wpisz ręcznie.');
    } else {
      final img = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (img == null || !context.mounted) return null;
      final bytes = await img.readAsBytes();
      if (!context.mounted) return null;
      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
      try {
        data = await ai.readLabel(bytes);
      } catch (e) {
        if (context.mounted) toast(context, 'Nie udało się odczytać: $e. Uzupełnij ręcznie.');
      }
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }
  if (!context.mounted) return null;

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
  // Always confirm: OCR of labels is error-prone.
  final food = await showCustomFoodDialog(context, barcode: barcode, initial: initial);
  if (food == null) return null;
  final id = await ref.read(dbProvider).saveFood(food);
  return Food.fromMap({...food.toMap(), 'id': id});
}

/// What to do with a product that was just scanned or read.
Future<bool> foodActions(BuildContext context, WidgetRef ref, Food f) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(f.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${n0(f.kcal100)} kcal/100 g · ${macroText(Macros(p: f.p100, c: f.c100, f: f.f100))}${f.estimated ? ' · ~' : ''}',
              style: const TextStyle(color: AppColors.muted)),
          if (f.ingredients.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Skład: ${f.ingredients}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: () => Navigator.pop(ctx, 'eat'), icon: const Icon(Icons.restaurant), label: const Text('Zjadłem — dodaj do dziennika')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: () => Navigator.pop(ctx, 'cart'), icon: const Icon(Icons.add_shopping_cart), label: const Text('Do koszyka (zakupy)')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Center(child: Text('Tylko zapisz i skanuj dalej'))),
        ]),
      ),
    ),
  );
  if (!context.mounted || action == null) return false;
  if (action == 'cart') {
    await ref.read(shoppingProvider.notifier).add(['0|${f.title}']);
    if (context.mounted) toast(context, 'Dodano do zakupów: ${f.title}');
    return true;
  }
  final g = await askGrams(context, f);
  if (g == null) return false;
  await ref.read(foodLoggerProvider).addFood(f, g, when: ref.read(selectedDayProvider));
  if (context.mounted) toast(context, 'Dodano: ${f.title}');
  return true;
}

/// Legacy single-shot flow used from the search screen.
Future<bool> scanLabelFlow(BuildContext context, WidgetRef ref, {String? barcode}) async {
  final f = await labelToFood(context, ref, barcode: barcode);
  if (f == null || !context.mounted) return false;
  return foodActions(context, ref, f);
}
