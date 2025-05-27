import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../main.dart';

class ExpandableFAB extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onAddNote;
  final VoidCallback onAddTask;
  final VoidCallback onStartRecording;

  const ExpandableFAB({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    required this.onAddNote,
    required this.onAddTask,
    required this.onStartRecording,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Note button (visible when expanded)
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: MaterialButton(
              onPressed: onAddNote,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(width: 2, color: Color(0xFFE1E1E1)),
              ),
              color: Colors.white,
              padding: EdgeInsets.zero,
              minWidth: 62,
              height: 62,
              child: Container(
                width: 62,
                height: 62,
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  shadows: const [
                    BoxShadow(
                      color: Color(0x15000000),
                      blurRadius: 10.0,
                      offset: Offset(0, 3),
                      spreadRadius: 0,
                    )
                  ],
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/notes.svg',
                    width: 22,
                    height: 22,
                  ),
                ),
              ),
            ),
          ),

        // Task button (visible when expanded)
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: MaterialButton(
              onPressed: onAddTask,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(width: 2, color: Color(0xFFE1E1E1)),
              ),
              color: Colors.white,
              padding: EdgeInsets.zero,
              minWidth: 62,
              height: 62,
              child: Container(
                width: 62,
                height: 62,
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  shadows: const [
                    BoxShadow(
                      color: Color(0x15000000),
                      blurRadius: 10.0,
                      offset: Offset(0, 3),
                      spreadRadius: 0,
                    )
                  ],
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/tasks.svg',
                    width: 28,
                    height: 28,
                  ),
                ),
              ),
            ),
          ),

        // Record button (visible when expanded)
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: MaterialButton(
              onPressed: onStartRecording,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(width: 2, color: Colors.white),
              ),
              padding: EdgeInsets.zero,
              minWidth: 62,
              height: 62,
              color: Colors.transparent,
              child: Container(
                width: 62,
                height: 62,
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment(-0.00, -0.00),
                    end: Alignment(1.00, 1.00),
                    colors: [Color(0xFF598FFF), Color(0xFF1E44FF)],
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  shadows: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 17.60,
                      offset: Offset(0, 4),
                      spreadRadius: 0,
                    )
                  ],
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/record_icon.svg',
                    width: 24,
                    height: 24,
                    colorFilter:
                        const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                  ),
                ),
              ),
            ),
          ),

        // Main FAB (plus/close)
        MaterialButton(
          onPressed: onToggle,
          elevation: 0,
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: EdgeInsets.zero,
          minWidth: 62,
          height: 62,
          child: Container(
            width: 62,
            height: 62,
            padding: const EdgeInsets.all(12),
            decoration: ShapeDecoration(
              gradient: const LinearGradient(
                begin: Alignment(-0.00, -0.00),
                end: Alignment(1.00, 1.00),
                colors: [Color(0xFF413F3F), Color(0xFF0C0C0C)],
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              shadows: const [
                BoxShadow(
                  color: Color(0x15000000),
                  blurRadius: 10.0,
                  offset: Offset(0, 3),
                  spreadRadius: 0,
                )
              ],
            ),
            child: Center(
              child: AnimatedRotation(
                turns: isExpanded ? 0.125 : 0, // 0.125 turns = 45 degrees
                duration: const Duration(milliseconds: 200),
                curve: Curves.fastOutSlowIn,
                child: CustomPaint(
                  size: const Size(24, 24),
                  painter: PlusIconPainter(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
