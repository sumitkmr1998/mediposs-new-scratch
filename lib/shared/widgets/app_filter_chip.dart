import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

enum AppFilterChipStyle {
  filled,
  outlined,
}

class AppFilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? activeColor;
  final AppFilterChipStyle style;
  final double? fontSize;
  final FontWeight fontWeight;

  const AppFilterChip({
    super.key,
    required this.label,
    this.icon,
    this.isSelected = false,
    required this.onTap,
    this.activeColor,
    this.style = AppFilterChipStyle.outlined,
    this.fontSize,
    this.fontWeight = FontWeight.w700,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = activeColor ?? AppTheme.primary;
    final effectiveFontSize = fontSize ?? 13;

    final bgColor = isSelected
        ? (style == AppFilterChipStyle.filled
            ? accentColor
            : accentColor.withValues(alpha: 0.1))
        : (isDark ? AppTheme.darkSurface : AppTheme.inputBg);

    final fgColor = isSelected
        ? (style == AppFilterChipStyle.filled ? Colors.white : accentColor)
        : context.textMutedColor;

    final borderColor =
        isSelected ? accentColor.withValues(alpha: 0.3) : context.borderColor;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMd,
            vertical: AppTheme.spacingSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: effectiveFontSize + 2, color: fgColor),
                const SizedBox(width: AppTheme.spacingSm),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: effectiveFontSize,
                  fontWeight: fontWeight,
                  color: fgColor,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
