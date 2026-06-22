import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/note.dart';
import '../models/checklist_item.dart' as model;
import 'dart:convert';
import 'package:home_widget/home_widget.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/ai_suggestion_service.dart';
import '../main.dart' show checklistUpdateStream;

// This screen is used for both creating a new note and editing an existing one.
// If [note] is null, we're creating. If [note] is provided, we're editing.
class NoteEditorScreen extends StatefulWidget {
  final Note? note;
  final String? initialCategoryId;
  final DateTime? initialReminderAt;
  // When true, the whole screen is view-only — used for previewing an
  // archived note without allowing edits.
  final bool readOnly;
  // Set when this screen is opened from the Calendar tab's "New" flow.
  // Tags the resulting note as a calendar reminder (isCalendarReminder)
  // and stamps it with initialCalendarDate so it groups under that day
  // even before the user sets an actual reminder time.
  final bool isCalendarReminder;
  final DateTime? initialCalendarDate;

  const NoteEditorScreen({
    super.key,
    this.note,
    this.initialCategoryId,
    this.initialReminderAt,
    this.readOnly = false,
    this.isCalendarReminder = false,
    this.initialCalendarDate,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

// A single checklist row's UI state — wraps a persisted model.ChecklistItem
// (stable string id + text + done) with the TextEditingController/FocusNode
// the editor's widgets need. The string id is what the home screen widget
// will eventually use to address one specific item from outside the app,
// so it must survive save/reload unchanged — never regenerated.
class _ChecklistItem {
  final String id;
  final TextEditingController controller;
  final FocusNode focusNode;
  bool done;

  _ChecklistItem({required String text, bool done = false, String? id})
      : id = id ?? _generateId(),
        done = done,
        controller = TextEditingController(text: text),
        focusNode = FocusNode();

  static String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';
  static int _counter = 0;

  // Wraps an existing persisted item (editing an existing note) — keeps
  // its original id so the widget's toggle handler keeps working across
  // edits, rather than minting a new id every time the note is opened.
  _ChecklistItem.fromModel(model.ChecklistItem item)
      : id = item.id,
        controller = TextEditingController(text: item.text),
        focusNode = FocusNode(),
        done = item.done;

  model.ChecklistItem toModel() =>
      model.ChecklistItem(id: id, text: controller.text.trim(), done: done);
}

// A single undo/redo step — just the title and content text at a point
// in time. Checklist/reminder state is intentionally not included.
class _EditSnapshot {
  final String title;
  final String content;
  const _EditSnapshot(this.title, this.content);
}

class _NoteEditorScreenState extends State<NoteEditorScreen> with WidgetsBindingObserver {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _contentFocusNode = FocusNode();

  // Inherited silently from whichever folder the note was created inside —
  // no dropdown, never edited here.
  String? _selectedCategoryId;
  DateTime? _reminderAt;
  DateTime? _calendarDate;

  final List<_ChecklistItem> _checklistItems = [];

  // Ids of checklist items the user actually toggled (tapped the checkbox
  // for) during THIS editor session. Used by _buildChecklistItems to know
  // which items' `done` state this screen actually owns right now vs.
  // which ones are just sitting in stale in-memory state from initState —
  // without this, the periodic/debounced auto-save would blindly re-write
  // every item's `done` exactly as it was when the screen opened, silently
  // undoing any toggle made from outside (e.g. the home screen widget)
  // while this screen happened to still be alive in memory.
  final Set<String> _toggledItemIds = {};

  // Live AI read of the text — only decides whether to show the
  // "suggested time" chip, never applied automatically.
  DateTime? _suggestedReminder;

  bool get _isEditing => widget.note != null;

  // Debounce timer for auto-save — resets on every keystroke, only fires
  // ~1.2s after the user stops typing, so we're not hitting Hive on every
  // single character.
  Timer? _autoSaveTimer;
  bool _hasUnsavedChanges = false;

  // Belt-and-suspenders periodic save — fires every 10s regardless of
  // typing activity, as a safety net in case the debounce timer never
  // gets a quiet moment to fire (e.g. continuous typing) or the app is
  // killed before the debounce window elapses. Calls the same _autoSave,
  // which already no-ops if there's nothing unsaved or the note is empty.
  Timer? _periodicSaveTimer;
  bool _isPopping = false;

  // Live self-clear: if this screen is left open and the wall clock ticks
  // past _reminderAt while the user is still looking at it, the pill/bell
  // disappears without needing to leave and reopen the note. The
  // notification itself fires independently via NotificationService —
  // this timer only clears the note's own in-memory/persisted field.
  Timer? _reminderExpiryTimer;

  // Subscription to the global checklistUpdateStream (main.dart) — fed by
  // a raw isolate-to-isolate message the widget's background callback
  // sends via IsolateNameServer the moment a toggle is applied. This is
  // real push, not polling: earlier attempts used Hive's box.watch()
  // (doesn't cross isolates — see widget_service.dart for why) and then
  // a 2s Timer.periodic poll (worked, but had up to 2s of lag and ran
  // continuously whether or not anything changed).
  StreamSubscription? _checklistUpdateSubscription;

  // Background theme image, if the note has one set — read once at open
  // time. Themed entirely via this screen's own card-style "asset:"/"file:"
  // prefix scheme; not editable from here (set via NotesScreen's edit mode).
  String? _backgroundImagePath;

  // ── Undo/Redo (title + content text only) ──────────────────────────────
  // Snapshots are pushed on a pause in typing (debounced, like auto-save)
  // rather than on every keystroke — otherwise one undo step = one letter,
  // which is useless. _isApplyingHistory guards against the listener
  // re-recording a snapshot while we're the ones writing the text back in.
  final List<_EditSnapshot> _undoStack = [];
  final List<_EditSnapshot> _redoStack = [];
  Timer? _historyDebounceTimer;
  bool _isApplyingHistory = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (_isEditing) {
      _titleController.text = widget.note!.title;
      _selectedCategoryId = widget.note!.categoryId;
      _reminderAt = widget.note!.reminderAt;
      _calendarDate = widget.note!.calendarDate;
      _backgroundImagePath = widget.note!.backgroundImagePath;
      _contentController.text = widget.note!.content;
      _checklistItems.addAll(
        widget.note!.checklistItems.map((m) => _ChecklistItem.fromModel(m)),
      );
    } else {
      _selectedCategoryId = widget.initialCategoryId;
      _reminderAt = widget.initialReminderAt;
      _calendarDate = widget.initialCalendarDate;
    }

    _contentController.addListener(_analyzeContent);

    if (_isEditing) {
      _checklistUpdateSubscription = checklistUpdateStream.stream.listen((message) {
        // message is {'noteId': ..., 'itemId': ...} — only bother
        // re-syncing if it's actually about THIS note; ignore others.
        if (message is Map && message['noteId'] == widget.note!.id) {
          debugPrint('[ChecklistSync] push notification received for this note: $message');
          _syncChecklistFromHive(); // intentionally not awaited — fire and forget
        }
      });
    }

    if (!widget.readOnly) {
      _titleController.addListener(_scheduleAutoSave);
      _contentController.addListener(_scheduleAutoSave);
      _titleController.addListener(_scheduleHistorySnapshot);
      _contentController.addListener(_scheduleHistorySnapshot);
      _periodicSaveTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _autoSave(),
      );
      // Seed the stack with the starting text so the very first edit has
      // something to undo back to.
      _undoStack.add(_EditSnapshot(_titleController.text, _contentController.text));
    }

    _scheduleReminderExpiryCheck();
  }

  // Re-arms itself after every check (rather than a fixed Timer.periodic)
  // so the wait shrinks to exactly "time left until the reminder" instead
  // of polling at a fixed interval that's either too slow (pill lingers
  // after the time passes) or wastefully frequent for far-future times.
  void _scheduleReminderExpiryCheck() {
    _reminderExpiryTimer?.cancel();
    if (widget.readOnly || _reminderAt == null) return;

    final remaining = _reminderAt!.difference(DateTime.now());
    if (remaining.isNegative) {
      setState(() => _reminderAt = null);
      _scheduleAutoSave();
      return;
    }
    // Cap the wait at 1 minute so a far-future reminder doesn't schedule
    // one giant Timer — re-checks at most once a minute, or sooner if
    // the reminder is closer than that.
    final wait = remaining < const Duration(minutes: 1) ? remaining : const Duration(minutes: 1);
    _reminderExpiryTimer = Timer(wait, _scheduleReminderExpiryCheck);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checklistUpdateSubscription?.cancel();
    _autoSaveTimer?.cancel();
    _periodicSaveTimer?.cancel();
    _historyDebounceTimer?.cancel();
    _reminderExpiryTimer?.cancel();
    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
    for (final item in _checklistItems) {
      item.controller.dispose();
      item.focusNode.dispose();
    }
    super.dispose();
  }

  // Fires whenever the app transitions foreground/background while this
  // screen is alive — e.g. the user backgrounds the app, toggles a
  // checkbox from the home screen widget, then returns here. On resume,
  // pull the latest `done` values from Hive for any item this session
  // hasn't itself toggled, so the UI visibly reflects what the widget
  // did instead of silently sitting on stale initState data until the
  // next save (which only protected against overwriting on save, not
  // against the screen *displaying* stale state in the meantime).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[ChecklistSync] lifecycle state changed: $state');
    if (state == AppLifecycleState.resumed) {
      _syncChecklistFromHive(); // intentionally not awaited — fire and forget
    }
  }

  Future<void> _syncChecklistFromHive() async {
    debugPrint('[ChecklistSync] _syncChecklistFromHive called — isEditing=$_isEditing readOnly=${widget.readOnly}');
    if (!_isEditing || widget.readOnly) return;

    // Read straight from Hive — this is always fresh because the widget's
    // background callback writes to Hive (via applyPendingToggle) BEFORE
    // calling refreshWidget. Going through 'todo_rows' instead is wrong:
    // that JSON is filtered to only notes due TODAY, so a note without a
    // today reminder/calendarDate never appears there and sync silently
    // no-ops even though Hive itself was updated correctly.
    final freshNote = await DatabaseService.instance.getNoteByIdFresh(widget.note!.id);
    if (freshNote == null) return;

    final doneMap = <String, bool>{
      for (final item in freshNote.checklistItems) item.id: item.done,
    };

    debugPrint('[ChecklistSync] doneMap from Hive: $doneMap');
    debugPrint('[ChecklistSync] toggledItemIds this session: $_toggledItemIds');

    bool changed = false;
    for (final item in _checklistItems) {
      if (_toggledItemIds.contains(item.id)) continue; // this session owns it
      final latestDone = doneMap[item.id];
      if (latestDone == null) continue;
      if (item.done != latestDone) {
        item.done = latestDone;
        changed = true;
        debugPrint('[ChecklistSync] item ${item.id} updated: ${!latestDone} -> $latestDone');
      }
    }
    debugPrint('[ChecklistSync] changed=$changed');
    if (changed && mounted) setState(() {});
  }

  // Called on every keystroke in title/content. Resets the debounce timer
  // so the actual save only happens once the user pauses typing.
  void _scheduleAutoSave() {
    _hasUnsavedChanges = true;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 1200), _autoSave);
  }

  // The actual debounced save — same logic as the manual Save button, but
  // doesn't navigate away. Only fires once we have at least a title or
  // body, so we never litter Hive with empty draft notes.
  Future<void> _autoSave() async {
    if (!mounted) return;
    if (!_hasUnsavedChanges) return;
    // Guard: if this note was already deleted (e.g. swiped away from
    // the list while the editor's timers were still running), don't
    // resurrect it via a stale auto-save.
    final currentId = _isEditing
        ? widget.note!.id
        : _persistedNoteId;
    if (currentId != null &&
        DatabaseService.instance.getNoteById(currentId) == null) {
      return;
    }
    if (_titleController.text.trim().isEmpty &&
        _contentController.text.trim().isEmpty &&
        _checklistItems.isEmpty) {
      return;
    }
    await _saveNote(popOnSave: false);
    _hasUnsavedChanges = false;
  }

  // Called on every keystroke. Debounced the same way as auto-save — we
  // only want a new undo step once the user pauses, not per character.
  void _scheduleHistorySnapshot() {
    if (_isApplyingHistory) return;
    _historyDebounceTimer?.cancel();
    _historyDebounceTimer = Timer(const Duration(milliseconds: 500), _pushHistorySnapshot);
  }

  void _pushHistorySnapshot() {
    final snapshot = _EditSnapshot(_titleController.text, _contentController.text);
    final last = _undoStack.isEmpty ? null : _undoStack.last;
    if (last != null && last.title == snapshot.title && last.content == snapshot.content) {
      return; // nothing actually changed
    }
    _undoStack.add(snapshot);
    _redoStack.clear(); // new edit invalidates any redo history
    if (mounted) setState(() {});
  }

  void _applySnapshot(_EditSnapshot snapshot) {
    _isApplyingHistory = true;
    _titleController.value = TextEditingValue(
      text: snapshot.title,
      selection: TextSelection.collapsed(offset: snapshot.title.length),
    );
    _contentController.value = TextEditingValue(
      text: snapshot.content,
      selection: TextSelection.collapsed(offset: snapshot.content.length),
    );
    _isApplyingHistory = false;
    _scheduleAutoSave();
  }

  void _undo() {
    if (_undoStack.length <= 1) return; // nothing before the current state
    _historyDebounceTimer?.cancel();
    final current = _undoStack.removeLast();
    _redoStack.add(current);
    _applySnapshot(_undoStack.last);
    setState(() {});
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _historyDebounceTimer?.cancel();
    final snapshot = _redoStack.removeLast();
    _undoStack.add(snapshot);
    _applySnapshot(snapshot);
    setState(() {});
  }

  // ── Checklist ────────────────────────────────────────────────────────────
  // (Parsing checklist lines out of content was removed — checklistItems
  // is now the source of truth, loaded directly from the saved Note above.
  // content is plain free-text only.)

  void _analyzeContent() {
    final text = _contentController.text;
    final lines = text.split('\n');

    final bulletPattern = RegExp(r'^[-*•]\s+(.+)$');
    final remainingLines = <String>[];
    bool convertedSomething = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isLastLine = i == lines.length - 1;
      final match = isLastLine ? null : bulletPattern.firstMatch(line.trim());

      if (match != null && match.group(1)!.trim().isNotEmpty) {
        _checklistItems.add(_ChecklistItem(text: match.group(1)!.trim()));
        convertedSomething = true;
      } else {
        remainingLines.add(line);
      }
    }

    final combined = '${_titleController.text} ${_contentController.text}';
    final suggestion = AiSuggestionService.instance.suggestReminderTime(combined);

    if (convertedSomething) {
      final newText = remainingLines.join('\n');
      setState(() {
        _contentController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
        _suggestedReminder = suggestion;
      });
    } else if (suggestion != _suggestedReminder) {
      setState(() => _suggestedReminder = suggestion);
    }
  }

  void _addChecklistItem() {
    final item = _ChecklistItem(text: '');
    setState(() => _checklistItems.add(item));
    // Wait a frame so the new row actually exists in the tree (and so the
    // toolbar's own tap doesn't immediately steal focus back) before
    // asking for keyboard focus on it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) item.focusNode.requestFocus();
    });
  }

  // Pressing Enter inside an existing checklist row inserts a new empty
  // row directly after it (not just appended at the end) and focuses it,
  // so a fast Enter-Enter-Enter flow naturally builds the list top to
  // bottom — same idea as Reminders/Notion-style checklist input.
  void _addChecklistItemAfter(int index) {
    final item = _ChecklistItem(text: '');
    setState(() => _checklistItems.insert(index + 1, item));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) item.focusNode.requestFocus();
    });
  }

  void _removeChecklistItem(_ChecklistItem item) {
    setState(() {
      _checklistItems.remove(item);
      item.controller.dispose();
    });
  }

  // Writes just this one item's `done` state straight to Hive and
  // refreshes the widget immediately — independent of the normal
  // debounce/periodic auto-save, which still handles title/content/order
  // on its own schedule. Only fires for an existing (already-saved) note;
  // a brand-new unsaved note has nothing in Hive yet for the widget to
  // read regardless, so there's nothing to push. Uses Hive's currently
  // persisted text for this item (not the editor's live controller text),
  // so an in-progress unsaved text edit on the same row isn't prematurely
  // pushed — that still flows through the normal auto-save path.
  Future<void> _pushChecklistToggleToWidget(_ChecklistItem item) async {
    if (!_isEditing) return;
    final note = DatabaseService.instance.getNoteById(widget.note!.id);
    if (note == null) return;

    final items = note.checklistItems;
    final index = items.indexWhere((m) => m.id == item.id);
    if (index == -1) return;

    items[index] = model.ChecklistItem(id: item.id, text: items[index].text, done: item.done);
    await DatabaseService.instance.saveNote(note);
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  // content is now plain free-text only — checklist data lives in
  // checklistItems (saved separately in _saveNote). Empty-text rows are
  // dropped so a half-typed/abandoned task row doesn't get persisted.
  String _buildFinalContent() => _contentController.text.trim();

  // Builds the checklist list to persist. For `done`, items the user
  // actually toggled in THIS session use their current in-memory value;
  // everything else re-reads the latest value from Hive right before
  // saving, so an external change (e.g. a home screen widget toggle made
  // while this screen sat open in the background) doesn't get silently
  // overwritten by this screen's stale initState snapshot. Text/order are
  // still this screen's own — those aren't editable from outside it.
  List<model.ChecklistItem> _buildChecklistItems() {
    final latestFromHive = _isEditing
        ? DatabaseService.instance.getNoteById(widget.note!.id)?.checklistItems
        : null;

    return _checklistItems
        .where((item) => item.controller.text.trim().isNotEmpty)
        .map((item) {
          bool done = item.done;
          if (!_toggledItemIds.contains(item.id) && latestFromHive != null) {
            final fresh = latestFromHive.where((m) => m.id == item.id);
            if (fresh.isNotEmpty) done = fresh.first.done;
          }
          return model.ChecklistItem(id: item.id, text: item.controller.text.trim(), done: done);
        })
        .toList();
  }

  // Set once the first note is created, so every subsequent save (debounce,
  // periodic, Done button, back-nav) updates the SAME note instead of
  // generating a fresh id and creating a duplicate.
  String? _persistedNoteId;
  bool _isSaving = false;

  Future<void> _saveNote({bool popOnSave = true}) async {
    if (_isSaving) {
      if (popOnSave && mounted) Navigator.pop(context, true);
      return;
    }
    _isSaving = true;

    // Cancel any pending auto-save timers — this save (whatever triggered
    // it) already covers their work, so don't let them fire again after
    // we've already written/popped.
    _autoSaveTimer?.cancel();
_periodicSaveTimer?.cancel();

    try {
    final rawTitle = _titleController.text.trim();
    final title = rawTitle.isEmpty ? 'Untitled' : rawTitle;

    final now = DateTime.now();
    final content = _buildFinalContent();

    final id = _isEditing
        ? widget.note!.id
        : (_persistedNoteId ??= now.millisecondsSinceEpoch.toString());

    final note = Note(
      id: id,
      title: title,
      content: content,
      createdAt: _isEditing ? widget.note!.createdAt : now,
      updatedAt: now,
      reminderAt: _reminderAt,
      categoryId: _selectedCategoryId,
      isArchived: _isEditing ? widget.note!.isArchived : false,
      isPinned: _isEditing ? widget.note!.isPinned : false,
      colorValue: _isEditing ? widget.note!.colorValue : null,
      backgroundImagePath: _backgroundImagePath,
      isCompleted: _isEditing ? widget.note!.isCompleted : false,
      isCalendarReminder: _isEditing ? widget.note!.isCalendarReminder : widget.isCalendarReminder,
      calendarDate: _calendarDate,
      checklistItems: _buildChecklistItems(),
    );

    await DatabaseService.instance.saveNote(note);
    await NotificationService.instance.cancelNoteReminder(note.id);

    if (note.reminderAt != null && note.reminderAt!.isAfter(DateTime.now())) {
      await NotificationService.instance.scheduleNoteReminder(
        noteId: note.id,
        title: note.title,
        body: content.isNotEmpty ? content : 'You have a reminder.',
        scheduledAt: note.reminderAt!,
      );
    }

    } catch (e) {
      debugPrint('[NoteEditor] save error: $e');
    } finally {
      _isSaving = false;
      if (popOnSave && mounted) Navigator.pop(context, true);
    }
  }

  // ── Reminder picking ─────────────────────────────────────────────────────

  Future<void> _pickReminder() async {
    // If this note already has a calendarDate (created via the Calendar
    // tab), the date is implicit — skip straight to the time picker
    // instead of asking the user to re-pick a date they already chose.
    DateTime? date = _calendarDate;

    if (date == null) {
      date = await showDatePicker(
        context: context,
        initialDate: _reminderAt ?? DateTime.now(),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      );
      if (date == null) return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime:
          _reminderAt != null ? TimeOfDay.fromDateTime(_reminderAt!) : TimeOfDay.now(),
    );
    if (time == null) return;

    setState(() {
      _reminderAt = DateTime(date!.year, date.month, date.day, time.hour, time.minute);
    });
    _scheduleReminderExpiryCheck();
  }

  void _applySuggestedReminder() {
    if (_suggestedReminder == null) return;
    setState(() {
      _reminderAt = _suggestedReminder;
      _suggestedReminder = null;
    });
    _scheduleReminderExpiryCheck();
  }

  String _formatDateTime(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:$minute $period';
  }

  // Resolves a stored "asset:..." or "file:..." path into the right
  // ImageProvider — same scheme used by NotesScreen's card backgrounds.
  ImageProvider _resolveBackgroundImage(String path) {
    if (path.startsWith('asset:')) {
      return AssetImage(path.substring('asset:'.length));
    }
    return FileImage(File(path.substring('file:'.length)));
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isPopping) return;
        _isPopping = true;
        // Back button/gesture: flush any pending edits straight to Hive
        // (same save the debounce/periodic timers already use) without
        // requiring a Done tap first, then actually leave the screen.
        if (!widget.readOnly) {
          await _saveNote(popOnSave: false);
        }
        if (mounted) Navigator.pop(context, true);
      },
      child: Stack(
        children: [
          // Full-screen background image, behind everything — AppBar,
          // body, and the keyboard toolbar are all made transparent below
          // so this shows through all of them, per the theme set on the
          // note via NotesScreen's edit mode.
          if (_backgroundImagePath != null)
            Positioned.fill(
              child: Image(
                image: _resolveBackgroundImage(_backgroundImagePath!),
                fit: BoxFit.cover,
              ),
            ),
          if (_backgroundImagePath != null)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.35),
                      Colors.black.withOpacity(0.65),
                    ],
                  ),
                ),
              ),
            ),
          Scaffold(
            backgroundColor: _backgroundImagePath != null ? Colors.transparent : null,
            resizeToAvoidBottomInset: false,
            appBar: AppBar(
              backgroundColor: _backgroundImagePath != null ? Colors.transparent : null,
              elevation: 0,
              title: Text(widget.readOnly
                  ? 'Archived Note'
                  : (_isEditing ? 'Edit Note' : 'New Note')),
              actions: [
                if (!widget.readOnly)
                  TextButton(
                    onPressed: () => _saveNote(),
                    child: const Text(
                      'Done',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // ── Title (reminder bell moved to the bottom toolbar) ──────────
            TextField(
              controller: _titleController,
              autofocus: !_isEditing && !widget.readOnly,
              readOnly: widget.readOnly,
              decoration: InputDecoration(
                hintText: 'Untitled',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: _backgroundImagePath != null ? Colors.white : null,
              ),
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) =>
                  FocusScope.of(context).requestFocus(_contentFocusNode),
              onChanged: widget.readOnly ? null : (_) => _analyzeContent(),
            ),

            const SizedBox(height: 4),

            // ── Reminder area — only shown once a reminder is actually
            //    set. Nothing is shown otherwise; the bell icon next to
            //    the title is the only way to open the picker. ──────────
            if (_reminderAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: widget.readOnly
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule, size: 15, color: colorScheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            _formatDateTime(_reminderAt!),
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : _ReminderSetRow(
                        label: _formatDateTime(_reminderAt!),
                        color: colorScheme.primary,
                        onChange: _pickReminder,
                        onClear: () {
                          setState(() => _reminderAt = null);
                          _reminderExpiryTimer?.cancel();
                        },
                      ),
              ),

            const SizedBox(height: 18),

            // ── Content (free text — typed bullets auto-become checkboxes) ─
            TextField(
              controller: _contentController,
              focusNode: _contentFocusNode,
              readOnly: widget.readOnly,
              decoration: InputDecoration(
                hintText: 'Tap anywhere and start typing...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              cursorColor: Theme.of(context).colorScheme.primary,
              style: TextStyle(
                fontSize: 16.5,
                height: 1.6,
                color: _backgroundImagePath != null ? Colors.white : null,
              ),
              minLines: 3,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
            ),

            // ── AI suggestion chip — only when a time is detected and no
            //    reminder is set yet, fades in/out smoothly. Never shown
            //    in read-only mode since there's nothing to act on. ──────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(sizeFactor: animation, child: child),
              ),
              child: (!widget.readOnly && _suggestedReminder != null && _reminderAt == null)
                  ? Padding(
                      key: ValueKey(_suggestedReminder),
                      padding: const EdgeInsets.only(top: 10),
                      child: ActionChip(
                        avatar: Icon(Icons.auto_awesome, size: 16, color: colorScheme.primary),
                        label: Text('Set reminder: ${_formatDateTime(_suggestedReminder!)}'),
                        backgroundColor: colorScheme.primaryContainer,
                        side: BorderSide.none,
                        onPressed: _applySuggestedReminder,
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('no-suggestion')),
            ),

            const SizedBox(height: 20),

            // ── Checklist — flows directly under the writing area, no
            //    section header/box, just plain checkbox rows like Notion.
            //    Hidden entirely in read-only mode if there are no tasks. ─
            if (!widget.readOnly || _checklistItems.isNotEmpty) ...[
              const SizedBox(height: 4),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _checklistItems.isEmpty
                    ? const SizedBox.shrink()
                    : (widget.readOnly
                        ? Column(
                            children: _checklistItems
                                .map((item) => _ReadOnlyChecklistRow(item: item))
                                .toList(),
                          )
                        : ReorderableListView(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            onReorderStart: (_) => HapticFeedback.mediumImpact(),
                            onReorder: (oldIndex, newIndex) {
                              setState(() {
                                if (newIndex > oldIndex) newIndex -= 1;
                                final item = _checklistItems.removeAt(oldIndex);
                                _checklistItems.insert(newIndex, item);
                              });
                            },
                            children: [
                              for (int i = 0; i < _checklistItems.length; i++)
                                _ChecklistRow(
                                  key: ValueKey(_checklistItems[i].id),
                                  item: _checklistItems[i],
                                  index: i,
                                  onDelete: () => _removeChecklistItem(_checklistItems[i]),
                                  onSubmitNext: () => _addChecklistItemAfter(i),
                                  onToggleDone: () {
                                    _checklistItems[i].done = !_checklistItems[i].done;
                                    _toggledItemIds.add(_checklistItems[i].id);
                                    // Push to the widget immediately rather than
                                    // waiting for the next auto-save (debounce is
                                    // 1.2s, periodic is up to 10s) — otherwise a
                                    // checkbox tapped here feels laggy if you check
                                    // the home screen widget right away.
                                    _pushChecklistToggleToWidget(_checklistItems[i]);
                                  },
                                ),
                            ],
                          )),
              ),
              ],

            // ── Word/char count: only shown inline here in read-onlyS
            //    mode. In edit mode it lives in the keyboard toolbar. ──────
            if (widget.readOnly) ...[
              const SizedBox(height: 24),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _contentController,
                builder: (context, value, _) {
                  final text = value.text.trim();
                  final wordCount = text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
                  return Text(
                    '$wordCount word${wordCount == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.3)),
                  );
                },
              ),
            ],
                ],
              ),
            ),
          ),
          // ── Keyboard toolbar — "Add a task" + live word/char count,
          //    pinned right above the keyboard (like an iOS accessory
          //    bar). Sits at the bottom of the screen when the keyboard
          //    is closed, since bottom padding is just 0 then. ───────────
          if (!widget.readOnly)
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              decoration: BoxDecoration(
                color: _backgroundImagePath != null
                    ? Colors.black.withOpacity(0.35)
                    : const Color(0xFF3C3541),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Undo',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: _undoStack.length > 1 ? _undo : null,
                        icon: Icon(
                          Icons.undo,
                          size: 18,
                          color: _undoStack.length > 1
                              ? colorScheme.primary
                              : Colors.white.withOpacity(0.2),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Redo',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: _redoStack.isNotEmpty ? _redo : null,
                        icon: Icon(
                          Icons.redo,
                          size: 18,
                          color: _redoStack.isNotEmpty
                              ? colorScheme.primary
                              : Colors.white.withOpacity(0.2),
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _pickReminder,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Icon(
                            _reminderAt != null
                                ? Icons.notifications_active
                                : Icons.notifications_none_outlined,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _addChecklistItem,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_task, size: 18, color: colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                'Add a task',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small presentational widgets ─────────────────────────────────────────


// Compact "reminder is set" display, replacing the quick-pick chips once chosen.
class _ReminderSetRow extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onChange;
  final VoidCallback onClear;

  const _ReminderSetRow({
    required this.label,
    required this.color,
    required this.onChange,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onChange,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 15, color: Colors.redAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// A small rotating set of example tasks shown as placeholder text on
// empty checklist rows — picked deterministically off the item's id so
// the same row always shows the same example (no flicker on rebuild).
const List<String> _taskPlaceholders = [
  'e.g. Buy groceries',
  'e.g. Call mom back',
  'e.g. Finish the report',
  'e.g. Book dentist appointment',
  "e.g. Reply to Sarah's email",
  'e.g. Pay electricity bill',
];

String _taskPlaceholderFor(String id) =>
    _taskPlaceholders[id.hashCode.abs() % _taskPlaceholders.length];

// A single checklist row with swipe-to-delete, used in an AnimatedSize
// column so adding/removing rows resizes smoothly instead of jumping.
class _ChecklistRow extends StatelessWidget {
  final _ChecklistItem item;
  final int index;
  final VoidCallback onDelete;
  final VoidCallback onSubmitNext;
  final VoidCallback onToggleDone;

  const _ChecklistRow({
    super.key,
    required this.item,
    required this.index,
    required this.onDelete,
    required this.onSubmitNext,
    required this.onToggleDone,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('dismiss_${item.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.redAccent),
      ),
      // The whole row is now the drag trigger (long-press anywhere to pick
      // it up and reorder) rather than just the small leading icon — much
      // easier to grab one-handed on a wide screen. Short taps still reach
      // the checkbox/text field underneath since ReorderableDragStartListener
      // only intercepts the long-press-drag gesture, not plain taps.
      child: StatefulBuilder(
        builder: (context, setRowState) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              // Align to the top so multi-line wrapped text keeps the
              // checkbox/handle pinned to the first line, not centered
              // against the full wrapped height.
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setRowState(onToggleDone),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutBack,
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: item.done
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        border: Border.all(
                          color: item.done
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white.withOpacity(0.35),
                          width: 1.8,
                        ),
                      ),
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutBack,
                        scale: item.done ? 1.0 : 0.4,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 120),
                          opacity: item.done ? 1.0 : 0.0,
                          child: const Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Wrapped onto its own flexible column so long task text
                // wraps to multiple lines, indented to align under the
                // first line's text (not under the checkbox).
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      // Dims the whole text block immediately on toggle —
                      // fast and punchy rather than a slow fade, so it
                      // still reads as "instant feedback" even though the
                      // strikethrough itself can't be tweened (TextField
                      // applies TextDecoration as an on/off flag, with no
                      // animatable in-between state, and a manual overlay
                      // line doesn't follow multi-line text wrapping).
                      opacity: item.done ? 0.55 : 1.0,
                      child: TextField(
                        controller: item.controller,
                        focusNode: item.focusNode,
                        maxLines: null,
                        minLines: 1,
                        style: TextStyle(
                          fontSize: 15.5,
                          height: 1.35,
                          decoration: item.done ? TextDecoration.lineThrough : TextDecoration.none,
                          decorationColor: Colors.white60,
                          decorationThickness: 1.5,
                          color: item.done ? Colors.white38 : Colors.white.withOpacity(0.9),
                        ),
                        cursorColor: Theme.of(context).colorScheme.primary,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          hintText: _taskPlaceholderFor(item.id),
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
                        ),
                        textInputAction: TextInputAction.next,
                        onEditingComplete: onSubmitNext,
                      ),
                    ),
                  ),
                ),
                // Drag handle — moved to the right side of the row, with a
                // generous tap target. Kept separate from the TextField
                // (rather than wrapping the whole row) since long-pressing
                // directly on text conflicts with the field's own
                // text-selection gesture.
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2, left: 8),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: Icon(
                          Icons.drag_indicator,
                          size: 20,
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Plain, non-interactive checklist row used only in read-only preview mode —
// shows the checkbox state and text but nothing can be tapped or edited.
class _ReadOnlyChecklistRow extends StatelessWidget {
  final _ChecklistItem item;

  const _ReadOnlyChecklistRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              item.done ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: item.done ? Colors.white38 : Colors.white60,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                item.controller.text.isEmpty ? 'Task' : item.controller.text,
                style: TextStyle(
                  fontSize: 15.5,
                  decoration: item.done ? TextDecoration.lineThrough : null,
                  color: item.done ? Colors.white38 : Colors.white70,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
