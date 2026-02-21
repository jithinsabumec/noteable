import 'package:flutter/material.dart';

class PlusIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.52941
      ..strokeCap = StrokeCap.round;

    final scaleX = size.width / 24.0;
    final scaleY = size.height / 24.0;

    canvas.drawLine(
      Offset(12 * scaleX, 2 * scaleY),
      Offset(12 * scaleX, 22 * scaleY),
      paint,
    );

    canvas.drawLine(
      Offset(2 * scaleX, 12 * scaleY),
      Offset(22 * scaleX, 12 * scaleY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
