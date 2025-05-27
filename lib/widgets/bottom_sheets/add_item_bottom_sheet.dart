import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AddItemBottomSheet extends StatefulWidget {
  final String initialTab;
  final Function(String content, String type) onAddItem;
  final VoidCallback? onReloadEntries;

  const AddItemBottomSheet({
    super.key,
    this.initialTab = 'Notes',
    required this.onAddItem,
    this.onReloadEntries,
  });

  @override
  State<AddItemBottomSheet> createState() => _AddItemBottomSheetState();
}

class _AddItemBottomSheetState extends State<AddItemBottomSheet> {
  late String selectedType;
  List<TextEditingController> textControllers = [];
  List<FocusNode> focusNodes = [];

  @override
  void initState() {
    super.initState();
    selectedType = widget.initialTab;
    textControllers = [TextEditingController()];
    focusNodes = [FocusNode()];

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

  void _addNewField() {
    setState(() {
      final newController = TextEditingController();
      final newFocusNode = FocusNode();
      textControllers.add(newController);
      focusNodes.add(newFocusNode);

      Future.delayed(const Duration(milliseconds: 50), () {
        newFocusNode.requestFocus();
      });
    });
  }

  void _handleSubmit() {
    bool anEntryWasAdded = false;
    for (var controller in textControllers) {
      if (controller.text.isNotEmpty) {
        widget.onAddItem(controller.text, selectedType);
        anEntryWasAdded = true;
      }
    }

    if (anEntryWasAdded) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Please enter a ${selectedType.toLowerCase().substring(0, selectedType.length - 1)} to add.'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Segmented Control (Notes/Tasks) - with animated background
            LayoutBuilder(
              builder: (context, constraints) {
                final containerWidth = constraints.maxWidth;
                const gap = 4.0; // 4 pixel gap between tabs
                final tabWidth = (containerWidth - 8 - gap) /
                    2; // Account for container padding and gap

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEEEEE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE4E4E4)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x19000000),
                        blurRadius: 17.60,
                        offset: Offset(0, 4),
                        spreadRadius: 0,
                      )
                    ],
                  ),
                  height: 46, // Fixed height for the container
                  child: Stack(
                    children: [
                      // Animated background that slides
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        left: selectedType == 'Notes'
                            ? 0
                            : tabWidth + gap, // Add gap for Tasks position
                        top: 0,
                        bottom: 0,
                        width: tabWidth, // Equal width for both tabs
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                        ),
                      ),

                      // Tab buttons
                      Row(
                        children: <Widget>[
                          // Notes Tab - Exactly half width
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  selectedType = 'Notes';
                                });
                                // Reload entries when switching tabs to ensure fresh data
                                widget.onReloadEntries?.call();
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SvgPicture.asset(
                                      'assets/icons/notes.svg',
                                      width: 18,
                                      height: 18,
                                      colorFilter: ColorFilter.mode(
                                        selectedType == 'Notes'
                                            ? Colors.black
                                            : Colors.grey.shade600,
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Notes',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'Geist',
                                        color: selectedType == 'Notes'
                                            ? Colors.black
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Tasks Tab - Exactly half width
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  selectedType = 'Tasks';
                                });
                                // Reload entries when switching tabs to ensure fresh data
                                widget.onReloadEntries?.call();
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SvgPicture.asset(
                                      'assets/icons/tasks.svg',
                                      width: 18,
                                      height: 18,
                                      colorFilter: ColorFilter.mode(
                                        selectedType == 'Tasks'
                                            ? Colors.black
                                            : Colors.grey.shade600,
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Tasks',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'Geist',
                                        color: selectedType == 'Tasks'
                                            ? Colors.black
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Text Field(s) and "Add new note" button
            Column(
              children: [
                const SizedBox(height: 24),

                // Title - Different text based on selected type
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    selectedType == 'Notes'
                        ? "What's on your mind?"
                        : "What's important today?",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Geist',
                      color: Color(0xFF4B4B4B),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ListView for text fields
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: textControllers.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: TextField(
                        key: ValueKey(
                            'textfield_${index}_${textControllers[index].hashCode}'),
                        controller: textControllers[index],
                        focusNode: focusNodes[index],
                        minLines: 3,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText: selectedType == 'Notes'
                              ? "I've been thinking about..."
                              : "I need to...",
                          hintStyle: const TextStyle(color: Color(0xFFB3B3B3)),
                          fillColor: const Color(0xFFF9F9F9),
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: Color(0xFFE1E1E1),
                              width: 1.0,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: Color(0xFFE1E1E1),
                              width: 1.0,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
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
                    );
                  },
                ),

                // Add new note button
                Center(
                  child: TextButton(
                    onPressed: _addNewField,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      backgroundColor: const Color(0xFFFFFFFF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(
                            color: Color(0xFFE1E1E1), width: 1.0),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.add,
                            color: Color(0xFF858585), size: 20),
                        const SizedBox(width: 6),
                        Text(
                          selectedType == 'Notes'
                              ? 'Add new note'
                              : 'Add new task',
                          style: const TextStyle(
                            color: Color(0xFF848484),
                            fontFamily: 'Geist',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 48),

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
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Geist'),
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child:
                        Text(selectedType == 'Notes' ? 'Add note' : 'Add task'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// Helper function to show the bottom sheet
void showAddItemBottomSheet({
  required BuildContext context,
  String initialTab = 'Notes',
  required Function(String content, String type) onAddItem,
  VoidCallback? onReloadEntries,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext context) {
      return AddItemBottomSheet(
        initialTab: initialTab,
        onAddItem: onAddItem,
        onReloadEntries: onReloadEntries,
      );
    },
  );
}
