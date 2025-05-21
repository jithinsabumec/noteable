// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_item_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TaskItemModelAdapter extends TypeAdapter<TaskItemModel> {
  @override
  final int typeId = 2;

  @override
  TaskItemModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TaskItemModel(
      task: fields[0] as String,
      completed: fields[1] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, TaskItemModel obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.task)
      ..writeByte(1)
      ..write(obj.completed);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskItemModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
