import 'package:flutter/material.dart';
import 'package:noteable/models/timeline_entry.dart' as models;

import '../services/storage_service.dart';
import '../utils/date_formatter.dart';
import '../widgets/rive_checkbox.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen>
    with SingleTickerProviderStateMixin {
  final StorageService _storageService = StorageService();

  late final TabController _tabController;
  bool _isLoading = true;
  bool _showCompletedInAll = false;
  List<models.TimelineEntry> _allTasks = [];

  DateTime get _today => DateFormatter.startOfDay(DateTime.now());

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _loadTasks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
    });

    final tasks = await _storageService.getTasksInDateRange(null, null);

    if (!mounted) return;

    setState(() {
      _allTasks = tasks;
      _isLoading = false;
    });
  }

  DateTime _effectiveDate(models.TimelineEntry entry) {
    return DateFormatter.startOfDay(entry.scheduledDate ?? entry.timestamp);
  }

  int _compareBySchedule(models.TimelineEntry a, models.TimelineEntry b) {
    final dateCompare = _effectiveDate(a).compareTo(_effectiveDate(b));
    if (dateCompare != 0) return dateCompare;

    final aTime = DateFormatter.scheduledTimeToMinutes(a.scheduledTime) ?? 9999;
    final bTime = DateFormatter.scheduledTimeToMinutes(b.scheduledTime) ?? 9999;
    if (aTime != bTime) return aTime.compareTo(bTime);

    return a.timestamp.compareTo(b.timestamp);
  }

  List<models.TimelineEntry> _upcomingTasks() {
    final tasks = _allTasks.where((entry) {
      if (entry.type != models.EntryType.task || entry.completed) {
        return false;
      }

      if (entry.scheduledDate == null) {
        return true;
      }

      return !_effectiveDate(entry).isBefore(_today);
    }).toList()
      ..sort(_compareBySchedule);

    return tasks;
  }

  List<models.TimelineEntry> _overdueTasks() {
    final tasks = _allTasks.where((entry) {
      if (entry.type != models.EntryType.task || entry.completed) {
        return false;
      }

      if (entry.scheduledDate == null) {
        return false;
      }

      return _effectiveDate(entry).isBefore(_today);
    }).toList()
      ..sort(_compareBySchedule);

    return tasks;
  }

  List<models.TimelineEntry> _allTabTasks() {
    final tasks = _allTasks.where((entry) {
      if (entry.type != models.EntryType.task) {
        return false;
      }
      if (_showCompletedInAll) {
        return true;
      }
      return !entry.completed;
    }).toList()
      ..sort(_compareBySchedule);

    return tasks;
  }

  Future<void> _toggleTaskCompletion(
    models.TimelineEntry entry,
    bool completed,
  ) async {
    final updated = entry.copyWith(completed: completed);
    await _storageService.updateEntry(updated);
    await _loadTasks();
  }

  Widget _buildTaskList(List<models.TimelineEntry> tasks,
      {bool grouped = false}) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (tasks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'No tasks here yet.',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 16,
              color: Color(0xFF666666),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (!grouped) {
      return RefreshIndicator(
        onRefresh: _loadTasks,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final task = tasks[index];
            return _TaskCard(
              entry: task,
              onToggle: (newValue) {
                if (newValue == null) return;
                _toggleTaskCompletion(task, newValue);
              },
            );
          },
        ),
      );
    }

    final groupedTasks = <DateTime?, List<models.TimelineEntry>>{};
    for (final task in tasks) {
      final key = task.scheduledDate == null ? null : _effectiveDate(task);
      groupedTasks.putIfAbsent(key, () => <models.TimelineEntry>[]).add(task);
    }

    final keys = groupedTasks.keys.toList()
      ..sort((a, b) {
        if (a == null && b == null) return 0;
        if (a == null) return 1;
        if (b == null) return -1;
        return a.compareTo(b);
      });

    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: keys.length,
        itemBuilder: (context, index) {
          final key = keys[index];
          final sectionTasks = groupedTasks[key]!..sort(_compareBySchedule);

          final title = key == null
              ? 'Unscheduled'
              : DateFormatter.formatDate(key).toLowerCase();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF666666),
                  ),
                ),
              ),
              ...sectionTasks.map((task) {
                return _TaskCard(
                  entry: task,
                  onToggle: (newValue) {
                    if (newValue == null) return;
                    _toggleTaskCompletion(task, newValue);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final upcomingTasks = _upcomingTasks();
    final overdueTasks = _overdueTasks();
    final allTasks = _allTabTasks();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Tasks',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Color(0xFF171717),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF171717),
          unselectedLabelColor: const Color(0xFF8A8A8A),
          indicatorColor: const Color(0xFF171717),
          labelStyle: const TextStyle(
            fontFamily: 'Geist',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Overdue'),
            Tab(text: 'All'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTaskList(upcomingTasks),
          _buildTaskList(overdueTasks),
          Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Show completed',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Switch.adaptive(
                      value: _showCompletedInAll,
                      onChanged: (value) {
                        setState(() {
                          _showCompletedInAll = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildTaskList(allTasks, grouped: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final models.TimelineEntry entry;
  final ValueChanged<bool?> onToggle;

  const _TaskCard({
    required this.entry,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final dateLabel = entry.scheduledDate == null
        ? ''
        : DateFormatter.formatScheduledDateLabel(entry.scheduledDate);
    final timeLabel = entry.scheduledTime == null
        ? ''
        : DateFormatter.formatScheduledTimeLabel(entry.scheduledTime);
    final hasDate = dateLabel.isNotEmpty;
    final hasTime = timeLabel.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFE1E1E1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: RiveCheckbox(
              isChecked: entry.completed,
              onChanged: onToggle,
              size: 28,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => onToggle(!entry.completed),
                  child: Text(
                    entry.content,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      decoration:
                          entry.completed ? TextDecoration.lineThrough : null,
                      decorationColor:
                          entry.completed ? Colors.grey.shade400 : null,
                      color: entry.completed
                          ? Colors.grey.shade400
                          : const Color(0xFF171717),
                    ),
                  ),
                ),
                if (hasDate || hasTime) const SizedBox(height: 8),
                if (hasDate || hasTime)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (hasDate)
                        _MetaChip(
                          label: dateLabel,
                          icon: Icons.calendar_today_outlined,
                        ),
                      if (hasTime)
                        _MetaChip(
                          label: timeLabel,
                          icon: Icons.schedule_outlined,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _MetaChip({
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F5FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFD9E2FF),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: const Color(0xFF2F55CC),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'Geist',
              fontWeight: FontWeight.w600,
              color: Color(0xFF2F55CC),
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
