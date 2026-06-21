import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../models/category.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/background_image_service.dart';
import '../widgets/theme_picker_sheet.dart';
import 'note_editor_screen.dart';
import 'archived_screen.dart';

// Shared floating Undo toast — dark rounded card + purple "Undo" pill.
// Public (no underscore) and top-level so other screens (e.g.
// LikedAnimeScreen) can reuse the exact same styling instead of
// duplicating it inline.
void showUndoToast(BuildContext context, String message, {VoidCallback? onUndo}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Positioned(
      // Sits above the FAB + nav bar, never overlapping either
      bottom: 148,
      left: 24,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - value)),
              child: child,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2C2831),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13.5,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (onUndo != null) ...[
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () {
                              entry.remove();
                              onUndo();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7C3AED).withOpacity(0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Undo',
                                style: TextStyle(
                                  color: Color(0xFFCB9BFF),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Countdown bar — drains left to right over the toast's
                  // 3s visible window, giving a "lap timer" sense of how
                  // much longer Undo is still available.
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1.0, end: 0.0),
                    duration: const Duration(seconds: 3),
                    curve: Curves.linear,
                    builder: (context, value, child) => Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: value.clamp(0.0, 1.0),
                        child: Container(
                          height: 3,
                          color: const Color(0xFF7C3AED),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(seconds: 3), () {
    if (entry.mounted) entry.remove();
  });
}

class NotesScreen extends StatefulWidget {
  // Fired whenever folder navigation or the grid/list toggle changes —
  // lets HomeScreen's AppBar (title, back arrow, toggle icon) stay in
  // sync without polling currentState on every build.
  final VoidCallback? onStateChanged;

  const NotesScreen({super.key, this.onStateChanged});

  @override
  State<NotesScreen> createState() => NotesScreenState();
}

class NotesScreenState extends State<NotesScreen> {
  List<Note> _notes = [];
  List<Category> _categories = [];

  String? _currentFolderId;
  final List<Category> _folderPath = [];

  // Toggleable layout — grid (2-column staggered, default) or single-column
  // list. Doesn't persist across app restarts; just a session preference.
  bool _isGridView = true;

  // ── Edit mode (single-select for theming — pick exactly one note OR
  //    one folder, then the picker opens immediately) ─────────────────────
  bool _isEditMode = false;
  String? _selectedNoteId;
  String? _selectedFolderId;

  bool get isEditMode => _isEditMode;

  void toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
      if (!_isEditMode) {
        _selectedNoteId = null;
        _selectedFolderId = null;
      }
    });
    widget.onStateChanged?.call();
  }

  Future<void> _selectNoteForTheming(String id) async {
    setState(() {
      _selectedFolderId = null;
      _selectedNoteId = id;
    });
    await _applyThemeToNote(id);
  }

  Future<void> _selectFolderForTheming(String id) async {
    setState(() {
      _selectedNoteId = null;
      _selectedFolderId = id;
    });
    await _applyThemeToFolder(id);
  }

  Future<void> _applyThemeToNote(String id) async {
    final note = _notes.firstWhere((n) => n.id == id);
    final result = await showThemePickerSheet(
      context,
      showRemoveOption: note.backgroundImagePath != null,
    );
    if (result == null) {
      if (mounted) setState(() => _selectedNoteId = null);
      return;
    }

    await BackgroundImageService.instance.deleteIfUserUpload(note.backgroundImagePath);
    note.backgroundImagePath = result.backgroundPath;
    await DatabaseService.instance.saveNote(note);

    if (!mounted) return;
    setState(() {
      _isEditMode = false;
      _selectedNoteId = null;
    });
    widget.onStateChanged?.call();
    _loadData();
  }

  Future<void> _applyThemeToFolder(String id) async {
    final folder = _categories.firstWhere((c) => c.id == id);
    final result = await showThemePickerSheet(
      context,
      showRemoveOption: folder.backgroundImagePath != null,
    );
    if (result == null) {
      if (mounted) setState(() => _selectedFolderId = null);
      return;
    }

    await BackgroundImageService.instance.deleteIfUserUpload(folder.backgroundImagePath);
    folder.backgroundImagePath = result.backgroundPath;
    await DatabaseService.instance.saveCategory(folder);

    if (!mounted) return;
    setState(() {
      _isEditMode = false;
      _selectedFolderId = null;
    });
    widget.onStateChanged?.call();
    _loadData();
  }

  // Soft pastel palette used to color-code cards when a note/folder has no
  // explicit colorValue set — cycled deterministically off each item's id
  // so a given card's color never changes between rebuilds.
  static const List<Color> _palette = [
    Color(0xFFE57373), // soft red
    Color(0xFF7986CB), // soft indigo
    Color(0xFFFFB74D), // soft orange
    Color(0xFFBA68C8), // soft purple
    Color(0xFF4FC3F7), // soft blue
    Color(0xFF81C784), // soft green
  ];

  Color _colorForId(String id) {
    final hash = id.codeUnits.fold<int>(0, (sum, c) => sum + c);
    return _palette[hash % _palette.length];
  }

  // Resolves a stored "asset:..." or "file:..." path into the right
  // DecorationImage provider for a card background.
  DecorationImage _backgroundDecorationImage(String path) {
    if (path.startsWith('asset:')) {
      return DecorationImage(
        image: AssetImage(path.substring('asset:'.length)),
        fit: BoxFit.cover,
      );
    }
    return DecorationImage(
      image: FileImage(File(path.substring('file:'.length))),
      fit: BoxFit.cover,
    );
  }

  // Small checkbox badge shown in the top-right corner of a card while in
  // edit mode, reflecting whether that card is currently selected.
  Widget _selectionCheckbox(bool selected) {
    return Positioned(
      top: 8,
      right: 8,
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? Theme.of(context).colorScheme.primary : Colors.black54,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: selected
              ? const Icon(Icons.check, size: 15, color: Colors.white)
              : null,
        ),
      ),
    );
  }

  // Small pin indicator, top-right of a card. Always white, with a small
  // dark shadow/outline so it stays legible even on the lighter pastel
  // note cards (a plain white icon with no contrast aid would wash out
  // against light backgrounds).
  Widget _pinBadge(String ownerId) {
    return Positioned(
      key: ValueKey('pin_$ownerId'),
      top: 8,
      right: 8,
      child: const IgnorePointer(
        child: Icon(
          Icons.push_pin,
          size: 16,
          color: Colors.white,
        ),
      ),
    );
  }

  // Reads the note's structured checklistItems directly for card preview
  // purposes — content is now plain free-text only, so there's no parsing
  // left to do here. Kept as a (note) -> list function, same call shape
  // as before, just sourced differently.
  List<MapEntry<String, bool>> _parseChecklistPreview(Note note) {
    return note.checklistItems
        .map((item) => MapEntry(item.text, item.done))
        .toList();
  }

  // content is plain free-text now — no checklist lines to strip out.
  String _freeTextPreview(Note note) => note.content.trim();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _loadData() {
    setState(() {
      _notes = DatabaseService.instance.getAllNotes();
      _categories = DatabaseService.instance.getAllCategories();
    });
  }

  // ── Exposed for HomeScreen's AppBar (grid/list toggle + archive icon
  //    now live up there instead of duplicating a header in the body) ────
  bool get isGridView => _isGridView;

  void toggleGridView() {
    setState(() => _isGridView = !_isGridView);
    widget.onStateChanged?.call();
  }

  Future<void> openArchived() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ArchivedScreen()),
    );
    _loadData();
  }

  // ── Folder navigation ──────────────────────────────────────────────────

  List<Category> get _subfolders {
    final list = _categories
        .where((c) => c.parentId == _currentFolderId && c.isVisible && !c.isArchived)
        .toList();
    // Pinned folders float to the top of the folder group; everything
    // else keeps its original relative order (stable sort).
    list.sort((a, b) {
      if (a.isPinned == b.isPinned) return 0;
      return a.isPinned ? -1 : 1;
    });
    return list;
  }

  List<Note> get _notesInCurrentFolder {
    final list = _notes
        .where((n) =>
            n.categoryId == _currentFolderId &&
            !n.isArchived &&
            !n.isCalendarReminder)
        .toList();
    // Same idea for notes — pinned notes float to the top of the note
    // group (folders are always listed before notes regardless, per
    // _buildItems's ordering, so this only affects ordering within notes).
    list.sort((a, b) {
      if (a.isPinned == b.isPinned) return 0;
      return a.isPinned ? -1 : 1;
    });
    return list;
  }

  void _openFolder(Category folder) {
    setState(() {
      _folderPath.add(folder);
      _currentFolderId = folder.id;
    });
    widget.onStateChanged?.call();
  }

  bool goBack() {
    if (_folderPath.isEmpty) return false;
    setState(() {
      _folderPath.removeLast();
      _currentFolderId = _folderPath.isEmpty ? null : _folderPath.last.id;
    });
    widget.onStateChanged?.call();
    return true;
  }

  bool get isAtRoot => _folderPath.isEmpty;
  String get currentFolderName =>
      _folderPath.isEmpty ? 'Notes' : _folderPath.last.name;

  // The currently open folder's background theme, if it has one — used to
  // tint HomeScreen's AppBar while browsing inside that folder. Always
  // null at root, since root never carries a theme.
  String? get currentFolderBackgroundPath =>
      _folderPath.isEmpty ? null : _folderPath.last.backgroundImagePath;

  Category? _categoryById(String? id) {
    if (id == null) return null;
    try {
      return _categories.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  // ── Move to folder ──────────────────────────────────────────────────────

  // All descendant ids of a folder (children, grandchildren, ...) — used to
  // stop a folder being moved into itself or one of its own children.
  List<String> _descendantFolderIds(String folderId) {
    final result = <String>[];
    void collect(String parentId) {
      for (final c in _categories.where((c) => c.parentId == parentId)) {
        result.add(c.id);
        collect(c.id);
      }
    }
    collect(folderId);
    return result;
  }

  // Shared bottom sheet for picking a destination folder (or root) — used
  // by both note-move and folder-move. Shows only top-level folders by
  // default; each with subfolders gets an expand chevron to drill in,
  // rather than flattening everything into one long "A / B / C" list.
  Future<void> _showMoveDestinationPicker({
    required String? currentParentId,
    required List<String> excludeIds,
    required ValueChanged<String?> onSelected,
  }) async {
    final available = _categories
        .where((c) => !excludeIds.contains(c.id) && !c.isArchived && c.isVisible)
        .toList();

    final rootFolders = available.where((c) => c.parentId == null).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    List<Category> childrenOf(String id) =>
        available.where((c) => c.parentId == id).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    final expanded = <String>{};

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          List<Widget> buildFolderRows(
            Category folder,
            int depth, {
            bool isLastSibling = true,
            List<bool> ancestorIsLast = const [],
          }) {
            final children = childrenOf(folder.id);
            final isExpanded = expanded.contains(folder.id);
            final rows = <Widget>[
              _moveFolderRow(
                folder: folder,
                depth: depth,
                isLastSibling: isLastSibling,
                ancestorIsLast: ancestorIsLast,
                isCurrent: currentParentId == folder.id,
                hasChildren: children.isNotEmpty,
                isExpanded: isExpanded,
                onSelect: () {
                  Navigator.pop(context);
                  onSelected(folder.id);
                },
                onToggleExpand: () => setSheetState(() {
                  if (isExpanded) {
                    expanded.remove(folder.id);
                  } else {
                    expanded.add(folder.id);
                  }
                }),
              ),
            ];
            if (isExpanded) {
              for (var i = 0; i < children.length; i++) {
                rows.addAll(buildFolderRows(
                  children[i],
                  depth + 1,
                  isLastSibling: i == children.length - 1,
                  ancestorIsLast: [...ancestorIsLast, isLastSibling],
                ));
              }
            }
            return rows;
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text('Move to', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: const Text('Notes (root)'),
                    trailing: currentParentId == null ? const Icon(Icons.check, size: 18) : null,
                    onTap: () {
                      Navigator.pop(context);
                      onSelected(null);
                    },
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final folder in rootFolders) ...buildFolderRows(folder, 0),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Single row in the "Move to" folder tree — every row's themed card
  // spans the same full width regardless of nesting depth (no shrinking
  // per level). Nesting is communicated through indentation + a slightly
  // smaller, "open folder" icon at deeper levels, rather than connector
  // lines — lines don't read well here since every row is its own
  // independently-rounded, vertically-spaced card (theme images need
  // that), so a continuous line would always look broken between rows.
  Widget _moveFolderRow({
    required Category folder,
    required int depth,
    required bool isLastSibling,
    required List<bool> ancestorIsLast,
    required bool isCurrent,
    required bool hasChildren,
    required bool isExpanded,
    required VoidCallback onSelect,
    required VoidCallback onToggleExpand,
  }) {
    final hasTheme = folder.backgroundImagePath != null;
    final iconColor = hasTheme ? Colors.white : Colors.white70;

    return Padding(
      padding: EdgeInsets.fromLTRB(16 + (depth * 22), 2, 16, 2),
      child: Material(
        color: hasTheme ? null : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: hasTheme
              ? BoxDecoration(image: _backgroundDecorationImage(folder.backgroundImagePath!))
              : null,
          child: InkWell(
            onTap: onSelect,
            child: Container(
              decoration: hasTheme
                  ? BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.15),
                          Colors.black.withOpacity(0.55),
                        ],
                      ),
                    )
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: hasChildren
                        ? IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                            icon: AnimatedRotation(
                              turns: isExpanded ? 0.25 : 0,
                              duration: const Duration(milliseconds: 150),
                              child: Icon(Icons.chevron_right_rounded, color: iconColor),
                            ),
                            onPressed: onToggleExpand,
                          )
                        : null,
                  ),
                  Icon(
                    Icons.folder_outlined,
                    size: depth > 0 ? 16 : 18,
                    color: iconColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      folder.name,
                      style: TextStyle(
                        fontWeight: depth > 0 ? FontWeight.w500 : FontWeight.w600,
                        fontSize: depth > 0 ? 13.5 : 14.5,
                        color: hasTheme ? Colors.white : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isCurrent)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.check, size: 18, color: hasTheme ? Colors.white : null),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Long-press menu for a note — pin/unpin + move. Long-press used to
  // jump straight to the move picker; now it opens this small chooser
  // first, same pattern as the folder long-press menu.
  Future<void> _showNoteOptions(Note note) async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(note.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(note.isPinned ? 'Unpin note' : 'Pin note'),
              onTap: () {
                Navigator.pop(context);
                _togglePinNote(note);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Move to folder'),
              onTap: () {
                Navigator.pop(context);
                _moveNote(note);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePinNote(Note note) async {
    note.isPinned = !note.isPinned;
    await DatabaseService.instance.saveNote(note);
    _loadData();
  }

  Future<void> _moveNote(Note note) async {
    await _showMoveDestinationPicker(
      currentParentId: note.categoryId,
      excludeIds: const [],
      onSelected: (destinationId) async {
        if (destinationId == note.categoryId) return;
        final previousCategoryId = note.categoryId;

        note.categoryId = destinationId;
        await DatabaseService.instance.saveNote(note);
        _loadData();

        if (!mounted) return;
        showUndoToast(context, 'Moved "${note.title}"', onUndo: () async {
          note.categoryId = previousCategoryId;
          await DatabaseService.instance.saveNote(note);
          _loadData();
        });
      },
    );
  }

  Future<void> _moveFolder(Category folder) async {
    final excludeIds = [folder.id, ..._descendantFolderIds(folder.id)];
    await _showMoveDestinationPicker(
      currentParentId: folder.parentId,
      excludeIds: excludeIds,
      onSelected: (destinationId) async {
        if (destinationId == folder.parentId) return;
        final previousParentId = folder.parentId;

        folder.parentId = destinationId;
        await DatabaseService.instance.saveCategory(folder);
        _loadData();

        if (!mounted) return;
        showUndoToast(context, 'Moved "${folder.name}"', onUndo: () async {
          folder.parentId = previousParentId;
          await DatabaseService.instance.saveCategory(folder);
          _loadData();
        });
      },
    );
  }

  // ── Notes ────────────────────────────────────────────────────────────────

  Future<void> _openEditor({Note? note}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          note: note,
          initialCategoryId: note == null ? _currentFolderId : null,
        ),
      ),
    );
    if (saved == true) _loadData();
  }

  // Swiping a note: delete immediately from Hive. Undo restores it by
  // saving the same note object straight back — no waiting timer needed.
  Future<void> _swipeDeleteNote(Note note) async {
    setState(() => _notes.removeWhere((n) => n.id == note.id));

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
      _loadData();
    });

    // Undo window has passed (toast auto-dismisses after 5s) — only now is
    // it safe to actually delete the user-uploaded background file, since
    // Undo above re-saves the same `note` object and would need that file
    // to still exist if the user reverses the delete in time.
    await Future.delayed(const Duration(seconds: 5));
    if (!_notes.any((n) => n.id == note.id)) {
      await BackgroundImageService.instance.deleteIfUserUpload(note.backgroundImagePath);
    }
  }

  // Swiping a note right: archive it immediately. Undo flips isArchived
  // back to false and saves — instant in both directions.
  Future<void> _swipeArchiveNote(Note note) async {
    setState(() => _notes.removeWhere((n) => n.id == note.id));

    note.isArchived = true;
    await DatabaseService.instance.saveNote(note);

    if (!mounted) return;
    showUndoToast(context, '"${note.title}" archived', onUndo: () async {
      note.isArchived = false;
      await DatabaseService.instance.saveNote(note);
      _loadData();
    });
  }

  // ── Folders (categories) ───────────────────────────────────────────────

  Future<void> _showAddFolderDialog() async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            if (!_isSavingFolder) _saveFolder(controller.text);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!_isSavingFolder) _saveFolder(controller.text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  bool _isSavingFolder = false;

  Future<void> _saveFolder(String name) async {
    if (name.trim().isEmpty || _isSavingFolder) return;
    _isSavingFolder = true;

    final category = Category(
      id: '${DateTime.now().millisecondsSinceEpoch}_${_categories.length}',
      name: name.trim(),
      parentId: _currentFolderId,
      createdAt: DateTime.now(),
    );

    await DatabaseService.instance.saveCategory(category);
    _isSavingFolder = false;
    if (mounted) Navigator.pop(context);
    _loadData();
  }

  // Long-press menu for a folder — move + pin/unpin; hide/show was
  // removed, delete moved to swipe.
  Future<void> _showFolderOptions(Category folder) async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(folder.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(folder.isPinned ? 'Unpin folder' : 'Pin folder'),
              onTap: () {
                Navigator.pop(context);
                _togglePinFolder(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Move to folder'),
              onTap: () {
                Navigator.pop(context);
                _moveFolder(folder);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePinFolder(Category folder) async {
    folder.isPinned = !folder.isPinned;
    await DatabaseService.instance.saveCategory(folder);
    _loadData();
  }

  // Swiping a folder: delete immediately, including its children. Undo
  // restores the folder and all its children by re-saving them.
  Future<void> _swipeDeleteFolder(Category folder) async {
    final children = _categories.where((c) => c.parentId == folder.id).toList();
    final noteCount = _notes.where((n) => n.categoryId == folder.id).length;

    setState(() => _categories.removeWhere((c) => c.id == folder.id));

    for (final child in children) {
      await DatabaseService.instance.deleteCategory(child.id);
    }
    await DatabaseService.instance.deleteCategory(folder.id);

    final extra = [
      if (children.isNotEmpty) '${children.length} subfolder(s)',
      if (noteCount > 0) '$noteCount note(s) will be unfiled',
    ].join(', ');

    if (!mounted) return;
    showUndoToast(context, '"${folder.name}" deleted${extra.isNotEmpty ? ' ($extra)' : ''}', onUndo: () async {
      await DatabaseService.instance.saveCategory(folder);
      for (final child in children) {
        await DatabaseService.instance.saveCategory(child);
      }
      _loadData();
    });

    // Same Undo-window wait as note deletion — only sweep uploaded
    // background files for the folder and its children once the toast has
    // expired and none of them were restored via Undo.
    await Future.delayed(const Duration(seconds: 5));
    if (!_categories.any((c) => c.id == folder.id)) {
      await BackgroundImageService.instance.deleteIfUserUpload(folder.backgroundImagePath);
      for (final child in children) {
        if (!_categories.any((c) => c.id == child.id)) {
          await BackgroundImageService.instance.deleteIfUserUpload(child.backgroundImagePath);
        }
      }
    }
  }

  // Swiping a folder right: archive it immediately. Does NOT cascade to
  // children — only the folder itself is marked archived. Undo flips it back.
  Future<void> _swipeArchiveFolder(Category folder) async {
    setState(() => _categories.removeWhere((c) => c.id == folder.id));

    folder.isArchived = true;
    await DatabaseService.instance.saveCategory(folder);

    if (!mounted) return;
    showUndoToast(context, '"${folder.name}" archived', onUndo: () async {
      folder.isArchived = false;
      await DatabaseService.instance.saveCategory(folder);
      _loadData();
    });
  }

  // ── FAB entry point ─────────────────────────────────────────────────────

  Future<void> showAddOptions() async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('New Note'),
              onTap: () {
                Navigator.pop(context);
                _openEditor();
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New Folder'),
              onTap: () {
                Navigator.pop(context);
                _showAddFolderDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> openNewNote() async {
    await _openEditor();
  }

  // ── Formatting ───────────────────────────────────────────────────────────

  String _formatShort(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour == 0
        ? 12
        : dt.hour > 12
            ? dt.hour - 12
            : dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '${months[dt.month - 1]} ${dt.day} at $hour:$minute $period';
  }

  // ── Shared swipe-to-delete/archive backgrounds ──────────────────────────

  // Shared layout for both swipe-reveal backgrounds — a soft circular icon
  // badge next to a label. Only vertical margin is applied (matching the
  // gap between cards); horizontal margin is intentionally omitted so the
  // color fills flush against the card with no gap revealing the plain
  // Dismissible background underneath as you swipe. Only the outward
  // corners are rounded — the edge that meets the card stays square so it
  // reads as one continuous surface sliding apart, not two separate boxes.
  Widget _swipeActionBackground({
    required Alignment alignment,
    required List<Color> gradientColors,
    required IconData icon,
    required String label,
  }) {
    final isLeftAligned = alignment == Alignment.centerLeft;
    return Container(
      alignment: alignment,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: isLeftAligned ? Alignment.centerLeft : Alignment.centerRight,
          end: isLeftAligned ? Alignment.centerRight : Alignment.centerLeft,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(isLeftAligned ? 16 : 0),
          right: Radius.circular(isLeftAligned ? 0 : 16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: isLeftAligned ? TextDirection.ltr : TextDirection.rtl,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.22),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _deleteBackground() {
    return _swipeActionBackground(
      alignment: Alignment.centerRight,
      gradientColors: const [Color(0xFFFF8A80), Color(0xFFE53935)],
      icon: Icons.delete_outline_rounded,
      label: 'Delete',
    );
  }

  Widget _archiveBackground() {
    return _swipeActionBackground(
      alignment: Alignment.centerLeft,
      gradientColors: [
        Theme.of(context).colorScheme.primary.withOpacity(0.8),
        Theme.of(context).colorScheme.primary,
      ],
      icon: Icons.archive_outlined,
      label: 'Archive',
    );
  }

  // ── Tile builders ────────────────────────────────────────────────────────

  Widget _buildFolderTile(Category folder) {
    final subfolderCount = _categories.where((c) => c.parentId == folder.id).length;
    final noteCount = _notes.where((n) => n.categoryId == folder.id).length;

    return Dismissible(
      key: ValueKey('folder_${folder.id}'),
      direction: DismissDirection.horizontal,
      background: _archiveBackground(),
      secondaryBackground: _deleteBackground(),
      confirmDismiss: (direction) async {
        if (_isEditMode) return false;
        if (direction == DismissDirection.startToEnd) {
          _swipeArchiveFolder(folder);
        } else {
          _swipeDeleteFolder(folder);
        }
        return true;
      },
      child: Stack(
        children: [
          Material(
            color: const Color(0xFF3C3541),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: folder.backgroundImagePath != null
                  ? BoxDecoration(image: _backgroundDecorationImage(folder.backgroundImagePath!))
                  : null,
              child: InkWell(
                onTap: () =>
                    _isEditMode ? _selectFolderForTheming(folder.id) : _openFolder(folder),
                onLongPress: () => _isEditMode ? null : _showFolderOptions(folder),
                child: Container(
                  decoration: folder.backgroundImagePath != null
                      ? BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.15),
                              Colors.black.withOpacity(0.55),
                            ],
                          ),
                        )
                      : null,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.folder_rounded,
                          color: folder.backgroundImagePath != null
                              ? Colors.white
                              : Theme.of(context).colorScheme.primary,
                          size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              folder.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: folder.backgroundImagePath != null
                                    ? Colors.white
                                    : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if ((subfolderCount + noteCount) > 0) ...[
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (subfolderCount > 0) '$subfolderCount folder${subfolderCount == 1 ? '' : 's'}',
                                  if (noteCount > 0) '$noteCount note${noteCount == 1 ? '' : 's'}',
                                ].join(' · '),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: folder.backgroundImagePath != null
                                      ? Colors.white70
                                      : Colors.white.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      ],
                  ),
                ),
              ),
            ),
          ),
          if (_isEditMode) _selectionCheckbox(_selectedFolderId == folder.id),
          if (!_isEditMode && folder.isPinned) _pinBadge('folder_${folder.id}'),
        ],
      ),
    );
  }

  Widget _buildNoteCard(Note note) {
    final category = _categoryById(note.categoryId);
    final cardColor =
        note.colorValue != null ? Color(note.colorValue!) : _colorForId(note.id);
    final checklist = _parseChecklistPreview(note);
    final freeText = _freeTextPreview(note);

    return Dismissible(
      key: ValueKey('note_${note.id}'),
      direction: DismissDirection.horizontal,
      background: _archiveBackground(),
      secondaryBackground: _deleteBackground(),
      confirmDismiss: (direction) async {
        if (_isEditMode) return false;
        if (direction == DismissDirection.startToEnd) {
          _swipeArchiveNote(note);
        } else {
          _swipeDeleteNote(note);
        }
        return true;
      },
      child: Stack(
        children: [
          Material(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: note.backgroundImagePath != null
                  ? BoxDecoration(image: _backgroundDecorationImage(note.backgroundImagePath!))
                  : null,
              child: InkWell(
                onTap: () =>
                    _isEditMode ? _selectNoteForTheming(note.id) : _openEditor(note: note),
                onLongPress: () => _isEditMode ? null : _showNoteOptions(note),
                child: Container(
                  decoration: note.backgroundImagePath != null
                      ? BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.1),
                              Colors.black.withOpacity(0.6),
                            ],
                          ),
                        )
                      : null,
                  padding: const EdgeInsets.all(14),
                  child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (category != null && _currentFolderId == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '#${category.name}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(right: note.isPinned ? 18 : 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          note.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5,
                            color: note.backgroundImagePath != null
                                ? Colors.white
                                : Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (note.reminderAt != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(Icons.alarm_rounded,
                              size: 16,
                              color: note.backgroundImagePath != null
                                  ? Colors.white70
                                  : Colors.black54),
                        ),
                    ],
                  ),
                ),
                // Checklist preview — up to 4 rows shown, "+N more" if longer.
                if (checklist.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final item in checklist.take(4))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            item.value ? Icons.check_box : Icons.check_box_outline_blank,
                            size: 15,
                            color: note.backgroundImagePath != null
                                ? Colors.white70
                                : Colors.black54,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: note.backgroundImagePath != null
                                    ? Colors.white
                                    : Colors.black87,
                                decoration: item.value ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (checklist.length > 4)
                    Text(
                      '+ ${checklist.length - 4} more',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: note.backgroundImagePath != null
                            ? Colors.white70
                            : Colors.black54,
                      ),
                    ),
                ] else if (freeText.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    freeText,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: note.backgroundImagePath != null
                          ? Colors.white70
                          : Colors.black54,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  _formatShort(note.updatedAt),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: note.backgroundImagePath != null
                        ? Colors.white70
                        : Colors.black.withOpacity(0.45),
                  ),
                ),
              ],
            ),
          ),
              ),
            ),
          ),
          if (_isEditMode) _selectionCheckbox(_selectedNoteId == note.id),
          if (!_isEditMode && note.isPinned) _pinBadge('note_${note.id}'),
        ],
      ),
    );
  }

  // Builds the ordered list of (id, widget) pairs for whatever is in the

  // Builds the ordered list of (id, widget) pairs for whatever is in the
  // current folder — folders first, then notes — shared by both layout
  // calculations below so grid and list always agree on item order/identity.
  List<MapEntry<String, WidgetBuilder>> _buildItems(List<Category> subfolders, List<Note> notesHere) {
    return [
      for (final folder in subfolders)
        MapEntry('folder_${folder.id}', (context) => _buildFolderTile(folder)),
      for (final note in notesHere)
        MapEntry('note_${note.id}', (context) => _buildNoteCard(note)),
    ];
  }

  // Rough content-driven height estimate per item, in the SAME order as
  // _buildItems — folders are always one short row; notes grow with
  // however many checklist lines or how much free text they're showing.
  // This isn't pixel-perfect (real text wrap depends on font metrics we
  // don't have without a full layout pass), but it's close enough to stop
  // list-mode cards from clipping/overflowing the way a single flat
  // constant did.
  List<double> _estimateHeights(List<Category> subfolders, List<Note> notesHere) {
    const folderHeight = 72.0;

    // Matches the real Padding(all: 14) + title row + timestamp row used
    // inside _buildNoteCard, piece by piece, rather than one guessed
    // constant — the previous flat estimate kept undercounting because it
    // didn't separately account for top/bottom card padding AND the
    // timestamp line AND the checklist's own internal spacing.
    const cardPaddingTopBottom = 28.0; // padding: all(14) → 14 + 14
    const titleRowHeight = 24.0; // title text line, allowing 2-line wrap headroom
    const spacingBeforeBody = 8.0; // SizedBox(height: 8) before checklist/text
    const spacingBeforeTimestamp = 10.0; // SizedBox(height: 10)
    const timestampHeight = 16.0; // "Jun 19 at 11:13 PM" line
    const checklistRowHeight = 24.0; // icon+text row (~18) + bottom padding (3) + buffer
    const freeTextLineHeight = 19.0;
    const safetyBuffer = 10.0; // small cushion against font/wrap variance

    double baseHeight(int extraLines) =>
        cardPaddingTopBottom +
        titleRowHeight +
        spacingBeforeBody +
        spacingBeforeTimestamp +
        timestampHeight +
        safetyBuffer;

    final heights = <double>[];
    for (final _ in subfolders) {
      heights.add(folderHeight);
    }
    for (final note in notesHere) {
      final checklist = _parseChecklistPreview(note);
      final freeText = _freeTextPreview(note);
      double height = baseHeight(0);
      if (checklist.isNotEmpty) {
        final rows = checklist.take(4).length;
        height += checklistRowHeight * rows;
        if (checklist.length > 4) height += 18; // "+N more" line
      } else if (freeText.isNotEmpty) {
        final estimatedLines = (freeText.length / 28).ceil().clamp(1, 4);
        height += freeTextLineHeight * estimatedLines;
      }
      heights.add(height);
    }
    return heights;
  }

  @override
  Widget build(BuildContext context) {
    final subfolders = _subfolders;
    final notesHere = _notesInCurrentFolder;
    final isEmpty = subfolders.isEmpty && notesHere.isEmpty;

    return Column(
      children: [
        Expanded(
          child: isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.note_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        isAtRoot ? 'No notes yet' : 'This folder is empty',
                        style: TextStyle(fontSize: 18, color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to add a note or folder',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                )
              : _ReflowingLayout(
                  isGridView: _isGridView,
                  bottomPadding: _isEditMode ? 96 : 96,
                  items: _buildItems(subfolders, notesHere),
                  estimatedHeights: _estimateHeights(subfolders, notesHere),
                ),
        ),
        if (_isEditMode)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2831),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.palette_outlined, size: 16, color: Colors.white.withOpacity(0.6)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tap a note or folder to set its background',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: toggleEditMode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withOpacity(0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            color: Color(0xFFCB9BFF),
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Renders [child] once to measure its real height (via a post-frame
// RenderBox lookup), then reports that height back through [onMeasured].
// Used so grid mode can pack cards by their ACTUAL content height instead
// of a guessed constant — this is what makes true masonry packing (like
// Keep/Notion) possible without overflow.
class _MeasureSize extends StatefulWidget {
  final Widget child;
  final double width;
  final ValueChanged<double> onMeasured;

  const _MeasureSize({
    super.key,
    required this.child,
    required this.width,
    required this.onMeasured,
  });

  @override
  State<_MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<_MeasureSize> {
  final _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _key.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        widget.onMeasured(box.size.height);
      }
    });
    return SizedBox(
      width: widget.width,
      child: KeyedSubtree(key: _key, child: widget.child),
    );
  }
}

// Animates every card's own frame (position + size) between grid and list
// layouts, instead of swapping two unrelated widget trees. Each item keeps
// a stable key across both modes, so AnimatedPositioned can tween it from
// its grid rect straight to its list rect (or back) — this is what gives
// the "cards reflow into place" feel rather than a fade/cut.
// Wraps a single reflowing item with a tiny per-index stagger and a
// softer curve — without this, every card animates on the exact same
// clock and the whole reflow feels like one mechanical snap. Staggering
// the start by a few ms per index (capped, so a long list doesn't drift
// out of sync) makes the motion read as fluid, like cards "settling"
// into place one after another rather than jumping together.
class _StaggeredReflowItem extends StatefulWidget {
  final int index;
  final Rect rect;
  final Widget child;

  const _StaggeredReflowItem({
    super.key,
    required this.index,
    required this.rect,
    required this.child,
  });

  @override
  State<_StaggeredReflowItem> createState() => _StaggeredReflowItemState();
}

class _StaggeredReflowItemState extends State<_StaggeredReflowItem> {
  Rect? _targetRect;
  Rect? _displayRect;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _targetRect = widget.rect;
    _displayRect = widget.rect;
  }

  @override
  void didUpdateWidget(_StaggeredReflowItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rect != oldWidget.rect) {
      _targetRect = widget.rect;
      _delayTimer?.cancel();
      // Small staggered delay per index, capped at ~160ms so items far
      // down a long list don't lag noticeably behind the first ones.
      final delayMs = (widget.index * 14).clamp(0, 160);
      _delayTimer = Timer(Duration(milliseconds: delayMs), () {
        if (mounted) setState(() => _displayRect = _targetRect);
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rect = _displayRect ?? widget.rect;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutQuart,
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: widget.child,
    );
  }
}

class _ReflowingLayout extends StatefulWidget {
  final bool isGridView;
  final double bottomPadding;
  final List<MapEntry<String, WidgetBuilder>> items;
  // One estimated height per item (same order as `items`) — only used for
  // LIST mode now, where a single column makes a height guess reasonably
  // safe. Grid mode uses real measured heights instead (see below).
  final List<double> estimatedHeights;

  const _ReflowingLayout({
    required this.isGridView,
    required this.bottomPadding,
    required this.items,
    required this.estimatedHeights,
  });

  @override
  State<_ReflowingLayout> createState() => _ReflowingLayoutState();
}

class _ReflowingLayoutState extends State<_ReflowingLayout> {
  // Real measured heights for grid mode, keyed by item id — populated by
  // _MeasureSize after each card actually renders once at the grid column
  // width. Until a given item's real height is known, it falls back to a
  // safe default so layout doesn't jump wildly on first paint.
  final Map<String, double> _measuredGridHeights = {};

  void _onMeasured(String key, double height) {
    // Safety cushion above the raw measured height — on cold start
    // specifically, the off-screen measuring pass can run before text/font
    // metrics are fully settled, undershooting the real on-screen paint by
    // a noticeable margin (observed up to ~17px) until the next re-measure
    // corrects it. A generous fixed buffer absorbs that gap without
    // needing pixel-perfect parity between the two passes.
    final rounded = (height + 24).roundToDouble();
    if (_measuredGridHeights[key] == rounded) return;
    setState(() => _measuredGridHeights[key] = rounded);
  }

  @override
  Widget build(BuildContext context) {
    const horizontalPadding = 12.0;
    const topPadding = 8.0;
    const gridSpacing = 10.0;
    const listSpacing = 10.0;
    const defaultGridHeight = 150.0; // fallback only until first measured

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final usableWidth = width - horizontalPadding * 2;
        final colWidth = (usableWidth - gridSpacing) / 2;

        final rects = <Rect>[];

        if (widget.isGridView) {
          // True masonry packing: each item's real measured height (once
          // known) decides how tall its slot is — shortest-column-next
          // placement, same idea as Keep/Pinterest, no fixed guess.
          final colHeights = [topPadding, topPadding];
          for (var i = 0; i < widget.items.length; i++) {
            final key = widget.items[i].key;
            final height = _measuredGridHeights[key] ?? defaultGridHeight;
            final col = colHeights[0] <= colHeights[1] ? 0 : 1;
            final x = horizontalPadding + col * (colWidth + gridSpacing);
            final y = colHeights[col];
            rects.add(Rect.fromLTWH(x, y, colWidth, height));
            colHeights[col] = y + height + gridSpacing;
          }
        } else {
          var runningY = topPadding;
          for (var i = 0; i < widget.items.length; i++) {
            final height = widget.estimatedHeights[i];
            rects.add(Rect.fromLTWH(horizontalPadding, runningY, usableWidth, height));
            runningY += height + listSpacing;
          }
        }

        final maxBottom = rects.isEmpty
            ? topPadding
            : rects.map((r) => r.bottom).reduce((a, b) => a > b ? a : b);

        return Stack(
          children: [
            // Off-screen measuring pass: every item is rendered once at
            // the grid column width, invisibly, purely so _MeasureSize
            // can report its real height back into _measuredGridHeights.
            // Opacity 0 + IgnorePointer keeps it invisible and untappable
            // without skipping layout (unlike Offstage, which would skip
            // measurement entirely).
            Positioned(
              left: -99999,
              top: 0,
              child: RepaintBoundary(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final item in widget.items)
                          RepaintBoundary(
                            child: _MeasureSize(
                              key: ValueKey('measure_${item.key}'),
                              width: colWidth,
                              onMeasured: (h) => _onMeasured(item.key, h),
                              child: Builder(builder: item.value),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: SizedBox(
                height: maxBottom + widget.bottomPadding,
                child: Stack(
                  children: [
                    for (var i = 0; i < widget.items.length; i++)
                      _StaggeredReflowItem(
                        key: ValueKey(widget.items[i].key),
                        index: i,
                        rect: rects[i],
                        child: RepaintBoundary(
                          child: Builder(builder: widget.items[i].value),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
