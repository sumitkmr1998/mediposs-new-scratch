import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class AppSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final String? badge;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry? contentPadding;
  final bool expandable;
  final bool isExpanded;
  final VoidCallback? onToggle;

  const AppSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.accentColor,
    this.badge,
    this.trailing,
    required this.child,
    this.contentPadding,
    this.expandable = false,
    this.isExpanded = false,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: context.borderColor.withValues(alpha: 0.5)),
        boxShadow: AppTheme.subtleShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: expandable ? onToggle : null,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingXl,
                vertical: AppTheme.spacingMd,
              ),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.04),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppTheme.radiusCard),
                ),
                border: Border(
                  bottom: BorderSide(
                    color: accentColor.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppTheme.spacingSm - 2),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(AppTheme.spacingSm - 2),
                    ),
                    child: Icon(icon, size: 16, color: accentColor),
                  ),
                  const SizedBox(width: AppTheme.spacingSm),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: AppTheme.spacingSm - 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingSm,
                        vertical: AppTheme.spacingXs,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusChip),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (trailing != null) trailing!,
                  if (expandable) ...[
                    const SizedBox(width: AppTheme.spacingSm),
                    Icon(
                      isExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: accentColor.withValues(alpha: 0.6),
                      size: 20,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!expandable || isExpanded)
            Padding(
              padding:
                  contentPadding ?? const EdgeInsets.all(AppTheme.spacingMd),
              child: child,
            ),
        ],
      ),
    );
  }
}
