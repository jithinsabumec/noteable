// Timeline data models
class TimelineEntry {
  final String timestamp;
  final bool isDaytime;
  final List<String> notes;
  final List<TaskItem> tasks;
  final List<TimelineItemRef> itemOrder;

  TimelineEntry({
    required this.timestamp,
    required this.isDaytime,
    required this.notes,
    required this.tasks,
    required this.itemOrder,
  });

  // Add a convenience method to access items by their ordered position
  dynamic getItemAt(int orderIndex) {
    if (orderIndex < 0 || orderIndex >= itemOrder.length) return null;

    final ref = itemOrder[orderIndex];
    if (ref.type == ItemType.note && ref.index < notes.length) {
      return notes[ref.index];
    } else if (ref.type == ItemType.task && ref.index < tasks.length) {
      return tasks[ref.index];
    }
    return null;
  }

  // Method to calculate reference index for a specific item
  TimelineItemRef? findItemRef(ItemType type, int index) {
    for (int i = 0; i < itemOrder.length; i++) {
      if (itemOrder[i].type == type && itemOrder[i].index == index) {
        return itemOrder[i];
      }
    }
    return null;
  }

  // Get the ordered position of an item
  int getOrderPosition(ItemType type, int index) {
    for (int i = 0; i < itemOrder.length; i++) {
      if (itemOrder[i].type == type && itemOrder[i].index == index) {
        return i;
      }
    }
    return -1; // Not found
  }
}

class TaskItem {
  String task;
  bool completed;
  DateTime? scheduledDate;
  String? scheduledTime;

  TaskItem({
    required this.task,
    this.completed = false,
    this.scheduledDate,
    this.scheduledTime,
  });
}

// Helper classes for managing ordered items in TimelineEntry
enum ItemType { note, task }

class TimelineItemRef {
  final ItemType type;
  int index; // Index within the original notes or tasks list
  final String storageId; // ID from models.TimelineEntry

  TimelineItemRef(
      {required this.type, required this.index, required this.storageId});

  @override
  String toString() => '$type:$index (ID:$storageId)';
}
