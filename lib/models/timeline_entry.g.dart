// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TimelineEntryAdapter extends TypeAdapter<TimelineEntry> {
  @override
  final int typeId = 0;

  @override
  TimelineEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TimelineEntry(
      id: fields[0] as String,
      content: fields[1] as String,
      timestamp: fields[2] as DateTime,
      type: fields[3] as EntryType,
      completed: fields[4] as bool,
      scheduledDate: fields[5] as DateTime?,
      scheduledTime: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, TimelineEntry obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.content)
      ..writeByte(2)
      ..write(obj.timestamp)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.completed)
      ..writeByte(5)
      ..write(obj.scheduledDate)
      ..writeByte(6)
      ..write(obj.scheduledTime);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class EntryTypeAdapter extends TypeAdapter<EntryType> {
  @override
  final int typeId = 1;

  @override
  EntryType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return EntryType.note;
      case 1:
        return EntryType.task;
      default:
        return EntryType.note;
    }
  }

  @override
  void write(BinaryWriter writer, EntryType obj) {
    switch (obj) {
      case EntryType.note:
        writer.writeByte(0);
        break;
      case EntryType.task:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntryTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
