package pl.gsk.dietownik

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Home-screen widget: calories left today plus three one-tap actions (speak, scan, eyeball entry). */
class DietownikWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_dietownik).apply {
                setTextViewText(R.id.widget_left, widgetData.getString("left", "2000"))
                setTextViewText(R.id.widget_label, widgetData.getString("label", "kcal na dziś"))
                setProgressBar(R.id.widget_progress, 100, widgetData.getInt("progress", 0), false)
                setOnClickPendingIntent(R.id.widget_say, launch(context, "mic"))
                setOnClickPendingIntent(R.id.widget_scan, launch(context, "scan"))
                setOnClickPendingIntent(R.id.widget_eye, launch(context, "oko"))
                setOnClickPendingIntent(R.id.widget_root, launch(context, "home"))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun launch(context: Context, action: String) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("dietownik://$action"))
}
