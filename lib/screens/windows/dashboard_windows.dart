import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../theme/app_theme.dart';
import '../pos_screen.dart';
import '../warehouse_screen.dart';
import '../sales_history_screen.dart';
import '../settings_screen.dart';

class DashboardWindows extends StatelessWidget {
  const DashboardWindows({super.key});

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final sales = context.watch<SalesProvider>();
    final auth = context.read<AuthProvider>();
    final cs = Theme.of(context).colorScheme;
    final rangeLabel = _getRangeLabel(sales);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => auth.logout(),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome back, ${auth.currentUser?.name ?? 'User'}! 👋',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    )),
            const SizedBox(height: 4),
            Text('Here\'s your store overview',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: context.textMutedColor)),
            const SizedBox(height: 16),

            // Global Date Filter Bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'Today',
                    isSelected: sales.activeFilter == SalesFilter.today,
                    onSelected: () => sales.setFilter(SalesFilter.today),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Yesterday',
                    isSelected: sales.activeFilter == SalesFilter.yesterday,
                    onSelected: () => sales.setFilter(SalesFilter.yesterday),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Last 7 Days',
                    isSelected: sales.activeFilter == SalesFilter.last7Days,
                    onSelected: () => sales.setFilter(SalesFilter.last7Days),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'All Time',
                    isSelected: sales.activeFilter == SalesFilter.allTime,
                    onSelected: () => sales.setFilter(SalesFilter.allTime),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Custom',
                    isSelected: sales.activeFilter == SalesFilter.custom,
                    onSelected: () async {
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        builder: (ctx, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme:
                                  Theme.of(context).colorScheme.copyWith(
                                        primary: AppTheme.primary,
                                        onPrimary: Colors.white,
                                      ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (range != null) {
                        sales.setFilter(SalesFilter.custom, range: range);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // KPI Grid
            LayoutBuilder(builder: (ctx, constraints) {
              final cols = constraints.maxWidth > 900
                  ? 3
                  : (constraints.maxWidth > 600 ? 2 : 1);
              final spacing = 16.0;
              final cardWidth =
                  (constraints.maxWidth - (cols - 1) * spacing) / cols;
              final rangeLabel = _getRangeLabel(sales);
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  _KpiCard(
                    label: "$rangeLabel Revenue",
                    value:
                        '₹${sales.sales.fold(0.0, (sum, s) => sum + s.total).toStringAsFixed(0)}',
                    icon: Icons.currency_rupee,
                    color: AppTheme.success,
                    width: (constraints.maxWidth - (cols - 1) * 16) / cols,
                  ),
                  _KpiCard(
                    label: '$rangeLabel Sales',
                    value: '${sales.sales.length}',
                    icon: Icons.receipt_long,
                    color: AppTheme.primary,
                    width: (constraints.maxWidth - (cols - 1) * 16) / cols,
                  ),
                  _KpiCard(
                    label: 'All-time Revenue',
                    value:
                        '₹${(sales.totalRevenue / 1000).toStringAsFixed(1)}K',
                    icon: Icons.trending_up,
                    color: AppTheme.primaryLight,
                    width: (constraints.maxWidth - (cols - 1) * 16) / cols,
                  ),
                  _KpiCard(
                    label: 'Low Stock Items',
                    value: '${inv.lowStockCount}',
                    icon: Icons.warning_amber,
                    color: AppTheme.warning,
                    width: (constraints.maxWidth - (cols - 1) * 16) / cols,
                  ),
                  _KpiCard(
                    label: 'Total Products',
                    value: '${inv.medicines.length}',
                    icon: Icons.medication,
                    color: AppTheme.accent,
                    width: (constraints.maxWidth - (cols - 1) * 16) / cols,
                  ),
                  _KpiCard(
                    label: 'Store Stock Value',
                    value:
                        '₹${(inv.totalInventoryValue / 1000).toStringAsFixed(1)}K',
                    icon: Icons.warehouse,
                    color: const Color(0xFF7C3AED),
                    width: cardWidth,
                  ),
                ],
              );
            }),

            const SizedBox(height: 32),

            // Revenue Breakdown
            Text('$rangeLabel Revenue Breakdown',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (ctx, constraints) {
              final width = constraints.maxWidth > 500
                  ? (constraints.maxWidth - 32) / 3
                  : constraints.maxWidth;

              // Calculate breakdown from currently filtered sales
              double cash = 0, upi = 0, card = 0;
              for (final s in sales.sales) {
                if (s.paymentMethod == 'mixed') {
                  cash += s.cashAmount;
                  upi += s.upiAmount;
                  card += s.cardAmount;
                } else if (s.paymentMethod == 'cash') {
                  cash += s.total;
                } else if (s.paymentMethod == 'upi') {
                  upi += s.total;
                } else if (s.paymentMethod == 'card') {
                  card += s.total;
                }
              }

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _KpiCard(
                    label: "Cash",
                    value: '₹${cash.toStringAsFixed(0)}',
                    icon: Icons.money,
                    color: AppTheme.success,
                    width: width,
                  ),
                  _KpiCard(
                    label: "UPI",
                    value: '₹${upi.toStringAsFixed(0)}',
                    icon: Icons.qr_code_scanner,
                    color: AppTheme.primary,
                    width: width,
                  ),
                  _KpiCard(
                    label: "Card",
                    value: '₹${card.toStringAsFixed(0)}',
                    icon: Icons.credit_card,
                    color: AppTheme.warning,
                    width: width,
                  ),
                ],
              );
            }),

            const SizedBox(height: 32),

            // Quick Actions
            Text('Quick Actions',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _QuickActions(),

            if (inv.lowStockCount > 0) ...[
              const SizedBox(height: 32),
              Text('⚠️ Low Stock Alerts',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.warning,
                      )),
              const SizedBox(height: 12),
              ...inv.medicines
                  .where((m) => m.isLowStock)
                  .take(5)
                  .map((m) => _LowStockTile(medicine: m)),
            ],
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final double width;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 16),
              Text(value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: color,
                      )),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _ActionButton(
          label: 'New Sale',
          icon: Icons.point_of_sale,
          color: AppTheme.primary,
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const PosScreen())),
        ),
        _ActionButton(
          label: 'Warehouse',
          icon: Icons.warehouse,
          color: const Color(0xFF7C3AED),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const WarehouseScreen())),
        ),
        _ActionButton(
          label: 'Sales',
          icon: Icons.receipt_long,
          color: AppTheme.accent,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SalesHistoryScreen())),
        ),
        _ActionButton(
          label: 'Settings',
          icon: Icons.settings,
          color: context.textMutedColor,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _LowStockTile extends StatelessWidget {
  final dynamic medicine;
  const _LowStockTile({required this.medicine});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.warning.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.warning_amber,
              color: AppTheme.warning, size: 20),
        ),
        title: Text(medicine.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle:
            Text('Store: ${medicine.storeStock} | Main: ${medicine.mainStock}'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.danger.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('LOW',
              style: TextStyle(
                  color: AppTheme.danger,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

String _getRangeLabel(SalesProvider sales) {
  switch (sales.activeFilter) {
    case SalesFilter.today:
      return "Today's";
    case SalesFilter.yesterday:
      return "Yesterday's";
    case SalesFilter.last7Days:
      return "7 Days'";
    case SalesFilter.allTime:
      return "All-time";
    case SalesFilter.custom:
      return "Custom";
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : context.textMutedColor,
          )),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: AppTheme.primary,
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? AppTheme.primary : context.borderColor,
        ),
      ),
      showCheckmark: false,
    );
  }
}
