import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';

class SummaryField extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const SummaryField({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.textMutedColor,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color ?? context.textColor,
            ),
          ),
        ],
      ),
    );
  }
}
