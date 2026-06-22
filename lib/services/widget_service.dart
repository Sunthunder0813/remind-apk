import 'dart:convert';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import '../models/note.dart';
import '../models/checklist_item.dart' as model;
import 'database_service.dart';

// Must match the name registered in main.dart exactly.
const String _kChecklistUpdatePortName = 'remind_checklist_update_port';

class WidgetService {
  static const String _androidWidgetName = 'TodoWidgetProvider';

  static String _formatWidgetTime(DateTime dt) {
    final hour = dt.hour == 0
        ? 12
        : dt.hour > 12
            ? dt.hour - 12
            : dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  // Each note becomes a grouped widget block:
  // - note header row (title + time, if any)
  // - one row per checklist item
  // - separator row between notes
  // The native RemoteViewsFactory reads this JSON straight out of
  // home_widget's SharedPreferences store.
  static Future<void> refreshWidget(List<Note> allNotes) async {
    final now = DateTime.now();
    
    final todayNotes = allNotes.where((n) {
      if (n.isCalendarReminder != true) return false;
      final groupDate = n.calendarDate ?? n.reminderAt;
      return groupDate != null &&
          groupDate.year == now.year &&
          groupDate.month == now.month &&
          groupDate.day == now.day;
    }).toList()
      // allNotes (from getAllNotes()) is sorted by updatedAt descending,
      // which would otherwise make a note jump to the top of the widget
      // the instant it's opened/autosaved. createdAt is stable across
      // edits, keeping widget row order matching the Calendar tab's.
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    debugPrint('[WidgetRefresh] allNotes count: ${allNotes.length}');
    debugPrint('[WidgetRefresh] todayNotes ids: ${todayNotes.map((n) => n.id).toList()}');

    final rows = <Map<String, dynamic>>[];
    for (var index = 0; index < todayNotes.length; index++) {
      final note = todayNotes[index];
      final groupDate = note.reminderAt ?? note.calendarDate;
      final totalCount = note.checklistItems.length;
      final doneCount = note.checklistItems.where((i) => i.done).length;
      final taskCount = totalCount == 0
          ? null
          : (doneCount == totalCount ? 'Completed' : '$doneCount/$totalCount');

      rows.add({
        'type': 'header',
        'noteId': note.id,
        'title': note.title,
        'time': groupDate != null && note.reminderAt != null
            ? _formatWidgetTime(groupDate)
            : null,
        'taskCount': taskCount,
      });

      if (note.checklistItems.isNotEmpty) {
        for (final item in note.checklistItems) {
          rows.add({
            'type': 'item',
            'noteId': note.id,
            'itemId': item.id,
            'text': item.text,
            'done': item.done,
          });
        }
      } else if (note.content.trim().isNotEmpty) {
        // Only add a sub-row when there's real body text to show as a
        // detail line under the title. This is plain note content, not
        // a checklist item, so it must render with NO checkbox and NO
        // tap-to-toggle behavior — hence the distinct 'detail' type
        // instead of reusing 'item'. A note with no checklist AND no
        // content (just a bare title, e.g. "Untitled") gets no sub-row
        // at all — just the header.
        rows.add({
          'type': 'detail',
          'noteId': note.id,
          'text': note.content.trim(),
        });
      }

      if (index != todayNotes.length - 1) {
        rows.add({
          'type': 'separator',
        });
      }
    }

    debugPrint('[WidgetRefresh] FINAL rows being written (${rows.length} total): '
        '${rows.map((r) => '${r['type']}:${r['title'] ?? r['text']}').toList()}');
    await HomeWidget.saveWidgetData<String>('todo_rows', jsonEncode(rows));
    await HomeWidget.updateWidget(name: _androidWidgetName);
  }

  // Reads the pending checkbox-tap signal written by the native
  // TodoToggleReceiver, applies it to the real Hive Note/ChecklistItem,
  // clears the signal, then pushes a fresh refresh so the widget redraws.
  // Guards against the SAME signal being processed twice — seen in
  // testing as two widgetBackgroundCallback wake-ups ~300ms apart for one
  // tap (the underlying Android job-delivery mechanism redelivering, not
  // anything in our broadcast/debounce code — that layer was confirmed
  // firing exactly once). Without this, a second invocation can read the
  // note BEFORE the first invocation's write lands, flip its own stale
  // copy, and silently cancel the first toggle out — net result: tap the
  // widget, nothing changes. Tracking the last-claimed raw signal string
  // (not just a boolean) means a genuinely NEW toggle right after is
  // never blocked, only an exact repeat of the same not-yet-superseded one.
  static Future<void> applyPendingToggle() async {
    final raw = await HomeWidget.getWidgetData<String>('pending_toggle');
    debugPrint('[TodoToggle] applyPendingToggle read: $raw');
    if (raw == null || raw.isEmpty) {
      debugPrint('[TodoToggle] nothing pending — bailing out');
      return;
    }

    // Clear the signal FIRST before processing — this is the dedup guard.
    // If two callbacks wake up for the same tap, the second one reads ''
    // and bails out cleanly, rather than the old static-variable approach
    // which persisted across isolate restarts and blocked future toggles.
    await HomeWidget.saveWidgetData<String>('pending_toggle', '');
    await HomeWidget.updateWidget(name: _androidWidgetName);

    final Map<String, dynamic> signal = jsonDecode(raw);
    final String? noteId = signal['noteId'] as String?;
    final String? itemId = signal['itemId'] as String?;
    if (noteId == null) return;

    final note = DatabaseService.instance.getNoteById(noteId);
    if (note == null) {
      debugPrint('[TodoToggle] note $noteId no longer exists — skipping (likely deleted)');
      return;
    }

    if (itemId == null) {
      note.isCompleted = !note.isCompleted;
    } else {
      final items = note.checklistItems;
      final index = items.indexWhere((i) => i.id == itemId);
      if (index == -1) {
        debugPrint('[TodoToggle] itemId $itemId not found in note $noteId');
        return;
      }
      // Hive lazy-loads list items — mutating in place doesn't mark the
      // object dirty. Rebuild the entire list with the one item flipped
      // so saveNote sees a real change and writes it through.
      final oldItem = items[index];
      debugPrint('[TodoToggle] flipping item ${oldItem.id} done: ${oldItem.done} -> ${!oldItem.done}');
      note.checklistItems = [
        for (int i = 0; i < items.length; i++)
          if (i == index)
            model.ChecklistItem(
              id: oldItem.id,
              text: oldItem.text,
              done: !oldItem.done,
            )
          else
            items[i],
      ];
    }

    // Re-check the note still exists right before writing — closes the
    // race where this note was deleted (e.g. swiped away on the Calendar
    // tab) WHILE this background isolate was already mid-flight between
    // its read above and this write. Without this, a stale toggle signal
    // can resurrect a note the user already deleted.
    final stillExists = DatabaseService.instance.getNoteById(noteId) != null;
    if (!stillExists) {
      debugPrint('[TodoToggle] note $noteId was deleted mid-toggle — discarding stale write');
      return;
    }

    await DatabaseService.instance.saveNote(note);
    debugPrint('[TodoToggle] save complete');

    // Push an instant notification to the main UI isolate, if it's alive
    // and listening (i.e. the app is running, registered in main.dart).
    // SendPort.send() is fire-and-forget and safe to call even if nothing
    // is listening — it just silently does nothing in that case, so this
    // never throws or blocks even if the app is fully closed.
    final mainIsolatePort = IsolateNameServer.lookupPortByName(_kChecklistUpdatePortName);
    mainIsolatePort?.send({'noteId': noteId, 'itemId': itemId});
  }
}

// Wakes in a fresh background isolate whenever a widget checkbox is
// tapped — must stay top-level, public, and keep the @pragma or
// home_widget silently fails to find it.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  debugPrint('[TodoToggle] widgetBackgroundCallback woke up, uri=$uri');
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService.instance.init();
  // Unconditional re-read from disk — see refreshNotesBoxFromDisk's doc
  // comment. init() alone isn't enough here because this isolate may be
  // a REUSED one from an earlier tap, in which case init() no-ops and
  // this isolate would otherwise keep acting on a stale, earlier-opened
  // Box snapshot that doesn't know about notes created/edited since.
  await DatabaseService.instance.refreshNotesBoxFromDisk();
  await WidgetService.applyPendingToggle();
  debugPrint('[TodoToggle] widgetBackgroundCallback finished');
}
