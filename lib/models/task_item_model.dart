// lib/models/task_item_model.dart
import 'package:hive/hive.dart';

part 'task_item_model.g.dart'; // Connects to the generated file

@HiveType(typeId: 2) // Matches TaskItemModelAdapter typeId
class TaskItemModel {
  @HiveField(0)
  String task;

  @HiveField(1)
  bool completed;

  TaskItemModel({
    required this.task,
    this.completed = false,
  });
}
