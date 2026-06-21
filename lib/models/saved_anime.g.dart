// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'saved_anime.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SavedAnimeAdapter extends TypeAdapter<SavedAnime> {
  @override
  final int typeId = 3;

  @override
  SavedAnime read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SavedAnime(
      uniqueKey: fields[0] as String,
      source: fields[1] as HiveAnimeSource,
      malId: fields[2] as int,
      title: fields[3] as String,
      imageUrl: fields[4] as String,
      synopsis: fields[5] as String,
      score: fields[6] as double?,
      genres: (fields[7] as List).cast<String>(),
      listType: fields[8] as String,
      savedAt: fields[9] as DateTime,
      remarks: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SavedAnime obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.uniqueKey)
      ..writeByte(1)
      ..write(obj.source)
      ..writeByte(2)
      ..write(obj.malId)
      ..writeByte(3)
      ..write(obj.title)
      ..writeByte(4)
      ..write(obj.imageUrl)
      ..writeByte(5)
      ..write(obj.synopsis)
      ..writeByte(6)
      ..write(obj.score)
      ..writeByte(7)
      ..write(obj.genres)
      ..writeByte(8)
      ..write(obj.listType)
      ..writeByte(9)
      ..write(obj.savedAt)
      ..writeByte(10)
      ..write(obj.remarks);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedAnimeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class HiveAnimeSourceAdapter extends TypeAdapter<HiveAnimeSource> {
  @override
  final int typeId = 2;

  @override
  HiveAnimeSource read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return HiveAnimeSource.jikan;
      case 1:
        return HiveAnimeSource.anilist;
      default:
        return HiveAnimeSource.jikan;
    }
  }

  @override
  void write(BinaryWriter writer, HiveAnimeSource obj) {
    switch (obj) {
      case HiveAnimeSource.jikan:
        writer.writeByte(0);
        break;
      case HiveAnimeSource.anilist:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveAnimeSourceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
