import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' hide Category;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/note.dart';
import '../models/category.dart';
import '../models/saved_anime.dart';
import '../models/checklist_item.dart';
import 'widget_service.dart';

// DatabaseService is a singleton — one instance shared across the whole app.
// It handles opening Hive boxes and exposes simple CRUD methods.
class DatabaseService {
  // Private constructor so nobody can do DatabaseService() from outside
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  // Hive stores data in "boxes" — think of them as tables
  static const String _notesBoxName = 'notes';
  static const String _categoriesBoxName = 'categories';
  static const String _savedAnimeBoxName = 'saved_anime';

  late Box<Note> _notesBox;
  late Box<Category> _categoriesBox;
  late Box<SavedAnime> _savedAnimeBox;

  // Serializes every operation that touches _notesBox's open/closed state
  // (save, delete, and the cross-isolate-fresh reopen). Without this, a
  // fresh-read close()+reopen() racing against an in-flight put()/delete()
  // on the SAME (now-closed) Box object threw "Box has already been
  // closed" — silently swallowed by callers' try/catch blocks, making
  // saves and deletes appear to just silently do nothing. Each call now
  // queues behind whatever notesBox operation is already running instead
  // of overlapping with it.
  Future<void> _notesBoxLock = Future.value();

  Future<T> _runExclusiveOnNotesBox<T>(Future<T> Function() action) async {
    final previous = _notesBoxLock;
    final completer = Completer<void>();
    _notesBoxLock = completer.future;
    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  // Guards against double-init — the widget's background callback runs
  // in its own isolate and calls init() fresh every time it wakes, since
  // it doesn't share memory with the main app isolate.
  bool _initialized = false;

  // Call this once at app startup before runApp() — also called by the
  // widget's background callback (widget_service.dart) since that runs
  // in a separate isolate with nothing set up yet.
  Future<void> init() async {
    if (_initialized) return;
    try {
      await Hive.initFlutter();
    } catch (_) {
      // Widget tests and other non-Flutter shell contexts may not have the
      // path_provider plugin available, so fall back to a temp directory.
      Hive.init(Directory.systemTemp.path);
    }

    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(NoteAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(CategoryAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(HiveAnimeSourceAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(SavedAnimeAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(ChecklistItemAdapter());

    _notesBox = Hive.isBoxOpen(_notesBoxName)
        ? Hive.box<Note>(_notesBoxName)
        : await Hive.openBox<Note>(_notesBoxName);
    _categoriesBox = Hive.isBoxOpen(_categoriesBoxName)
        ? Hive.box<Category>(_categoriesBoxName)
        : await Hive.openBox<Category>(_categoriesBoxName);
    _savedAnimeBox = Hive.isBoxOpen(_savedAnimeBoxName)
        ? Hive.box<SavedAnime>(_savedAnimeBoxName)
        : await Hive.openBox<SavedAnime>(_savedAnimeBoxName);

    _initialized = true;
  }

  // ── Notes ──────────────────────────────────────────────────────────────────

  // Returns all notes as a list, newest first
  List<Note> getAllNotes() {
    final notes = _notesBox.values.toList();
    _sweepExpiredReminders(notes);
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  }

  // Clears reminderAt on any note whose scheduled time has already
  // passed, so the editor's reminder pill/bell stops showing it as
  // "set" once it's done. This never touches the actual notification —
  // NotificationService fires that independently at the scheduled time
  // via the OS scheduler, regardless of what this note object's
  // reminderAt field says afterward. Only writes back to Hive for notes
  // that actually changed, so this is a no-op cost on every other read.
  void _sweepExpiredReminders(List<Note> notes) {
    final now = DateTime.now();
    for (final note in notes) {
      if (note.reminderAt != null && note.reminderAt!.isBefore(now)) {
        note.reminderAt = null;
        _notesBox.put(note.id, note);
      }
    }
  }

  // Forces a fresh read of the entire notes box from disk, bypassing this
  // isolate's cached Hive values. Needed when the widget background isolate
  // writes a checklist toggle and the main app needs to reflect it instantly.
  Future<List<Note>> getAllNotesFresh() async {
    return _runExclusiveOnNotesBox(() async {
      await _notesBox.close();
      _notesBox = await Hive.openBox<Note>(_notesBoxName);
      final notes = _notesBox.values.toList();
      notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return notes;
    });
  }

  // Forces _notesBox to be reopened from disk, unconditionally. Always
  // called at the very start of the widget's background callback
  // (widgetBackgroundCallback in widget_service.dart) — that isolate can
  // be REUSED by Android for multiple consecutive widget taps instead of
  // spawned fresh every time. init()'s `_initialized` guard means a
  // reused isolate would otherwise keep using whatever Box snapshot it
  // opened on its very first wake, silently missing any note
  // created/edited from the main app isolate since then. Without this, a
  // checkbox tap on note B's row can save a notes list that's missing
  // note A entirely, overwriting the widget's previously-correct rows.
  Future<void> refreshNotesBoxFromDisk() async {
    await _runExclusiveOnNotesBox(() async {
      await _notesBox.close();
      _notesBox = await Hive.openBox<Note>(_notesBoxName);
    });
  }

  // Tracks ids that were explicitly deleted, so a stale write (e.g. an
  // editor screen's autosave timer firing AFTER the user already
  // swipe-deleted that same note from the list) can't resurrect it.
  final Set<String> _deletedNoteIds = {};

  // Saves a new note (key = note's id so we can look it up later)
  Future<void> saveNote(Note note) async {
    debugPrint('[DatabaseService] saveNote called for id=${note.id} title="${note.title}" — deletedIds at call time: $_deletedNoteIds');
    bool didSave = false;
    await _runExclusiveOnNotesBox(() async {
      if (_deletedNoteIds.contains(note.id)) {
        debugPrint('[DatabaseService] saveNote BLOCKED — id=${note.id} is in _deletedNoteIds (resurrection prevented)');
        return;
      }
      await _notesBox.put(note.id, note);
      debugPrint('[DatabaseService] saveNote written to Hive: id=${note.id}');
      didSave = true;
    });
    // Refresh widget AFTER the lock releases so getAllNotes() reads the
    // fully committed box state — calling it inside the lock meant it
    // could read a stale snapshot before the delete had fully landed.
    if (didSave) {
      await WidgetService.refreshWidget(getAllNotes());
    }
  }

  // Deletes a note by its id
  Future<void> deleteNote(String id) async {
    debugPrint('[DatabaseService] deleteNote called for id=$id');
    _deletedNoteIds.add(id);
    debugPrint('[DatabaseService] _deletedNoteIds now: $_deletedNoteIds');
    await _runExclusiveOnNotesBox(() async {
      await _notesBox.delete(id);
      debugPrint('[DatabaseService] _notesBox.delete() done for id=$id');
      debugPrint('[DatabaseService] Note still in box after delete? ${_notesBox.containsKey(id)}');
    });
    debugPrint('[DatabaseService] deleteNote fully complete for id=$id');
    // Refresh widget after lock releases so it reads the post-delete state.
    await WidgetService.refreshWidget(getAllNotes());
  }

  // Clears a previously-deleted id from the guard set, so an Undo
  // operation (which calls saveNote again for the same id) is allowed
  // through. Must be called BEFORE saveNote in any Undo flow.
  void undeleteNote(String id) {
    _deletedNoteIds.remove(id);
  }

  // Synchronous check — lets callers (e.g. the editor's _autoSave timer)
  // bail out early without acquiring the notesBox lock, avoiding a
  // resurrection race where the periodic save fires after a swipe-delete.
  bool isNoteDeleted(String id) => _deletedNoteIds.contains(id);

  Note? getNoteById(String id) {
    final note = _notesBox.get(id);
    if (note != null) _sweepExpiredReminders([note]);
    return note;
  }

  // Forces a fresh read from disk, bypassing this isolate's in-memory box
  // cache. Needed because Hive's Box keeps a per-isolate in-memory copy —
  // a write from another isolate (e.g. the widget's background callback)
  // updates the file on disk and THAT isolate's own cache, but never this
  // isolate's already-open handle. box.get() here would silently keep
  // returning stale data forever. Closing + reopening forces Hive to
  // re-read the file, which is the only way to cross that gap.
  Future<Note?> getNoteByIdFresh(String id) async {
    return _runExclusiveOnNotesBox(() async {
      await _notesBox.close();
      _notesBox = await Hive.openBox<Note>(_notesBoxName);
      final note = _notesBox.get(id);
      if (note != null) _sweepExpiredReminders([note]);
      return note;
    });
  }

  // Live stream of changes to one specific note's Hive entry — fires on
  // every put() to that key, from ANY isolate (including the widget's
  // background callback writing from outside the main app process).
  // Used by the editor screen to reflect external toggles immediately
  // while the screen is open and frontmost, not just on resume.
  Stream<BoxEvent> watchNote(String id) {
    return _notesBox.watch(key: id);
  }

  // ── Categories ─────────────────────────────────────────────────────────────

  List<Category> getAllCategories() {
    return _categoriesBox.values.toList();
  }

  Future<void> saveCategory(Category category) async {
    await _categoriesBox.put(category.id, category);
  }

  Future<void> deleteCategory(String id) async {
    await _categoriesBox.delete(id);
  }

  // ── Saved Anime (Liked / Watchlisted) ───────────────────────────────────

  // Returns every saved entry for a given list ('liked' or 'watchlisted'),
  // newest-saved first.
  List<SavedAnime> getSavedAnime(String listType) {
    final entries = _savedAnimeBox.values
        .where((entry) => entry.listType == listType)
        .toList();
    entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return entries;
  }

  // Key = "<listType>_<uniqueKey>" so the same anime can independently
  // exist in both the liked and watchlisted lists at once without colliding.
  String _savedAnimeKey(String listType, String uniqueKey) => '${listType}_$uniqueKey';

  Future<void> saveSavedAnime(SavedAnime entry) async {
    await _savedAnimeBox.put(_savedAnimeKey(entry.listType, entry.uniqueKey), entry);
  }

  Future<void> deleteSavedAnime(String listType, String uniqueKey) async {
    await _savedAnimeBox.delete(_savedAnimeKey(listType, uniqueKey));
  }

  bool isSavedAnime(String listType, String uniqueKey) {
    return _savedAnimeBox.containsKey(_savedAnimeKey(listType, uniqueKey));
  }

  // Looks up the raw stored entry (not just the Anime data) so callers
  // can read/update fields like `remarks` that don't exist on Anime.
  SavedAnime? getSavedAnimeEntry(String listType, String uniqueKey) {
    return _savedAnimeBox.get(_savedAnimeKey(listType, uniqueKey));
  }
}
