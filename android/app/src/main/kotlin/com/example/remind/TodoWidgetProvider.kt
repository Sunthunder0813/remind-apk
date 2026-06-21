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

            // Set up the RemoteViews collection (ListView) for checklist rows
            val serviceIntent = Intent(context, TodoRemoteViewsService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                putExtra("todo_rows", rowsJson)
            }
            views.setRemoteAdapter(R.id.widget_list_view, serviceIntent)
            views.setEmptyView(R.id.widget_list_view, R.id.widget_empty_text)

            // setRemoteAdapter alone doesn't reliably force the factory's
            // onDataSetChanged() to re-run on every Android version/launcher
            // if it decides the adapter intent "hasn't changed" — that's
            // why a delete from the Calendar tab (which only goes through
            // HomeWidget.updateWidget() -> onUpdate() -> here) could leave
            // a stale row visible, while the toggle path (which calls
            // notifyAppWidgetViewDataChanged directly from Kotlin) always
            // worked. Forcing it here covers every caller of updateWidget,
            // not just the toggle-specific one in TodoToggleReceiver.
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_list_view)

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

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}