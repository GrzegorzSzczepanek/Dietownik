import 'package:home_widget/home_widget.dart';

import 'data/db.dart';
import 'domain/models.dart';

/// Pushes today's numbers to the Android home-screen widget.
Future<void> syncHomeWidget(AppDb db, Goals goals) async {
  try {
    final entries = await db.entriesFor(dayKey(DateTime.now()));
    final eaten = entries.fold<double>(0, (a, e) => a + e.macros.kcal);
    final left = goals.kcal - eaten;
    final over = left < 0;
    await HomeWidget.saveWidgetData<String>('left', left.abs().round().toString());
    await HomeWidget.saveWidgetData<String>('label', over ? 'kcal ponad plan' : (eaten == 0 ? 'kcal na dziś' : 'kcal zostało'));
    await HomeWidget.saveWidgetData<int>('progress', goals.kcal == 0 ? 0 : (eaten / goals.kcal * 100).clamp(0, 100).round());
    await HomeWidget.updateWidget(androidName: 'DietownikWidgetProvider');
  } catch (_) {
    // The widget is a convenience; never let it break the app.
  }
}
