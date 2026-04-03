import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

enum AppActionButtonStyle {
  filled,
  outlined,
}

class AppActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final AppActionButtonStyle style;
  final double? fontSize;
  final FontWeight fontWeight;
  final bool small;

  const AppActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.style = AppActionButtonStyle.outlined,
    this.fontSize,
    this.fontWeight = FontWeight.w600,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveFontSize = fontSize ?? (small ? 10 : 13);
    final padding = small
        ? const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingSm,
            vertical: AppTheme.spacingXs + 2,
          )
        : const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMd,
            vertical: AppTheme.spacingSm,
          );

    final bgColor = style == AppActionButtonStyle.filled
        ? color
        : color.withValues(alpha: 0.08);

    final fgColor = style == AppActionButtonStyle.filled ? Colors.white : color;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(AppTheme.radiusInput),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusInput),
        onTap: onTap,
        child: Container(
          padding: padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: effectiveFontSize + 2, color: fgColor),
              const SizedBox(width: AppTheme.spacingXs + 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: effectiveFontSize,
                  fontWeight: fontWeight,
                  color: fgColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
