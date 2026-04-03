import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? ctaLabel;
  final IconData? ctaIcon;
  final VoidCallback? onCtaTap;
  final Color? iconColor;
  final bool bordered;
  final double iconSize;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.ctaLabel,
    this.ctaIcon,
    this.onCtaTap,
    this.iconColor,
    this.bordered = false,
    this.iconSize = 48,
  });

  @override
  Widget build(BuildContext context) {
    final mutedIconColor =
        iconColor ?? context.textMutedColor.withValues(alpha: 0.5);

    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingXl),
            decoration: BoxDecoration(
              color: mutedIconColor.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: iconSize, color: mutedIconColor),
          ),
          const SizedBox(height: AppTheme.spacingLg),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.textMutedColor,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppTheme.spacingXs),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 13,
                color: context.textMutedColor.withValues(alpha: 0.7),
              ),
            ),
          ],
          if (ctaLabel != null && onCtaTap != null) ...[
            const SizedBox(height: AppTheme.spacingLg),
            ElevatedButton.icon(
              onPressed: onCtaTap,
              icon: Icon(ctaIcon ?? Icons.add_rounded, size: 18),
              label: Text(ctaLabel!),
            ),
          ],
        ],
      ),
    );

    if (bordered) {
      return Container(
        padding: const EdgeInsets.all(AppTheme.spacingXxxl),
        decoration: BoxDecoration(
          border: Border.all(color: context.borderColor.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        child: content,
      );
    }

    return content;
  }
}
