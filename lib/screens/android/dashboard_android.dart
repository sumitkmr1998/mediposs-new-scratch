import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/providers/opd_provider.dart';
import '../../shared/models/medicine.dart' as model;
import '../../shared/models/appointment.dart';
import '../../theme/app_theme.dart';
import '../pos_screen.dart';
import '../warehouse_screen.dart';
import '../sales_history_screen.dart';
import '../settings_screen.dart';
import '../connection_screen.dart';
import '../../shared/services/sync_service.dart';
import '../../shared/widgets/app_kpi_card.dart';
import '../../shared/widgets/app_filter_chip.dart';

class DashboardAndroid extends StatelessWidget {
  const DashboardAndroid({super.key});

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final sales = context.watch<SalesProvider>();
    final opd = context.watch<OpdProvider>();
    final auth = context.read<AuthProvider>();
    final cs = Theme.of(context).colorScheme;
    final rangeLabel = _getRangeLabel(sales);

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          // Modern App Bar
          SliverAppBar(
            expandedHeight: 120,
            floating: true,
            pinned: true,
            backgroundColor: cs.surface,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.dashboard_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Dashboard',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              Consumer<WebSocketService>(
                builder: (context, wsvc, _) {
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: wsvc.connected
                              ? AppTheme.success.withValues(alpha: 0.1)
                              : AppTheme.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          wsvc.connected ? Icons.wifi : Icons.wifi_off,
                          color: wsvc.connected
                              ? AppTheme.success
                              : AppTheme.warning,
                          size: 20,
                        ),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ConnectionScreen()),
                      ),
                    ),
                  );
                },
              ),
              Container(
                margin: const EdgeInsets.only(right: 12),
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.logout_rounded,
                      color: AppTheme.danger,
                      size: 20,
                    ),
                  ),
                  onPressed: () => auth.logout(),
                ),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Section
                  _WelcomeSection(auth: auth, cs: cs),

                  const SizedBox(height: 24),

                  // Sentry Security Indicator
                  _SecurityStatusIndicator(cs: cs),

                  const SizedBox(height: 24),

                  // Date Filter
                  _DateFilterBar(sales: sales, cs: cs),

                  const SizedBox(height: 24),

                  // Primary Stats
                  _PrimaryStats(
                    sales: sales,
                    opd: opd,
                    inv: inv,
                    rangeLabel: rangeLabel,
                    cs: cs,
                  ),

                  const SizedBox(height: 24),

                  // Revenue Breakdown
                  _RevenueBreakdown(
                    sales: sales,
                    opd: opd,
                    rangeLabel: rangeLabel,
                    cs: cs,
                  ),

                  const SizedBox(height: 24),

                  // Quick Actions
                  _QuickActionsCard(cs: cs),

                  const SizedBox(height: 20),

                  // Inventory Alerts
                  if (inv.lowStockCount > 0) ...[
                    _LowStockCard(inv: inv, cs: cs),
                    const SizedBox(height: 24),
                  ],
                  if (inv.nearExpiryCount > 0) ...[
                    _NearExpiryCard(inv: inv, cs: cs),
                    const SizedBox(height: 24),
                  ],
                  if (inv.expiredCount > 0) ...[
                    _ExpiredCard(inv: inv, cs: cs),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeSection extends StatelessWidget {
  final AuthProvider auth;
  final ColorScheme cs;

  const _WelcomeSection({required this.auth, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.08),
            AppTheme.primaryLight.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  auth.currentUser?.name ?? 'User',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: AppTheme.primary,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateFilterBar extends StatelessWidget {
  final SalesProvider sales;
  final ColorScheme cs;

  const _DateFilterBar({required this.sales, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.08),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            AppFilterChip(
              label: 'Today',
              isSelected: sales.activeFilter == SalesFilter.today,
              onTap: () => sales.setFilter(SalesFilter.today),
              style: AppFilterChipStyle.filled,
            ),
            const SizedBox(width: 4),
            AppFilterChip(
              label: 'Yesterday',
              isSelected: sales.activeFilter == SalesFilter.yesterday,
              onTap: () => sales.setFilter(SalesFilter.yesterday),
              style: AppFilterChipStyle.filled,
            ),
            const SizedBox(width: 4),
            AppFilterChip(
              label: '7 Days',
              isSelected: sales.activeFilter == SalesFilter.last7Days,
              onTap: () => sales.setFilter(SalesFilter.last7Days),
              style: AppFilterChipStyle.filled,
            ),
            const SizedBox(width: 4),
            AppFilterChip(
              label: 'All',
              isSelected: sales.activeFilter == SalesFilter.allTime,
              onTap: () => sales.setFilter(SalesFilter.allTime),
              style: AppFilterChipStyle.filled,
            ),
            const SizedBox(width: 4),
            AppFilterChip(
              label: 'Custom',
              isSelected: sales.activeFilter == SalesFilter.custom,
              onTap: () async {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  builder: (ctx, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: Theme.of(context).colorScheme.copyWith(
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
              style: AppFilterChipStyle.filled,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryStats extends StatelessWidget {
  final SalesProvider sales;
  final OpdProvider opd;
  final InventoryProvider inv;
  final String rangeLabel;
  final ColorScheme cs;

  const _PrimaryStats({
    required this.sales,
    required this.opd,
    required this.inv,
    required this.rangeLabel,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final opdRev = opd.appointments
        .where((a) =>
            a.status == kStatusDone &&
            a.scheduledAt.year == now.year &&
            a.scheduledAt.month == now.month &&
            a.scheduledAt.day == now.day)
        .fold(0.0, (sum, a) => sum + (a.consultationFee));

    final productRev = sales.sales
        .where((s) =>
            s.createdAt.year == now.year &&
            s.createdAt.month == now.month &&
            s.createdAt.day == now.day)
        .fold(0.0, (sum, s) => sum + s.total);

    final totalToday = opdRev + productRev;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overview',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 1.1,
          children: [
            AppKpiCard(
              label: 'Today\'s Revenue',
              value: '₹${totalToday.toStringAsFixed(0)}',
              icon: Icons.trending_up_rounded,
              color: AppTheme.emerald,
            ),
            AppKpiCard(
              label: 'OPD Today',
              value: '${opd.todayQueue.length}',
              icon: Icons.people_alt_rounded,
              color: AppTheme.primary,
            ),
            AppKpiCard(
              label: 'Low Stock',
              value: '${inv.lowStockCount}',
              icon: Icons.warning_amber_rounded,
              color: AppTheme.warning,
              onTap: () => _showMedicineList(context, 'Low Stock',
                  inv.medicines.where((m) => m.isLowStock).toList()),
            ),
            AppKpiCard(
              label: 'Near Expiry',
              value: '${inv.nearExpiryCount}',
              icon: Icons.timer_rounded,
              color: AppTheme.orange,
              onTap: () => _showMedicineList(
                  context, 'Near Expiry', inv.nearExpiryMedicines),
            ),
            AppKpiCard(
              label: 'Expired',
              value: '${inv.expiredCount}',
              icon: Icons.event_busy_rounded,
              color: AppTheme.danger,
              onTap: () => _showMedicineList(
                  context, 'Expired Items', inv.expiredMedicines),
            ),
          ],
        ),
      ],
    );
  }

  void _showMedicineList(
      BuildContext context, String title, List<model.Medicine> meds) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.7,
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.withAlpha(100),
                    borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${meds.length} items',
                      style: TextStyle(
                          color: context.textMutedColor,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Expanded(
              child: meds.isEmpty
                  ? Center(
                      child: Text('No items found',
                          style: TextStyle(color: context.textMutedColor)))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: meds.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final m = meds[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(m.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${m.category} • ${m.storeStock} in stock',
                              style: TextStyle(
                                  fontSize: 12, color: context.textMutedColor)),
                          trailing: Icon(Icons.chevron_right,
                              color: context.textMutedColor, size: 20),
                          onTap: () {
                            Navigator.pop(ctx);
                            // We should show the detail or edit dialog
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevenueBreakdown extends StatelessWidget {
  final SalesProvider sales;
  final OpdProvider opd;
  final String rangeLabel;
  final ColorScheme cs;

  const _RevenueBreakdown({
    required this.sales,
    required this.opd,
    required this.rangeLabel,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Calculate breakdown
    double cash = 0, upi = 0, card = 0;

    // Product Sales
    for (final s in sales.sales) {
      if (s.createdAt.year == now.year &&
          s.createdAt.month == now.month &&
          s.createdAt.day == now.day) {
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
    }

    // OPD Revenue
    for (final a in opd.appointments) {
      if (a.status == kStatusDone &&
          a.scheduledAt.year == now.year &&
          a.scheduledAt.month == now.month &&
          a.scheduledAt.day == now.day) {
        if (a.paymentMethod == 'cash') {
          cash += a.consultationFee;
        } else if (a.paymentMethod == 'upi') {
          upi += a.consultationFee;
        } else if (a.paymentMethod == 'card') {
          card += a.consultationFee;
        }
      }
    }

    final total = cash + upi + card;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Revenue Breakdown',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const Spacer(),
            _TodayTotalBadge(total: total),
          ],
        ),
        const SizedBox(height: 14),

        // Visual Composition Bar
        if (total > 0) ...[
          _RevenueCompositionBar(
              cash: cash, upi: upi, card: card, total: total),
          const SizedBox(height: 16),
        ],

        Row(
          children: [
            Expanded(
              child: _BreakdownCard(
                title: 'Cash',
                value: '₹${cash.toStringAsFixed(0)}',
                icon: Icons.payments_rounded,
                color: AppTheme.emerald,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BreakdownCard(
                title: 'UPI',
                value: '₹${upi.toStringAsFixed(0)}',
                icon: Icons.qr_code_rounded,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BreakdownCard(
                title: 'Card',
                value: '₹${card.toStringAsFixed(0)}',
                icon: Icons.credit_card_rounded,
                color: AppTheme.accent,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TodayTotalBadge extends StatelessWidget {
  final double total;
  const _TodayTotalBadge({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.emerald, AppTheme.emeraldDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppTheme.emerald.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'TODAY: ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            '₹${total.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _BreakdownCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  final ColorScheme cs;

  const _QuickActionsCard({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.bolt_rounded,
                  color: AppTheme.primary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ActionChip(
                icon: Icons.point_of_sale_rounded,
                label: 'New Sale',
                color: AppTheme.primary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PosScreen()),
                ),
              ),
              _ActionChip(
                icon: Icons.warehouse_rounded,
                label: 'Warehouse',
                color: AppTheme.violet,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WarehouseScreen()),
                ),
              ),
              _ActionChip(
                icon: Icons.receipt_long_rounded,
                label: 'Sales',
                color: AppTheme.accent,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
                ),
              ),
              _ActionChip(
                icon: Icons.settings_rounded,
                label: 'Settings',
                color: cs.onSurface.withValues(alpha: 0.5),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LowStockCard extends StatelessWidget {
  final InventoryProvider inv;
  final ColorScheme cs;

  const _LowStockCard({required this.inv, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.warning.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: AppTheme.warning,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Low Stock Alerts',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${inv.lowStockCount}',
                  style: TextStyle(
                    color: AppTheme.danger,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...inv.medicines
              .where((m) => m.isLowStock)
              .take(5)
              .map((m) => _LowStockItem(medicine: m)),
        ],
      ),
    );
  }
}

class _LowStockItem extends StatelessWidget {
  final dynamic medicine;

  const _LowStockItem({required this.medicine});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.warning.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medicine.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Store: ${medicine.storeStock} | Main: ${medicine.mainStock}',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'LOW',
              style: TextStyle(
                color: AppTheme.danger,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NearExpiryCard extends StatelessWidget {
  final InventoryProvider inv;
  final ColorScheme cs;

  const _NearExpiryCard({required this.inv, required this.cs});

  @override
  Widget build(BuildContext context) {
    if (inv.nearExpiryCount == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.orange.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppTheme.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.timer_rounded,
                  color: AppTheme.orange,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Near Expiry Alerts',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${inv.nearExpiryCount}',
                  style: const TextStyle(
                    color: AppTheme.amberDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...inv.nearExpiryMedicines
              .take(3)
              .map((m) => _ExpiryItem(medicine: m, isExpired: false)),
        ],
      ),
    );
  }
}

class _ExpiredCard extends StatelessWidget {
  final InventoryProvider inv;
  final ColorScheme cs;

  const _ExpiredCard({required this.inv, required this.cs});

  @override
  Widget build(BuildContext context) {
    if (inv.expiredCount == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.danger.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.event_busy_rounded,
                  color: AppTheme.danger,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Expired Items',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${inv.expiredCount}',
                  style: TextStyle(
                    color: AppTheme.danger,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...inv.expiredMedicines
              .take(3)
              .map((m) => _ExpiryItem(medicine: m, isExpired: true)),
        ],
      ),
    );
  }
}

class _ExpiryItem extends StatelessWidget {
  final dynamic medicine;
  final bool isExpired;

  const _ExpiryItem({required this.medicine, required this.isExpired});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = isExpired ? AppTheme.danger : AppTheme.orange;

    // Get the earliest problematic date
    final now = DateTime.now();
    DateTime? displayDate;
    if (isExpired) {
      displayDate = medicine.batches
          .firstWhere((b) => b.expiryDate.isBefore(now))
          .expiryDate;
    } else {
      final threshold = now.add(const Duration(days: 90));
      displayDate = medicine.batches
          .firstWhere((b) =>
              b.expiryDate.isAfter(now) && b.expiryDate.isBefore(threshold))
          .expiryDate;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medicine.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Exp: ${displayDate!.day}/${displayDate.month}/${displayDate.year}',
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isExpired ? 'EXPIRED' : 'NEAR',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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

class _SecurityStatusIndicator extends StatelessWidget {
  final ColorScheme cs;
  const _SecurityStatusIndicator({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.shield_rounded, color: Colors.white, size: 12),
          ),
          const SizedBox(width: 10),
          Text(
            'SENTRY ACTIVE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppTheme.primary,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            'Anti-Backdate Protection Enabled',
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.4),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueCompositionBar extends StatelessWidget {
  final double cash;
  final double upi;
  final double card;
  final double total;

  const _RevenueCompositionBar({
    required this.cash,
    required this.upi,
    required this.card,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 8,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: Colors.grey.withValues(alpha: 0.1),
          ),
          child: Row(
            children: [
              if (cash > 0)
                Expanded(
                  flex: (cash / total * 100).round(),
                  child: Container(color: AppTheme.emerald),
                ),
              if (upi > 0)
                Expanded(
                  flex: (upi / total * 100).round(),
                  child: Container(color: AppTheme.primary),
                ),
              if (card > 0)
                Expanded(
                  flex: (card / total * 100).round(),
                  child: Container(color: AppTheme.accent),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _CompLabel(
                label: 'CASH', color: AppTheme.emerald, pct: cash / total),
            _CompLabel(label: 'UPI', color: AppTheme.primary, pct: upi / total),
            _CompLabel(
                label: 'CARD', color: AppTheme.accent, pct: card / total),
          ],
        ),
      ],
    );
  }
}

class _CompLabel extends StatelessWidget {
  final String label;
  final Color color;
  final double pct;
  const _CompLabel(
      {required this.label, required this.color, required this.pct});

  @override
  Widget build(BuildContext context) {
    if (pct == 0) return const SizedBox.shrink();
    return Row(
      children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(
          '$label ${(pct * 100).toStringAsFixed(0)}%',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.4)),
        ),
      ],
    );
  }
}
