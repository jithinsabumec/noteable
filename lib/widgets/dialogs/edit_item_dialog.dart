import 'package:flutter/material.dart';
import '../../models/timeline_models.dart';
import '../../services/item_management_service.dart';
import '../../utils/date_formatter.dart';

class EditItemDialog extends StatefulWidget {
  final String timestamp;
  final int contentListIndex;
  final int orderIndex;
  final ItemType itemType;
  final String content;
  final String storageId;
  final bool? completed;
  final DateTime? scheduledDate;
  final String? scheduledTime;
  final ItemManagementService itemManagementService;
  final DateTime selectedDate;
  final Map<String, List<TimelineEntry>> timelineEntriesByDate;
  final VoidCallback onStateUpdate;

  const EditItemDialog({
    super.key,
    required this.timestamp,
    required this.contentListIndex,
    required this.orderIndex,
    required this.itemType,
    required this.content,
    required this.storageId,
    this.completed,
    this.scheduledDate,
    this.scheduledTime,
    required this.itemManagementService,
    required this.selectedDate,
    required this.timelineEntriesByDate,
    required this.onStateUpdate,
  });

  @override
  State<EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<EditItemDialog> {
  late List<TextEditingController> textControllers;
  late List<FocusNode> focusNodes;
  late String selectedType;
  late bool isTaskCompleted;
  DateTime? selectedScheduledDate;
  String? selectedScheduledTime;

  @override
  void initState() {
    super.initState();

    // Create a new controller initialized with the existing content
    textControllers = [TextEditingController(text: widget.content)];
    focusNodes = [FocusNode()];

    // Initialize with the type of the current item
    selectedType = widget.itemType == ItemType.note ? 'Notes' : 'Tasks';

    // Initialize completed status for tasks
    isTaskCompleted = widget.completed ?? false;
    selectedScheduledDate = widget.scheduledDate == null
        ? null
        : DateFormatter.startOfDay(widget.scheduledDate!);
    selectedScheduledTime = DateFormatter.normalizeScheduledTime(
      widget.scheduledTime,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (focusNodes.isNotEmpty) {
        focusNodes.first.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (var controller in textControllers) {
      controller.dispose();
    }
    for (var node in focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Drag handle
            Center(
              child: Container(
                width: 60,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              'Edit ${selectedType.substring(0, selectedType.length - 1)}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                fontFamily: 'Geist',
                color: Color(0xFF171717),
              ),
            ),
            const SizedBox(height: 16),

            // Text field
            TextField(
              controller: textControllers.first,
              focusNode: focusNodes.first,
              minLines: 3,
              maxLines: 5,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: selectedType == 'Notes'
                    ? "I've been thinking about..."
                    : "I need to...",
                hintStyle: const TextStyle(color: Color(0xFFB3B3B3)),
                fillColor: const Color(0xFFF9F9F9),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFFE1E1E1),
                    width: 1.0,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFFE1E1E1),
                    width: 1.0,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFFE1E1E1),
                    width: 1.0,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),

            if (selectedType == 'Tasks') ...[
              const SizedBox(height: 16),
              const Text(
                'Schedule',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Geist',
                  color: Color(0xFF2D2D2D),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickScheduledDate,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        selectedScheduledDate == null
                            ? 'No date'
                            : DateFormatter.formatShortMonthDay(
                                selectedScheduledDate!,
                              ),
                        style: const TextStyle(
                          fontFamily: 'Geist',
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1F1F1F),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        selectedScheduledDate = null;
                      });
                    },
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        color: Color(0xFF5D5D5D),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickScheduledTime,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        selectedScheduledTime == null
                            ? 'No time'
                            : DateFormatter.formatScheduledTimeLabel(
                                selectedScheduledTime,
                              ),
                        style: const TextStyle(
                          fontFamily: 'Geist',
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1F1F1F),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        selectedScheduledTime = null;
                      });
                    },
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        color: Color(0xFF5D5D5D),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 32),

            // Bottom Action Buttons
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Geist'),
                      foregroundColor: const Color(0xFF4B4B4B),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final newContent = textControllers.first.text;
                      if (newContent.isNotEmpty) {
                        await widget.itemManagementService.updateItem(
                          timestamp: widget.timestamp,
                          orderIndexInItemOrder: widget.orderIndex,
                          newItemType: widget.itemType,
                          newContent: newContent,
                          newCompleted: isTaskCompleted,
                          originalItemType: widget.itemType,
                          storageId: widget.storageId,
                          newScheduledDate: selectedType == 'Tasks'
                              ? selectedScheduledDate
                              : null,
                          newScheduledTime: selectedType == 'Tasks'
                              ? selectedScheduledTime
                              : null,
                          applyScheduleUpdates: selectedType == 'Tasks',
                          selectedDate: widget.selectedDate,
                          timelineEntriesByDate: widget.timelineEntriesByDate,
                          onStateUpdate: widget.onStateUpdate,
                        );
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Geist'),
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const SizedBox(
                height: 24), // Additional bottom spacing to match add modal
          ],
        ),
      ),
    );
  }

  Future<void> _pickScheduledDate() async {
    final initialDate = selectedScheduledDate ?? DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null) return;

    setState(() {
      selectedScheduledDate = DateFormatter.startOfDay(pickedDate);
    });
  }

  Future<void> _pickScheduledTime() async {
    final initialTime =
        _timeOfDayFromStorage(selectedScheduledTime) ?? TimeOfDay.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (pickedTime == null) return;

    setState(() {
      selectedScheduledTime = _toStorageTime(pickedTime);
    });
  }

  TimeOfDay? _timeOfDayFromStorage(String? value) {
    final normalized = DateFormatter.normalizeScheduledTime(value);
    if (normalized == null) {
      return null;
    }

    final parts = normalized.split(':');
    if (parts.length != 2) {
      return null;
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  String _toStorageTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

// Helper function to show the edit item dialog
void showEditItemDialog({
  required BuildContext context,
  required String timestamp,
  required int contentListIndex,
  required int orderIndex,
  required ItemType itemType,
  required String content,
  required String storageId,
  bool? completed,
  DateTime? scheduledDate,
  String? scheduledTime,
  required ItemManagementService itemManagementService,
  required DateTime selectedDate,
  required Map<String, List<TimelineEntry>> timelineEntriesByDate,
  required VoidCallback onStateUpdate,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext context) {
      return EditItemDialog(
        timestamp: timestamp,
        contentListIndex: contentListIndex,
        orderIndex: orderIndex,
        itemType: itemType,
        content: content,
        storageId: storageId,
        completed: completed,
        scheduledDate: scheduledDate,
        scheduledTime: scheduledTime,
        itemManagementService: itemManagementService,
        selectedDate: selectedDate,
        timelineEntriesByDate: timelineEntriesByDate,
        onStateUpdate: onStateUpdate,
      );
    },
  );
}
