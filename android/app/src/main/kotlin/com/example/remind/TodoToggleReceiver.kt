package com.example.remind

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONObject

class TodoToggleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val noteId = intent.getStringExtra("noteId") ?: return
        val itemId = intent.getStringExtra("itemId")?.takeIf { it.isNotEmpty() }
        val isItemToggle = intent.getBooleanExtra("isItemToggle", false)

        // Write the pending toggle signal into SharedPreferences so the
        // Dart background callback can read it, apply it to Hive, and
        // push a fresh widget refresh — never write Hive from Kotlin.
        val signal = JSONObject().apply {
            put("noteId", noteId)
            if (isItemToggle && itemId != null) put("itemId", itemId)
            else put("itemId", JSONObject.NULL)
        }

        HomeWidgetPlugin.getData(context)
            .edit()
            .putString("pending_toggle", signal.toString())
            .apply()

        // Wake the Dart background callback
        es.antonborri.home_widget.HomeWidgetBackgroundIntent.getBroadcast(
            context,
            android.net.Uri.parse("remindApp://widgetToggle")
        ).send()

        // Notify the widget to redraw (the Dart callback will do a full
        // refresh, but this nudges the ListView to reload immediately)
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(
            ComponentName(context, TodoWidgetProvider::class.java)
        )
        manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list_view)
    }
}