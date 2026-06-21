package com.example.remind

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray

class TodoRemoteViewsService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return TodoRemoteViewsFactory(applicationContext, intent)
    }
}

class TodoRemoteViewsFactory(
    private val context: Context,
    intent: Intent
) : RemoteViewsService.RemoteViewsFactory {

    private val rows = mutableListOf<TodoRow>()

    data class TodoRow(
        val type: String,
        val noteId: String,
        val itemId: String? = null,
        val title: String? = null,
        val time: String? = null,
        val taskCount: String? = null,
        val text: String? = null,
        val done: Boolean = false
    )

    override fun onCreate() {}

    override fun onDataSetChanged() {
        rows.clear()
        try {
            val rowsJson = es.antonborri.home_widget.HomeWidgetPlugin
                .getData(context)
                .getString("todo_rows", "[]") ?: "[]"
            val arr = JSONArray(rowsJson)
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                // Separator rows only ever carry {"type": "separator"} — no
                // noteId/title/etc. Reading those fields unconditionally
                // with getString() threw a JSONException ("No value for
                // noteId") the moment the parser hit a separator, and that
                // exception was silently swallowed by the outer try/catch
                // below, leaving `rows` with only whatever had been parsed
                // BEFORE the crash. Since the separator sits between the
                // two notes, this is exactly why the second note's header
                // and checklist items were always missing — they were
                // never actually parsed at all, not a rendering issue.
                // optString()/has() everywhere makes every field optional
                // and tolerant of rows that don't carry it.
                rows.add(
                    TodoRow(
                        type = obj.optString("type", "item"),
                        noteId = obj.optString("noteId", ""),
                        itemId = if (obj.has("itemId") && !obj.isNull("itemId")) obj.getString("itemId") else null,
                        title = if (obj.has("title") && !obj.isNull("title")) obj.getString("title") else null,
                        time = if (obj.has("time") && !obj.isNull("time")) obj.getString("time") else null,
                        taskCount = if (obj.has("taskCount") && !obj.isNull("taskCount")) obj.getString("taskCount") else null,
                        text = if (obj.has("text") && !obj.isNull("text")) obj.getString("text") else null,
                        done = if (obj.has("done") && !obj.isNull("done")) obj.getBoolean("done") else false
                    )
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {}

    override fun getCount() = rows.size

    override fun getViewAt(position: Int): RemoteViews {
        val row = rows[position]
        return when (row.type) {
            "header" -> {
                val views = RemoteViews(context.packageName, R.layout.todo_widget_header_row)
                views.setTextViewText(R.id.note_title, row.title ?: "")
                views.setTextViewText(R.id.note_time, row.time ?: "")
                views.setViewVisibility(
                    R.id.note_time,
                    if (row.time.isNullOrEmpty()) android.view.View.GONE else android.view.View.VISIBLE
                )
                views.setTextViewText(R.id.note_count_badge, row.taskCount ?: "")
                views.setViewVisibility(
                    R.id.note_count_badge,
                    if (row.taskCount.isNullOrEmpty()) android.view.View.GONE else android.view.View.VISIBLE
                )
                views
            }
            "separator" -> RemoteViews(context.packageName, R.layout.todo_widget_separator_row)
            else -> {
                val views = RemoteViews(context.packageName, R.layout.todo_widget_row)

                views.setTextViewText(R.id.row_text, row.text ?: "")

                // Checkbox icon — filled if done, outline if not. Uses our own
                // vector drawables (android.R.drawable.checkbox_on/off_background
                // are legacy "background layer" assets meant to sit behind a real
                // CheckBox widget's foreground — used alone in an ImageView they
                // render as invisible/blank on most themes, which is why nothing
                // appeared to change on tap even though the underlying done value
                // was flipping correctly.
                val iconRes = if (row.done)
                    R.drawable.todo_checkbox_checked
                else
                    R.drawable.todo_checkbox_unchecked

                views.setImageViewResource(R.id.row_checkbox, iconRes)

                // Strikethrough text when done
                val paintFlags = if (row.done)
                    android.graphics.Paint.STRIKE_THRU_TEXT_FLAG or android.graphics.Paint.ANTI_ALIAS_FLAG
                else
                    android.graphics.Paint.ANTI_ALIAS_FLAG
                views.setInt(R.id.row_text, "setPaintFlags", paintFlags)

                // Fill in the intent template with this row's ids
                val fillIntent = Intent().apply {
                    putExtra("noteId", row.noteId)
                    putExtra("itemId", row.itemId ?: "")
                    putExtra("isItemToggle", row.itemId != null)
                }
                views.setOnClickFillInIntent(R.id.row_root, fillIntent)

                views
            }
        }
    }

    override fun getLoadingView() = null
    override fun getViewTypeCount() = 3
    override fun getItemId(position: Int) = position.toLong()
    override fun hasStableIds() = true
}
