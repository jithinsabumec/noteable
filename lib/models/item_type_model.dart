import 'package:hive/hive.dart';

part 'item_type_model.g.dart'; // Connects to the generated file

@HiveType(
    typeId: 3) // Matches ItemTypeModelAdapter typeId in item_type_model.g.dart
enum ItemTypeModel {
  @HiveField(0)
  note,
  @HiveField(1)
  task,
}

@HiveType(
    typeId:
        4) // Matches TimelineItemRefModelAdapter typeId in item_type_model.g.dart
class TimelineItemRefModel {
  @HiveField(0)
  final ItemTypeModel type;

  @HiveField(1)
  final int index;

  TimelineItemRefModel({
    required this.type,
    required this.index,
  });
}
