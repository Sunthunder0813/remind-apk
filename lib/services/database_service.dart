import 'dart:io';

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
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  }

  // Forces a fresh read of the entire notes box from disk, bypassing this
  // isolate's cached Hive values. Needed when the widget background isolate
  // writes a checklist toggle and the main app needs to reflect it instantly.
  Future<List<Note>> getAllNotesFresh() async {
    await _notesBox.close();
    _notesBox = await Hive.openBox<Note>(_notesBoxName);
    final notes = _notesBox.values.toList();
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  }

  // Saves a new note (key = note's id so we can look it up later)
  Future<void> saveNote(Note note) async {
    await _notesBox.put(note.id, note);
    await WidgetService.refreshWidget(getAllNotes());
  }

  // Deletes a note by its id
  Future<void> deleteNote(String id) async {
    await _notesBox.delete(id);
    await WidgetService.refreshWidget(getAllNotes());
  }

  Note? getNoteById(String id) {
    return _notesBox.get(id);
  }

  // Forces a fresh read from disk, bypassing this isolate's in-memory box
  // cache. Needed because Hive's Box keeps a per-isolate in-memory copy —
  // a write from another isolate (e.g. the widget's background callback)
  // updates the file on disk and THAT isolate's own cache, but never this
  // isolate's already-open handle. box.get() here would silently keep
  // returning stale data forever. Closing + reopening forces Hive to
  // re-read the file, which is the only way to cross that gap.
  Future<Note?> getNoteByIdFresh(String id) async {
    await _notesBox.close();
    _notesBox = await Hive.openBox<Note>(_notesBoxName);
    return _notesBox.get(id);
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
