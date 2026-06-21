import 'package:hive/hive.dart';
import 'checklist_item.dart';

// This tells Hive to generate an adapter for this class.
// The typeId must be unique across all your Hive models.
part 'note.g.dart';

@HiveType(typeId: 0)
class Note extends HiveObject {
  @HiveField(0)
  late String id; // Unique identifier (we'll use UUID later, for now a timestamp string)

  @HiveField(1)
  late String title;

  @HiveField(2)
  late String content;

  @HiveField(3)
  late DateTime createdAt;

  @HiveField(4)
  late DateTime updatedAt;

  @HiveField(5)
  DateTime? reminderAt; // Nullable — not every note has a reminder

  @HiveField(6)
  String? categoryId; // Nullable — a note may not belong to any category

  @HiveField(7, defaultValue: false)
  bool isArchived; // True when the note has been swiped into Archive

  @HiveField(8, defaultValue: false)
  bool isPinned; // True when the note should float to the top of its folder

  @HiveField(9)
  int? colorValue; // Nullable ARGB int for an accent color; null = default theme color

  @HiveField(10, defaultValue: null)
  String? backgroundImagePath; // Nullable path to a theme background image — either an
  // "asset:" prefixed bundled preset (e.g. "asset:assets/backgrounds/dusty_blue.jpg")
  // or an absolute file path to a user-uploaded photo copied into app storage.
  // Null = no background image, card falls back to its solid palette color.

  @HiveField(11, defaultValue: false)
  bool isCompleted; // True when checked off as done (e.g. on the Calendar tab todo list)

  @HiveField(12, defaultValue: false)
  bool isCalendarReminder; // True when created via the Calendar tab's quick-add flow —
  // these are excluded from the main Notes list/grid, since they're meant to live
  // only on the Calendar tab and the home screen widget, not mixed in with regular notes.

  @HiveField(13, defaultValue: null)
  DateTime? calendarDate; // The calendar day this note belongs to, independent of
  // reminderAt. Only set on notes created via the Calendar tab — lets a note be
  // grouped under a specific day even when reminderAt is null (no time chosen yet).
  // Regular notes (created via the Notes tab) leave this null and aren't affected.

  @HiveField(14, defaultValue: [])
  List<ChecklistItem> checklistItems; // Source of truth for checklist data — the
  // editor reads/writes this directly. `content`'s "- [ ] text" line encoding is
  // regenerated FROM this list on every save, purely for display/preview
  // compatibility (free-text previews etc.) — never parsed back the other way.

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.reminderAt,
    this.categoryId,
    this.isArchived = false,
    this.isPinned = false,
    this.colorValue,
    this.backgroundImagePath,
    this.isCompleted = false,
    this.isCalendarReminder = false,
    this.calendarDate,
    List<ChecklistItem>? checklistItems,
  }) : checklistItems = checklistItems ?? [];
}