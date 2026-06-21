package com.example.remind

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

class TodoWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val widgetData = HomeWidgetPlugin.getData(context)
            val rowsJson = widgetData.getString("todo_rows", "[]") ?: "[]"

            val views = RemoteViews(context.packageName, R.layout.todo_widget_layout)

            // Set up the RemoteViews collection (ListView) for checklist rows.
            // The factory (TodoRemoteViewsFactory) reads todo_rows fresh from
            // HomeWidgetPlugin's SharedPreferences itself in onDataSetChanged()
            // — it does NOT read it from this intent — so there's no need to
            // (and we must not) stuff rowsJson into the intent as if that were
            // the data source; doing so was misleading and unused.
            val serviceIntent = Intent(context, TodoRemoteViewsService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                // Unique per appWidgetId so Android never treats two widget
                // instances' RemoteViewsFactory as interchangeable/cacheable
                // against each other.
                data = android.net.Uri.parse("remind://widget/$appWidgetId")
            }
            views.setRemoteAdapter(R.id.widget_list_view, serviceIntent)
            views.setEmptyView(R.id.widget_list_view, R.id.widget_empty_text)

            // Pending intent template — each row fills in its own noteId+itemId
            val toggleIntent = Intent(context, TodoToggleReceiver::class.java)
            val togglePendingIntent = android.app.PendingIntent.getBroadcast(
                context,
                0,
                toggleIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_MUTABLE
            )
            views.setPendingIntentTemplate(R.id.widget_list_view, togglePendingIntent)

            // Tap the header → open the app
            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            val launchPending = android.app.PendingIntent.getActivity(
                context, 1, launchIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_header, launchPending)

            // Commit the RemoteViews to the actual widget FIRST.
            appWidgetManager.updateAppWidget(appWidgetId, views)

            // THEN force the ListView's adapter/factory to refetch fresh data.
            // Calling this BEFORE updateAppWidget (as before) raced against
            // the widget instance still running its previous factory/intent —
            // that ordering bug is what caused only one note's rows to ever
            // appear: whichever refresh's notifyAppWidgetViewDataChanged call
            // landed last against a half-committed widget state "won," and
            // the other note's rows were silently dropped instead of both
            // appearing together.
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_list_view)
        }
    }
}