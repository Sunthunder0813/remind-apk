// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class NoteAdapter extends TypeAdapter<Note> {
  @override
  final int typeId = 0;

  @override
  Note read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Note(
      id: fields[0] as String,
      title: fields[1] as String,
      content: fields[2] as String,
      createdAt: fields[3] as DateTime,
      updatedAt: fields[4] as DateTime,
      reminderAt: fields[5] as DateTime?,
      categoryId: fields[6] as String?,
      isArchived: fields[7] == null ? false : fields[7] as bool,
      isPinned: fields[8] == null ? false : fields[8] as bool,
      colorValue: fields[9] as int?,
      backgroundImagePath: fields[10] as String?,
      isCompleted: fields[11] == null ? false : fields[11] as bool,
      isCalendarReminder: fields[12] == null ? false : fields[12] as bool,
      calendarDate: fields[13] as DateTime?,
      checklistItems: fields[14] == null
          ? []
          : (fields[14] as List?)?.cast<ChecklistItem>(),
    );
  }

  @override
  void write(BinaryWriter writer, Note obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.content)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.updatedAt)
      ..writeByte(5)
      ..write(obj.reminderAt)
      ..writeByte(6)
      ..write(obj.categoryId)
      ..writeByte(7)
      ..write(obj.isArchived)
      ..writeByte(8)
      ..write(obj.isPinned)
      ..writeByte(9)
      ..write(obj.colorValue)
      ..writeByte(10)
      ..write(obj.backgroundImagePath)
      ..writeByte(11)
      ..write(obj.isCompleted)
      ..writeByte(12)
      ..write(obj.isCalendarReminder)
      ..writeByte(13)
      ..write(obj.calendarDate)
      ..writeByte(14)
      ..write(obj.checklistItems);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
