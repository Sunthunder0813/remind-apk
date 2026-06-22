import 'dart:async';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/note.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/widget_service.dart';
import 'note_editor_screen.dart';
import 'notes_screen.dart' show showUndoToast;

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => CalendarScreenState();
}

// Public (no leading underscore) so HomeScreen can reach it via a GlobalKey
// and trigger "add reminder for the selected day" from the shared FAB —
// same pattern as NotesScreenState.
class CalendarScreenState extends State<CalendarScreen> {
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  List<Note> _notesWithReminders = [];

  // Live self-clear for the alarm icon on this tab's day list: re-arms
  // for whichever currently-loaded reminder note's reminderAt is
  // soonest, so the icon disappears the moment that note's reminder
  // passes while the user is just sitting on the Calendar tab — not only
  // on the next tab switch/day select that happens to re-trigger
  // _loadNotes(). Same pattern as NotesScreen's _reminderSweepTimer; the
  // actual clearing logic still lives in DatabaseService's sweep.
  Timer? _reminderSweepTimer;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void dispose() {
    _reminderSweepTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    // Plain getAllNotes() — no box close/reopen needed here. Within this
    // (main) isolate, _notesBox already reflects every write made via
    // DatabaseService, so there's no staleness to fix; the close/reopen
    // "fresh" read only matters for picking up a write made by a
    // DIFFERENT isolate (the home screen widget's background callback).
    // Calling getAllNotesFresh() here — on every tab switch/build — used
    // to close the box other in-flight saves/deletes were using, which is
    // what was causing notes to silently fail to save or delete.
    final notes = DatabaseService.instance.getAllNotes();
    if (!mounted) return;
    setState(() {
      _notesWithReminders = notes
          .where((n) => n.isCalendarReminder == true)
          .toList();
    });
    _scheduleReminderSweep();
  }

  // Finds the soonest still-future reminderAt among currently loaded
  // reminder notes and arms a one-shot Timer for exactly that moment
  // (capped at 1 minute so a far-future reminder doesn't sit on one
  // giant Timer). When it fires, _loadNotes() re-runs, which re-reads
  // from DatabaseService — that read is what actually sweeps the
  // now-expired reminderAt to null and removes the alarm icon.
  void _scheduleReminderSweep() {
    _reminderSweepTimer?.cancel();

    final now = DateTime.now();
    DateTime? soonest;
    for (final note in _notesWithReminders) {
      final r = note.reminderAt;
      if (r != null && r.isAfter(now)) {
        if (soonest == null || r.isBefore(soonest)) soonest = r;
      }
    }
    if (soonest == null) return;

    final remaining = soonest.difference(now);
    final wait = remaining < const Duration(minutes: 1) ? remaining : const Duration(minutes: 1);
    _reminderSweepTimer = Timer(wait, _loadNotes);
  }

  // Public refresh hook so the open calendar tab can react to widget
  // toggles and other background writes immediately.
  void reloadFromStorage() {
    if (!mounted) return;
    _loadNotes();
  }

  List<Note> _notesForDay(DateTime day) {
    return _notesWithReminders.where((note) {
      // Calendar-created notes group by calendarDate (works even with no
      // reminder time set). Anything else (shouldn't normally reach this
      // list, but kept as a fallback) groups by reminderAt's date.
      final groupDate = note.calendarDate ?? note.reminderAt;
      if (groupDate == null) return false;
      return groupDate.year == day.year &&
          groupDate.month == day.month &&
          groupDate.day == day.day;
    }).toList();
  }

  List<Note> _eventLoader(DateTime day) => _notesForDay(day);

  Future<void> _openEditor(Note note) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)),
    );
    if (saved == true) _loadNotes();
  }

  // Opens the real note editor for the currently selected calendar day.
  // The date is implicit (passed as initialCalendarDate) — the reminder
  // bell starts empty; the user can optionally tap it to set a time.
  // Public so HomeScreen's FAB can call it directly when the Calendar tab
  // is active.
  Future<void> addReminderForSelectedDay() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          isCalendarReminder: true,
          initialCalendarDate: DateTime(
            _selectedDay.year,
            _selectedDay.month,
            _selectedDay.day,
          ),
        ),
      ),
    );
    if (saved == true) {
      _loadNotes();
      WidgetService.refreshWidget(DatabaseService.instance.getAllNotes());
    }
  }

  // Flips a note's completed state and persists it immediately. Note
  // extends HiveObject so note.save() writes straight back to its
  // existing Hive record — no need to go through DatabaseService.saveNote.
  Future<void> _toggleCompleted(Note note) async {
    setState(() {
      note.isCompleted = !note.isCompleted;
    });
    await DatabaseService.instance.saveNote(note);
  }

  // Swipe-left delete: removes immediately from Hive, with Undo restoring
  // it by saving the same note object straight back. Mirrors
  // NotesScreen's _swipeDeleteNote, minus the archive direction and the
  // background-image cleanup (calendar reminders don't carry themes).
  Future<void> _swipeDeleteNote(Note note) async {
    setState(() => _notesWithReminders.removeWhere((n) => n.id == note.id));

    await NotificationService.instance.cancelNoteReminder(note.id);
    await DatabaseService.instance.deleteNote(note.id);

    if (!mounted) return;
    showUndoToast(context, '"${note.title}" deleted', onUndo: () async {
      await DatabaseService.instance.saveNote(note);
      if (note.reminderAt != null && note.reminderAt!.isAfter(DateTime.now())) {
        await NotificationService.instance.scheduleNoteReminder(
          noteId: note.id,
          title: note.title,
          body: note.content.isNotEmpty ? note.content : 'You have a reminder.',
          scheduledAt: note.reminderAt!,
        );
      }
      _loadNotes();
      WidgetService.refreshWidget(DatabaseService.instance.getAllNotes());
    });
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour == 0
        ? 12
        : dt.hour > 12
            ? dt.hour - 12
            : dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  // Short readable label for the selected day, e.g. "Jun 19"
  String _formatSelectedDay(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final selectedNotes = _notesForDay(_selectedDay);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ── Calendar widget ──────────────────────────────────────────────
        TableCalendar<Note>(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          eventLoader: _eventLoader,
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          onPageChanged: (focusedDay) {
            _focusedDay = focusedDay;
          },
          calendarFormat: CalendarFormat.month,
          availableCalendarFormats: const {CalendarFormat.month: 'Month'},
          calendarStyle: CalendarStyle(
            markerDecoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            selectedDecoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            todayDecoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            todayTextStyle: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
          headerStyle: HeaderStyle(
            titleCentered: true,
            titleTextStyle: TextStyle(
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            leftChevronIcon: Icon(Icons.chevron_left, color: colorScheme.primary),
            rightChevronIcon: Icon(Icons.chevron_right, color: colorScheme.primary),
            formatButtonVisible: false,
          ),
        ),

        const Divider(height: 1),

        // ── Selected-day header ────────────────────────────────────────────
        // Adding a reminder is now done exclusively via the shared FAB.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            _formatSelectedDay(_selectedDay),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),

        // ── Notes list for selected day ──────────────────────────────────
        Expanded(
          child: selectedNotes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.event_available,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No reminders on this day',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: selectedNotes.length,
                  itemBuilder: (_, index) {
                    final note = selectedNotes[index];
                    return Dismissible(
                      key: ValueKey('calendar_note_${note.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF8A80), Color(0xFFE53935)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                      ),
                      confirmDismiss: (_) async {
                        await _swipeDeleteNote(note);
                        return true;
                      },
                      child: Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: ListTile(
                          leading: GestureDetector(
                            onTap: () => _toggleCompleted(note),
                            child: CircleAvatar(
                              backgroundColor: note.isCompleted
                                  ? colorScheme.primary
                                  : colorScheme.primaryContainer,
                              child: Icon(
                                note.isCompleted
                                    ? Icons.check
                                    : Icons.alarm,
                                color: note.isCompleted
                                    ? Colors.white
                                    : colorScheme.primary,
                                size: 20,
                              ),
                            ),
                          ),
                          title: Text(
                            note.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              decoration: note.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: note.isCompleted
                                  ? Colors.grey.shade500
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            note.reminderAt != null
                                ? _formatTime(note.reminderAt!)
                                : 'No time set',
                            style: TextStyle(
                              color: note.isCompleted
                                  ? Colors.grey.shade500
                                  : colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          onTap: () => _openEditor(note),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
