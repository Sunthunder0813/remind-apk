import 'package:hive/hive.dart';

part 'checklist_item.g.dart';

// A single checklist row, stored as a proper Hive object instead of being
// encoded as "- [ ] text" lines inside Note.content. This is the source
// of truth for checklist data going forward — content's text encoding is
// regenerated FROM this list on every save, purely for backward-compatible
// display (free-text previews, etc.), not the other way around.
//
// `id` is a stable string (not an index) so a specific item can be
// addressed reliably from outside the editor — e.g. by the home screen
// widget's tap-to-toggle handler, which only has a noteId + itemId to go
// on and has no concept of "current list position".
@HiveType(typeId: 4)
class ChecklistItem extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late String text;

  @HiveField(2)
  bool done;

  ChecklistItem({
    required this.id,
    required this.text,
    this.done = false,
  });
}