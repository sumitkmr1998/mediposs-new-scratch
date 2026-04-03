import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

enum AppStatusBadgeStyle {
  dot,
  icon,
  text,
}

class AppStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final AppStatusBadgeStyle style;
  final double? fontSize;
  final FontWeight fontWeight;
  final bool outlined;

  const AppStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.style = AppStatusBadgeStyle.dot,
    this.fontSize,
    this.fontWeight = FontWeight.w700,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveFontSize = fontSize ?? 10;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingSm,
        vertical: AppTheme.spacingXs + 1,
      ),
      decoration: BoxDecoration(
        color: outlined
            ? color.withValues(alpha: 0.08)
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
        border:
            outlined ? Border.all(color: color.withValues(alpha: 0.2)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (style == AppStatusBadgeStyle.dot)
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            )
          else if (style == AppStatusBadgeStyle.icon && icon != null)
            Icon(icon, size: effectiveFontSize + 2, color: color)
          else if (style == AppStatusBadgeStyle.text)
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: effectiveFontSize,
                fontWeight: fontWeight,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          if (style != AppStatusBadgeStyle.text) ...[
            const SizedBox(width: AppTheme.spacingXs + 2),
            Text(
              label,
              style: TextStyle(
                fontSize: effectiveFontSize,
                fontWeight: fontWeight,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
