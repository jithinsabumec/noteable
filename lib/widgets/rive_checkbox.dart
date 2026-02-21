import 'package:flutter/material.dart';

class RiveCheckbox extends StatelessWidget {
  final bool isChecked;
  final ValueChanged<bool?> onChanged;
  final double size;

  const RiveCheckbox({
    super.key,
    required this.isChecked,
    required this.onChanged,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Checkbox(
        value: isChecked,
        onChanged: onChanged,
        side: const BorderSide(color: Color(0xFF1A1A1A), width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        activeColor: const Color(0xFF1A1A1A),
        checkColor: Colors.white,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
