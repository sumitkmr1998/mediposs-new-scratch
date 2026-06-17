import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import 'interactive_hover.dart';

class AppKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final int? count;
  final VoidCallback? onTap;
  final double? width;
  final double? progress;
  final String? trendText;
  final bool? trendIsUp;

  final bool compact;

  const AppKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.count,
    this.onTap,
    this.width,
    this.progress,
    this.trendText,
    this.trendIsUp,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgGradient = LinearGradient(
      colors: isDark
          ? [
              color.withValues(alpha: 0.08),
              color.withValues(alpha: 0.02),
            ]
          : [
              color.withValues(alpha: 0.04),
              color.withValues(alpha: 0.005),
            ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final card = Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: bgGradient,
        borderRadius: BorderRadius.circular(compact ? AppTheme.radiusCard : AppTheme.radiusDialog),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
          width: compact ? 1.0 : 1.5,
        ),
        boxShadow: AppTheme.subtleShadow,
      ),
      child: Stack(
        clipBehavior: Clip.antiAlias,
        children: [
          // Watermark Icon rotated in bottom-right corner
          Positioned(
            right: compact ? -8 : -12,
            bottom: compact ? -8 : -12,
            child: Transform.rotate(
              angle: 0.25, // ~15 degrees
              child: Icon(
                icon,
                size: compact ? 60 : 80,
                color: color.withValues(alpha: isDark ? 0.05 : 0.03),
              ),
            ),
          ),
          // Content Row
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppTheme.spacingMd : AppTheme.spacingXl,
              vertical: compact ? AppTheme.spacingSm : AppTheme.spacingMd,
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(compact ? AppTheme.spacingXs : AppTheme.spacingSm),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(compact ? AppTheme.radiusChip : AppTheme.radiusInput),
                  ),
                  child: Icon(icon, size: compact ? 18 : 22, color: color),
                ),
                SizedBox(width: compact ? AppTheme.spacingSm : AppTheme.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            value,
                            style: TextStyle(
                              fontSize: compact ? 18 : 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: compact ? -0.5 : -1,
                            ),
                          ),
                          if (trendText != null) ...[
                            SizedBox(width: compact ? 4 : 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: (trendIsUp ?? true)
                                    ? AppTheme.success.withValues(alpha: 0.1)
                                    : AppTheme.danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    (trendIsUp ?? true)
                                        ? Icons.trending_up_rounded
                                        : Icons.trending_down_rounded,
                                    size: 10,
                                    color: (trendIsUp ?? true)
                                        ? AppTheme.success
                                        : AppTheme.danger,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    trendText!,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: (trendIsUp ?? true)
                                          ? AppTheme.success
                                          : AppTheme.danger,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          fontSize: compact ? 8 : 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: compact ? 0.8 : 1.2,
                        ),
                      ),
                      if (subtitle != null && !compact) ...[
                        const SizedBox(height: AppTheme.spacingXs + 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spacingSm,
                            vertical: AppTheme.spacingXs,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(AppTheme.spacingXs + 2),
                          ),
                          child: Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (count != null) ...[
                  SizedBox(width: compact ? AppTheme.spacingXs : AppTheme.spacingSm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingSm,
                      vertical: AppTheme.spacingXs,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                    ),
                    child: Text(
                      '+$count',
                      style: TextStyle(
                        fontSize: compact ? 10 : 12,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Glow Progress Bar at bottom of card
          if (progress != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FractionallySizedBox(
                alignment: Alignment.bottomLeft,
                widthFactor: progress!.clamp(0.0, 1.0),
                child: Container(
                  height: compact ? 3 : 4,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(2),
                      bottomRight: Radius.circular(2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: compact ? 3 : 4,
                        offset: const Offset(0, -1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (onTap != null) {
      return InteractiveHover(
        borderRadius: BorderRadius.circular(compact ? AppTheme.radiusCard : AppTheme.radiusDialog),
        onTap: onTap!,
        child: card,
      );
    }

    return card;
  }
}
