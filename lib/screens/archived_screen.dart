import 'package:flutter/material.dart';
import '../models/note.dart';
import '../models/category.dart';
import '../services/database_service.dart';
import 'note_editor_screen.dart';

// Shows everything the user has archived — both notes and folders.
// Archived folders can be opened to browse their contents (subfolders and
// notes inside them aren't necessarily archived themselves).
class ArchivedScreen extends StatefulWidget {
  const ArchivedScreen({super.key});

  @override
  State<ArchivedScreen> createState() => _ArchivedScreenState();
}

class _ArchivedScreenState extends State<ArchivedScreen> {
  List<Note> _allNotes = [];
  List<Category> _allCategories = [];

  // When null, we're showing the top-level archived list.
  // When set, we've drilled into an archived folder and show its contents.
  Category? _openFolder;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _allNotes = DatabaseService.instance.getAllNotes();
      _allCategories = DatabaseService.instance.getAllCategories();
    });
  }

  List<Note> get _archivedNotes =>
      _allNotes.where((n) => n.isArchived).toList();

  List<Category> get _archivedFolders =>
      _allCategories.where((c) => c.isArchived).toList();

  // Contents of whichever archived folder is currently open
  List<Category> get _subfoldersOfOpen => _allCategories
      .where((c) => c.parentId == _openFolder!.id)
      .toList();

  List<Note> get _notesOfOpen =>
      _allNotes.where((n) => n.categoryId == _openFolder!.id).toList();

  Future<void> _unarchiveNote(Note note) async {
    note.isArchived = false;
    await DatabaseService.instance.saveNote(note);
    _loadData();
  }

  Future<void> _unarchiveFolder(Category folder) async {
    folder.isArchived = false;
    await DatabaseService.instance.saveCategory(folder);
    _loadData();
  }

  // Archived notes are view-only here — opens the editor in read-only
  // mode so the layout matches a real note, but nothing can be changed.
  Future<void> _showNotePreview(Note note) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(note: note, readOnly: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // ── Browsing inside an archived folder ────────────────────────────────
    if (_openFolder != null) {
      final subfolders = _subfoldersOfOpen;
      final notes = _notesOfOpen;
      final isEmpty = subfolders.isEmpty && notes.isEmpty;

      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _openFolder = null),
          ),
          title: Text(_openFolder!.name),
        ),
        body: isEmpty
            ? const Center(
                child: Text(
                  'This folder is empty',
                  style: TextStyle(color: Colors.white60, fontSize: 16),
                ),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ...subfolders.map(
                    (folder) => Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: Icon(Icons.folder, color: colorScheme.primary),
                        title: Text(folder.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => setState(() => _openFolder = folder),
                      ),
                    ),
                  ),
                  ...notes.map(
                    (note) => Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: Icon(Icons.note, color: colorScheme.primary),
                        title: Text(note.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: note.content.isNotEmpty
                            ? Text(note.content, maxLines: 1, overflow: TextOverflow.ellipsis)
                            : null,
                        onTap: () => _showNotePreview(note),
                      ),
                    ),
                  ),
                ],
              ),
      );
    }

    // ── Top-level archived list ─────────────────────────────────────────
    final isEmpty = _archivedNotes.isEmpty && _archivedFolders.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Archived')),
      body: isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.archive_outlined, size: 64, color: Colors.white38),
                  const SizedBox(height: 16),
                  const Text(
                    'Nothing archived yet',
                    style: TextStyle(fontSize: 18, color: Colors.white60),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Swipe a note or folder right to archive it',
                    style: TextStyle(fontSize: 14, color: Colors.white38),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ..._archivedFolders.map(
                  (folder) => Card(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      leading: Icon(Icons.folder, color: colorScheme.primary),
                      title: Text(folder.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Folder · tap to open'),
                      trailing: TextButton(
                        onPressed: () => _unarchiveFolder(folder),
                        child: const Text('Unarchive'),
                      ),
                      // Tapping the tile (not the button) drills into the folder
                      onTap: () => setState(() => _openFolder = folder),
                    ),
                  ),
                ),
                ..._archivedNotes.map(
                  (note) => Card(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      leading: Icon(Icons.note, color: colorScheme.primary),
                      title: Text(note.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: note.content.isNotEmpty
                          ? Text(note.content, maxLines: 1, overflow: TextOverflow.ellipsis)
                          : null,
                      onTap: () => _showNotePreview(note),
                      trailing: TextButton(
                        onPressed: () => _unarchiveNote(note),
                        child: const Text('Unarchive'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}