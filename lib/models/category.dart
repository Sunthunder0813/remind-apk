import 'package:hive/hive.dart';

part 'category.g.dart';

@HiveType(typeId: 1)
class Category extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late String name;

  @HiveField(2)
  String? parentId; // Nullable — if null, this is a root-level category. If set, it's a child.

  @HiveField(3, defaultValue: true)
  late bool isVisible; // Controls show/hide in the UI (Phase 3 feature)

  @HiveField(4)
  late DateTime createdAt;

  @HiveField(5, defaultValue: false)
  bool isArchived; // True when the folder has been swiped into Archive

  @HiveField(6, defaultValue: null)
  String? backgroundImagePath;

  @HiveField(7, defaultValue: false)
  bool isPinned;

  Category({
    required this.id,
    required this.name,
    this.parentId,
    this.isVisible = true,
    required this.createdAt,
    this.isArchived = false,
    this.backgroundImagePath,
    this.isPinned = false,
  });
}