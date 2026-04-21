import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/providers/opd_provider.dart';
import '../../shared/models/medicine.dart' as model;
import '../../theme/app_theme.dart';
import 'pos_android.dart';
import 'warehouse_android.dart';
import 'sales_history_android.dart';
import 'settings_android.dart';
import 'user_management_android.dart';
import '../connection_screen.dart';
import 'opd/opd_queue_android.dart';
import 'opd/opd_report_android.dart';
import '../../shared/services/sync_service.dart';
import '../../shared/widgets/app_kpi_card.dart';
import '../../shared/widgets/app_filter_chip.dart';
import '../../shared/models/appointment.dart';
import '../../shared/models/medicine.dart' as model;

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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.grid_view_rounded,
                      color: Colors.white,
                      size: 20,
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
                  return IconButton(
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
                        color: wsvc.connected ? AppTheme.success : AppTheme.warning,
                        size: 20,
                      ),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ConnectionScreen()),
                    ),
                  );
                },
              ),
              IconButton(
                padding: const EdgeInsets.only(right: 12),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.logout_rounded, color: AppTheme.danger, size: 20),
                ),
                onPressed: () => auth.logout(),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _WelcomeSection(auth: auth, cs: cs),
                  const SizedBox(height: 24),
                  _SecurityStatusIndicator(cs: cs),
                  const SizedBox(height: 24),
                  _DateFilterBar(sales: sales, cs: cs),
                  const SizedBox(height: 24),
                  _PrimaryStats(
                    sales: sales,
                    opd: opd,
                    inv: inv,
                    rangeLabel: rangeLabel,
                  ),
                  const SizedBox(height: 24),
                  _FinancialPerformance(sales: sales, opd: opd),
                  const SizedBox(height: 24),
                  _QuickActionsCard(),
                  const SizedBox(height: 24),
                  _InventoryAlertsSection(inv: inv, cs: cs),
                  const SizedBox(height: 32),
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
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.6)),
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
              gradient: LinearGradient(
                colors: [AppTheme.primary.withValues(alpha: 0.2), AppTheme.primary.withValues(alpha: 0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
            ),
            child: const Icon(Icons.face_rounded, color: AppTheme.primary, size: 28),
          ),
        ],
      ),
    );
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
            decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
            child: const Icon(Icons.shield_rounded, color: Colors.white, size: 12),
          ),
          const SizedBox(width: 10),
          const Text(
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
            'Anti-Backdate Protection Active',
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

class _DateFilterBar extends StatelessWidget {
  final SalesProvider sales;
  final ColorScheme cs;

  const _DateFilterBar({required this.sales, required this.cs});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _CompactFilterChip(
            label: 'Today',
            isSelected: sales.activeFilter == SalesFilter.today,
            onTap: () {
              sales.setFilter(SalesFilter.today);
              context.read<OpdProvider>().setFilter(OpdFilter.today);
            },
          ),
          const SizedBox(width: 8),
          _CompactFilterChip(
            label: 'Yesterday',
            isSelected: sales.activeFilter == SalesFilter.yesterday,
            onTap: () {
              sales.setFilter(SalesFilter.yesterday);
              context.read<OpdProvider>().setFilter(OpdFilter.yesterday);
            },
          ),
          const SizedBox(width: 8),
          _CompactFilterChip(
            label: '7 Days',
            isSelected: sales.activeFilter == SalesFilter.last7Days,
            onTap: () {
              sales.setFilter(SalesFilter.last7Days);
              context.read<OpdProvider>().setFilter(OpdFilter.last7Days);
            },
          ),
          const SizedBox(width: 8),
          _CompactFilterChip(
            label: 'All Time',
            isSelected: sales.activeFilter == SalesFilter.allTime,
            onTap: () {
              sales.setFilter(SalesFilter.allTime);
              context.read<OpdProvider>().setFilter(OpdFilter.allTime);
            },
          ),
        ],
      ),
    );
  }
}

class _CompactFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CompactFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.primary.withValues(alpha: 0.2)),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.primary,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
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

  const _PrimaryStats({
    required this.sales,
    required this.opd,
    required this.inv,
    required this.rangeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final double totalRevenue = sales.filteredRevenue + opd.filteredCollectedRevenue;
    final String labelSuffix = _getLabelSuffix(sales.activeFilter);

    return Column(
      children: [
        AppKpiCard(
          label: 'Revenue ($labelSuffix)',
          value: '₹${totalRevenue.toStringAsFixed(0)}',
          icon: Icons.trending_up_rounded,
          color: AppTheme.emerald,
          subtitle: 'Combined Product Sales & OPD Fees',
          width: double.infinity,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: AppKpiCard(
                label: 'Sales ($labelSuffix)',
                value: '${sales.filteredSalesCount}',
                icon: Icons.shopping_bag_rounded,
                color: AppTheme.teal,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: AppKpiCard(
                label: 'OPD ($labelSuffix)',
                value: '${opd.filteredPatientCount}',
                icon: Icons.medical_services_rounded,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getLabelSuffix(SalesFilter filter) {
    switch (filter) {
      case SalesFilter.today: return 'Today';
      case SalesFilter.yesterday: return 'Yesterday';
      case SalesFilter.last7Days: return '7 Days';
      case SalesFilter.allTime: return 'All Time';
      case SalesFilter.custom: return 'Custom';
    }
  }
}

class _FinancialPerformance extends StatelessWidget {
  final SalesProvider sales;
  final OpdProvider opd;

  const _FinancialPerformance({required this.sales, required this.opd});

  @override
  Widget build(BuildContext context) {
    final double productSales = sales.filteredRevenue;
    final double opdRev = opd.filteredCollectedRevenue;
    final double total = productSales + opdRev;

    final double cash = sales.filteredCashRevenue + opd.filteredCashRevenue;
    final double upi = sales.filteredUpiRevenue + opd.filteredUpiRevenue;
    final double card = sales.filteredCardRevenue + opd.filteredCardRevenue;

    final String labelSuffix = _getLabelSuffix(sales.activeFilter);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.borderColor.withValues(alpha: 0.5)),
        boxShadow: AppTheme.subtleShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RevenueTotalBadge(total: total),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FINANCIAL PERFORMANCE',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: AppTheme.primary),
                    ),
                    Text('$labelSuffix performance metrics',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text('REVENUE SOURCE',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: context.textMutedColor)),
          const SizedBox(height: 16),
          _SourceRow(label: 'Product Sales', amount: productSales, total: total > 0 ? total : 1, color: AppTheme.emerald),
          const SizedBox(height: 16),
          _SourceRow(label: 'OPD Consults', amount: opdRev, total: total > 0 ? total : 1, color: AppTheme.primary),
          const SizedBox(height: 32),
          Text('PAYMENT MODES',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: context.textMutedColor)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _BreakdownMiniCard(label: 'Cash', value: cash, color: AppTheme.emerald, icon: Icons.payments_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _BreakdownMiniCard(label: 'UPI', value: upi, color: AppTheme.primary, icon: Icons.qr_code_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _BreakdownMiniCard(label: 'Card', value: card, color: AppTheme.purple, icon: Icons.credit_card_rounded)),
            ],
          ),
        ],
      ),
    );
  }

  String _getLabelSuffix(SalesFilter filter) {
    switch (filter) {
      case SalesFilter.today: return 'Today';
      case SalesFilter.yesterday: return 'Yesterday';
      case SalesFilter.last7Days: return '7 Days';
      case SalesFilter.allTime: return 'All Time';
      case SalesFilter.custom: return 'Custom';
    }
  }
}

class _SourceRow extends StatelessWidget {
  final String label;
  final double amount;
  final double total;
  final Color color;

  const _SourceRow({required this.label, required this.amount, required this.total, required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = (amount / total).clamp(0.0, 1.0);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text('₹${amount.toStringAsFixed(0)}',
                style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: color.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _BreakdownMiniCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final IconData icon;

  const _BreakdownMiniCard({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text('₹${value.toStringAsFixed(0)}',
              style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 13)),
          Text(label.toUpperCase(),
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: color.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}

class _RevenueTotalBadge extends StatelessWidget {
  final double total;
  const _RevenueTotalBadge({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppTheme.emerald, AppTheme.emeraldDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppTheme.emerald.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          const Text('TOTAL', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
          Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  void _handleAction(BuildContext context, String label) {
    Widget? target;
    switch (label) {
      case 'New POS':
        target = PosAndroid();
        break;
      case 'Add Patient':
        target = OpdQueueAndroid();
        break;
      case 'Stock List':
        target = WarehouseAndroid();
        break;
      case 'Reports':
        target = SalesHistoryAndroid();
        break;
      case 'Staff':
        target = UserManagementAndroid();
        break;
      case 'Settings':
        target = SettingsAndroid();
        break;
    }

    if (target != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => target!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 16),
          child: Text('QUICK ACTIONS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: AppTheme.primary)),
        ),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            _QuickActionItem(icon: Icons.add_shopping_cart_rounded, label: 'New POS', color: AppTheme.primary, onTap: () => _handleAction(context, 'New POS')),
            _QuickActionItem(icon: Icons.person_add_alt_rounded, label: 'Add Patient', color: AppTheme.teal, onTap: () => _handleAction(context, 'Add Patient')),
            _QuickActionItem(icon: Icons.inventory_2_rounded, label: 'Stock List', color: AppTheme.orange, onTap: () => _handleAction(context, 'Stock List')),
            _QuickActionItem(icon: Icons.analytics_rounded, label: 'Reports', color: AppTheme.purple, onTap: () => _handleAction(context, 'Reports')),
            _QuickActionItem(icon: Icons.security_rounded, label: 'Staff', color: AppTheme.indigo, onTap: () => _handleAction(context, 'Staff')),
            _QuickActionItem(icon: Icons.settings_rounded, label: 'Settings', color: Colors.blueGrey, onTap: () => _handleAction(context, 'Settings')),
          ],
        ),
      ],
    );
  }
}

class _QuickActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionItem({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.borderColor.withValues(alpha: 0.5)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 22)),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _InventoryAlertsSection extends StatelessWidget {
  final InventoryProvider inv;
  final ColorScheme cs;

  const _InventoryAlertsSection({required this.inv, required this.cs});

  @override
  Widget build(BuildContext context) {
    if (inv.lowStockCount == 0 && inv.nearExpiryCount == 0 && inv.expiredCount == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 16),
          child: Text('INVENTORY HEALTH', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: AppTheme.primary)),
        ),
        _ExpandableHealthCard(
          label: 'Low Stock',
          count: inv.lowStockCount,
          color: AppTheme.warning,
          icon: Icons.warning_amber_rounded,
          items: inv.medicines.where((m) => m.isLowStock).toList(),
          subtitleBuilder: (m) => 'Store: ${m.storeStock} | Main: ${m.mainStock}',
        ),
        const SizedBox(height: 12),
        _ExpandableHealthCard(
          label: 'Near Expiry',
          count: inv.nearExpiryCount,
          color: AppTheme.orange,
          icon: Icons.timer_rounded,
          items: inv.nearExpiryMedicines,
          subtitleBuilder: (m) {
             final now = DateTime.now();
             final threshold = now.add(const Duration(days: 90));
             final b = m.batches.firstWhere((b) => b.expiryDate.isAfter(now) && b.expiryDate.isBefore(threshold));
             return 'Exp: ${b.expiryDate.day}/${b.expiryDate.month}/${b.expiryDate.year}';
          },
        ),
        const SizedBox(height: 12),
        _ExpandableHealthCard(
          label: 'Expired Items',
          count: inv.expiredCount,
          color: AppTheme.danger,
          icon: Icons.event_busy_rounded,
          items: inv.expiredMedicines,
          subtitleBuilder: (m) {
             final now = DateTime.now();
             final b = m.batches.firstWhere((b) => b.expiryDate.isBefore(now));
             return 'Expired: ${b.expiryDate.day}/${b.expiryDate.month}/${b.expiryDate.year}';
          },
        ),
      ],
    );
  }
}

class _ExpandableHealthCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  final List<model.Medicine> items;
  final String Function(model.Medicine) subtitleBuilder;

  const _ExpandableHealthCard({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
    required this.items,
    required this.subtitleBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
            child: Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: items.take(10).map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(subtitleBuilder(m), style: TextStyle(color: context.textMutedColor, fontSize: 11)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                    ],
                  ),
                )).toList(),
              ),
            ),
            if (items.length > 10)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('And ${items.length - 10} more...', style: TextStyle(fontSize: 11, color: context.textMutedColor, fontStyle: FontStyle.italic)),
              ),
          ],
        ),
      ),
    );
  }
}

String _getRangeLabel(SalesProvider sales) {
  switch (sales.activeFilter) {
    case SalesFilter.today: return "Today's";
    case SalesFilter.yesterday: return "Yesterday's";
    case SalesFilter.last7Days: return "7 Days'";
    case SalesFilter.allTime: return "All-time";
    case SalesFilter.custom: return "Custom";
  }
}
