import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

/// A unified page layout that gives all list/report pages a consistent look.
///
/// Structure:
///  ┌─────────────────────────────────────────┐
///  │  AppBar: icon + title + subtitle        │
///  ├─────────────────────────────────────────┤
///  │  KPI Cards (auto-sizing grid)            │
///  ├─────────────────────────────────────────┤
///  │  Filter Chips + Search Bar (in card)    │
///  ├─────────────────────────────────────────┤
///  │  Data Table / List (in bordered card)   │
///  └─────────────────────────────────────────┘
class AppPageLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> kpiCards;
  final Widget? filterBar;
  final Widget? searchField;
  final Widget body;
  final Widget? floatingActionButton;
  final bool showKpiSection;
  final bool showFilterSection;

  const AppPageLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.kpiCards = const [],
    this.filterBar,
    this.searchField,
    required this.body,
    this.floatingActionButton,
    this.showKpiSection = true,
    this.showFilterSection = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
                Text(subtitle,
                    style:
                        TextStyle(fontSize: 12, color: context.textMutedColor)),
              ],
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Cards Section
            if (showKpiSection && kpiCards.isNotEmpty) ...[
              Text('OVERVIEW',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: context.textMutedColor)),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (ctx, constraints) {
                final cols = constraints.maxWidth > 1000
                    ? 4
                    : (constraints.maxWidth > 700 ? 2 : 1);
                const spacing = 16.0;
                final cardWidth =
                    (constraints.maxWidth - (cols - 1) * spacing) / cols;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: kpiCards
                      .map((card) => SizedBox(width: cardWidth, child: card))
                      .toList(),
                );
              }),
              const SizedBox(height: 24),
            ],

            // Filter + Search Section
            if (showFilterSection && (filterBar != null || searchField != null))
              _buildFilterSearchCard(context),

            if (showFilterSection && (filterBar != null || searchField != null))
              const SizedBox(height: 24),

            // Main Body (Table / List)
            body,

            const SizedBox(height: 24),
          ],
        ),
      ),
      floatingActionButton: floatingActionButton,
    );
  }

  Widget _buildFilterSearchCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: context.borderColor),
        boxShadow: AppTheme.subtleShadow,
      ),
      child: Row(
        children: [
          if (filterBar != null)
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: filterBar,
              ),
            ),
          if (filterBar != null && searchField != null)
            const SizedBox(width: 16),
          if (searchField != null) SizedBox(width: 260, child: searchField),
        ],
      ),
    );
  }
}

extension ThemeExtensionForAppPage on BuildContext {
  Color get _textMutedColor =>
      Theme.of(this).colorScheme.onSurface.withValues(alpha: 0.6);
  Color get _surfaceColor => Theme.of(this).colorScheme.surface;
  Color get _borderColor => Theme.of(this).dividerColor;
}
