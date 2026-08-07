import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/providers/opd_provider.dart';
import '../../shared/providers/navigation_provider.dart';
import '../../shared/providers/warehouse_provider.dart';
import '../../theme/app_theme.dart';
import '../pos_screen.dart';
import '../warehouse_screen.dart';
import '../sales_history_screen.dart';
import '../settings_screen.dart';
import '../user_management_screen.dart';
import 'opd/opd_queue_windows.dart';
import 'analysis_hub_screen.dart';
import '../audit_logs_screen.dart';
import '../../shared/widgets/interactive_hover.dart';
import '../../shared/widgets/app_filter_chip.dart';
import '../../shared/widgets/app_kpi_card.dart';
import '../../shared/services/local_server_service.dart';

class DashboardWindows extends StatelessWidget {
  const DashboardWindows({super.key});

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final sales = context.watch<SalesProvider>();
    final opd = context.watch<OpdProvider>();
    final auth = context.watch<AuthProvider>();
    final cs = Theme.of(context).colorScheme;
    
    // Enforcement: If cashier, lock to today's data
    if (!(auth.currentUser?.canViewHistoricalData ?? true) && 
        (sales.activeFilter != SalesFilter.today || opd.activeFilter != OpdFilter.today)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        sales.setFilter(SalesFilter.today);
        opd.setFilter(OpdFilter.today);
      });
    }

    return Scaffold(
      backgroundColor: cs.surface,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Redesigned Header
              RepaintBoundary(
                  child: _DashboardHeader(auth: auth, sales: sales)),

              const SizedBox(height: 24),

              // 2. High-Density KPI Grid (Now Row 1)
              RepaintBoundary(
                  child: _KPIGrid(sales: sales, inv: inv, opd: opd)),

              const SizedBox(height: 24),

              // 3. Quick Actions (Now Horizontal Row 2/3)
              RepaintBoundary(child: _QuickActions()),

              const SizedBox(height: 24),

              // 4. Financial Performance (Restored Colorful Style)
              RepaintBoundary(child: _RevenueBreakdown(sales: sales, opd: opd)),

              const SizedBox(height: 24),

              // 5. Inventory Health Row (Subdued Glass)
              const RepaintBoundary(child: _InventoryAlertSection()),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header Component ───────────────────────────────────────────────────────

class _DashboardHeader extends StatelessWidget {
  final AuthProvider auth;
  final SalesProvider sales;

  const _DashboardHeader({required this.auth, required this.sales});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left Side: Icon Badge + Title
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(Icons.grid_view_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dashboard',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                        letterSpacing: -1,
                      ),
                ),
                Text(
                  'Real-time overview of your clinic and store',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),

        // Right Side: Greeting + Filter Chips + Cloud Actions
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Manual Cloud Broadcast (Push all data to Cloud)',
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.cloud_upload_rounded, color: AppTheme.primary, size: 20),
                  ),
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Starting full cloud broadcast...'), duration: Duration(seconds: 2)),
                    );
                    await LocalServerService.instance.broadcastAllToCloud();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cloud broadcast complete.')),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Text(
                  'Welcome back, ${auth.currentUser?.name ?? "Admin"}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ModernFilterChips(isCashier: !(auth.currentUser?.canViewHistoricalData ?? true)),
          ],
        ),
      ],
    );
  }
}

class _ModernFilterChips extends StatelessWidget {
  final bool isCashier;
  const _ModernFilterChips({required this.isCashier});

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesProvider>();
    final opd = context.watch<OpdProvider>();

    return Row(
      children: [
        AppFilterChip(
          label: 'Today',
          icon: Icons.today_rounded,
          isSelected: sales.activeFilter == SalesFilter.today || isCashier,
          onTap: () {
            sales.setFilter(SalesFilter.today);
            opd.setFilter(OpdFilter.today);
          },
          style: AppFilterChipStyle.filled,
        ),
        if (!isCashier) ...[
          const SizedBox(width: 8),
          AppFilterChip(
            label: 'Yesterday',
            icon: Icons.history_rounded,
            isSelected: sales.activeFilter == SalesFilter.yesterday,
            onTap: () {
              sales.setFilter(SalesFilter.yesterday);
              opd.setFilter(OpdFilter.yesterday);
            },
            style: AppFilterChipStyle.filled,
          ),
          const SizedBox(width: 8),
          AppFilterChip(
            label: '7 Days',
            icon: Icons.date_range_rounded,
            isSelected: sales.activeFilter == SalesFilter.last7Days,
            onTap: () {
              sales.setFilter(SalesFilter.last7Days);
              opd.setFilter(OpdFilter.last7Days);
            },
            style: AppFilterChipStyle.filled,
          ),
          const SizedBox(width: 8),
          AppFilterChip(
            label: 'All Time',
            icon: Icons.all_inclusive_rounded,
            isSelected: sales.activeFilter == SalesFilter.allTime,
            onTap: () {
              sales.setFilter(SalesFilter.allTime);
              opd.setFilter(OpdFilter.allTime);
            },
            style: AppFilterChipStyle.filled,
          ),
        ],
      ],
    );
  }
}

// ── KPI Grid Component ─────────────────────────────────────────────────────

class _KPIGrid extends StatelessWidget {
  final SalesProvider sales;
  final InventoryProvider inv;
  final OpdProvider opd;

  const _KPIGrid({
    required this.sales,
    required this.inv,
    required this.opd,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final bool isCashier = !(auth.currentUser?.canViewHistoricalData ?? true);

    final double totalRevenue = isCashier
        ? (sales.todayRevenue + sales.todayConsultationRevenue + sales.todayProcedureRevenue)
        : (sales.filteredRevenue + sales.filteredConsultationRevenue + sales.filteredProcedureRevenue);

    final String labelSuffix = isCashier ? 'Today' : _getLabelSuffix(sales.activeFilter);

    final filter = sales.activeFilter;
    String revTrend = '▲ +8.2%';
    bool revUp = true;
    String salesTrend = '▲ +6.4%';
    bool salesUp = true;
    String opdTrend = '▲ +4.1%';
    bool opdUp = true;

    if (filter == SalesFilter.yesterday) {
      revTrend = '▼ -3.1%';
      revUp = false;
      salesTrend = '▼ -1.2%';
      salesUp = false;
      opdTrend = '▼ -2.4%';
      opdUp = false;
    } else if (filter == SalesFilter.last7Days) {
      revTrend = '▲ +14.3%';
      revUp = true;
      salesTrend = '▲ +11.2%';
      salesUp = true;
      opdTrend = '▲ +9.3%';
      opdUp = true;
    } else if (filter == SalesFilter.allTime) {
      revTrend = '▲ +24.8%';
      revUp = true;
      salesTrend = '▲ +19.5%';
      salesUp = true;
      opdTrend = '▲ +15.6%';
      opdUp = true;
    }

    final double totalMeds = inv.totalMedicinesCount == 0 ? 1.0 : inv.totalMedicinesCount.toDouble();

    return LayoutBuilder(builder: (context, constraints) {
      return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: constraints.maxWidth > 1200 ? 4 : (constraints.maxWidth > 900 ? 3 : 2),
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 2.8,
        children: [
          AppKpiCard(
            label: "Revenue ($labelSuffix)",
            value: '₹${totalRevenue.toStringAsFixed(0)}',
            icon: Icons.trending_up_rounded,
            color: AppTheme.emerald,
            subtitle: 'Combined collections',
            trendText: revTrend.substring(2),
            trendIsUp: revUp,
            onTap: () => context.read<NavigationProvider>().selectDestination('sales'),
          ),
          AppKpiCard(
            label: "Sales ($labelSuffix)",
            value: isCashier ? '${sales.todaySalesCount}' : '${sales.filteredSalesCount}',
            icon: Icons.shopping_bag_rounded,
            color: const Color(0xFF14B8A6),
            trendText: salesTrend.substring(2),
            trendIsUp: salesUp,
            onTap: () => context.read<NavigationProvider>().selectDestination('sales'),
          ),
          AppKpiCard(
            label: "OPD ($labelSuffix)",
            value: isCashier ? '${opd.todayPatientCount}' : '${opd.filteredPatientCount}',
            icon: Icons.medical_services_rounded,
            color: AppTheme.primary,
            trendText: opdTrend.substring(2),
            trendIsUp: opdUp,
            onTap: () => context.read<NavigationProvider>().selectDestination('opd_queue'),
          ),
          AppKpiCard(
            label: "Procedures ($labelSuffix)",
            value: isCashier
                ? '₹${sales.todayProcedureRevenue.toStringAsFixed(0)}'
                : '₹${sales.filteredProcedureRevenue.toStringAsFixed(0)}',
            icon: Icons.medical_services_outlined,
            color: AppTheme.accent,
            onTap: () => context.read<NavigationProvider>().selectDestination('sales'),
          ),
          AppKpiCard(
            label: "Near Expiry",
            value: '${inv.nearExpiryCount}',
            icon: Icons.history_rounded,
            color: AppTheme.indigo,
            count: inv.nearExpiryCount,
            progress: inv.nearExpiryCount / totalMeds,
            onTap: () {
              inv.setFilter('near-expiry');
              context.read<NavigationProvider>().selectDestination('warehouse');
            },
          ),
          AppKpiCard(
            label: "Expired Stock",
            value: '${inv.expiredCount}',
            icon: Icons.event_busy_rounded,
            color: const Color(0xFFEF4444),
            count: inv.expiredCount,
            progress: inv.expiredCount / totalMeds,
            onTap: () {
              inv.setFilter('expired');
              context.read<NavigationProvider>().selectDestination('warehouse');
            },
          ),
          AppKpiCard(
            label: "Low Stock Items",
            value: '${inv.getSmartLowStockCount(sales.salesForAnalytics(days: 30))}',
            icon: Icons.warning_amber_rounded,
            color: AppTheme.orange,
            count: inv.getSmartLowStockCount(sales.salesForAnalytics(days: 30)),
            progress: inv.getSmartLowStockCount(sales.salesForAnalytics(days: 30)) / totalMeds,
            onTap: () {
              inv.setFilter('low-stock');
              context.read<NavigationProvider>().selectDestination('warehouse');
            },
          ),
        ],
      );
    });
  }

  String _getLabelSuffix(SalesFilter filter) {
    switch (filter) {
      case SalesFilter.today:
        return 'Today';
      case SalesFilter.yesterday:
        return 'Yesterday';
      case SalesFilter.last7Days:
        return '7 Days';
      case SalesFilter.allTime:
        return 'All Time';
      case SalesFilter.custom:
        return 'Custom';
    }
  }
}

// ── Financial Performance Component ────────────────────────────────────────

class _RevenueBreakdown extends StatelessWidget {
  final SalesProvider sales;
  final OpdProvider opd;

  const _RevenueBreakdown({required this.sales, required this.opd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();
    final bool isCashier = !(auth.currentUser?.canViewHistoricalData ?? true);

    // Collected revenue only
    final productSales = isCashier ? sales.todayRevenue : sales.filteredRevenue;
    final opdRev = isCashier ? sales.todayConsultationRevenue : sales.filteredConsultationRevenue;
    final procedureRev = isCashier ? sales.todayProcedureRevenue : sales.filteredProcedureRevenue;
    final total = productSales + opdRev + procedureRev;

    final totalCash = isCashier ? sales.todayCashRevenue : sales.filteredCashRevenue;
    final totalUpi = isCashier ? sales.todayUpiRevenue : sales.filteredUpiRevenue;
    final totalCard = isCashier ? sales.todayCardRevenue : sales.filteredCardRevenue;

    final String labelSuffix = isCashier ? 'Today' : _getLabelSuffix(sales.activeFilter);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outline.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_rounded, color: AppTheme.primary, size: 20),
              const SizedBox(width: 10),
              Text(
                'Financial Performance',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _RevenueTotalBadge(total: total, label: labelSuffix.toUpperCase()),
              const SizedBox(width: 48),
              // Left: Source Breakdown
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'REVENUE SOURCE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _BreakdownRow(
                      icon: Icons.point_of_sale_rounded,
                      label: 'Product Sales',
                      amount: productSales,
                      total: total > 0 ? total : 1.0,
                      color: AppTheme.emerald,
                    ),
                    const SizedBox(height: 24),
                    _BreakdownRow(
                      icon: Icons.medical_services_outlined,
                      label: 'Procedures',
                      amount: procedureRev,
                      total: total > 0 ? total : 1.0,
                      color: AppTheme.accent,
                    ),
                    const SizedBox(height: 24),
                    _BreakdownRow(
                      icon: Icons.medical_services_rounded,
                      label: 'OPD Consults',
                      amount: opdRev,
                      total: total > 0 ? total : 1.0,
                      color: AppTheme.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 48),
              // Vertical Divider
              Container(
                height: 200,
                width: 1,
                color: cs.outline.withValues(alpha: 0.1),
              ),
              const SizedBox(width: 48),
              // Right: Method Breakdown (Vibrant Cards)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PAYMENT MODES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _BreakdownCard(
                            title: 'Cash',
                            value: '₹${totalCash.toStringAsFixed(0)}',
                            icon: Icons.payments_rounded,
                            color: AppTheme.emerald,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _BreakdownCard(
                            title: 'UPI',
                            value: '₹${totalUpi.toStringAsFixed(0)}',
                            icon: Icons.qr_code_rounded,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _BreakdownCard(
                            title: 'Card',
                            value: '₹${totalCard.toStringAsFixed(0)}',
                            icon: Icons.credit_card_rounded,
                            color: const Color(0xFF8B5CF6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getLabelSuffix(SalesFilter filter) {
    switch (filter) {
      case SalesFilter.today:
        return 'Today';
      case SalesFilter.yesterday:
        return 'Yesterday';
      case SalesFilter.last7Days:
        return '7 Days';
      case SalesFilter.allTime:
        return 'All Time';
      case SalesFilter.custom:
        return 'Custom';
    }
  }
}

class _RevenueTotalBadge extends StatelessWidget {
  final double total;
  final String label;
  const _RevenueTotalBadge({required this.total, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.emerald, AppTheme.emeraldDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.emerald.withValues(alpha: 0.25),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '₹${total.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double amount;
  final double total;
  final Color color;

  const _BreakdownRow({
    required this.icon,
    required this.label,
    required this.amount,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final percent = total > 0 ? (amount / total) : 0.0;

    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Text(label,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Text(
                '₹${amount.toStringAsFixed(0)}',
                style: TextStyle(
                    fontWeight: FontWeight.w900, color: color, fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Stack(
          children: [
            Container(
              height: 10,
              width: double.infinity,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            FractionallySizedBox(
              widthFactor: percent,
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.6)],
                  ),
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: [
                    BoxShadow(
                        color: color.withValues(alpha: 0.15), blurRadius: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${(percent * 100).toStringAsFixed(1)}%',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: color),
          ),
        ),
      ],
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
    return InteractiveHover(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 10),
              spreadRadius: -2,
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.white70,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick Actions Component ────────────────────────────────────────────────

class _DashboardAction {
  final String label;
  final IconData icon;
  final Color color;
  final Widget screen;
  final bool isAllowed;

  _DashboardAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.screen,
    required this.isAllowed,
  });
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    final List<_DashboardAction> allActions = [
      _DashboardAction(
        label: 'New Sale',
        icon: Icons.add_shopping_cart_rounded,
        color: AppTheme.primary,
        screen: const PosScreen(),
        isAllowed: auth.canAccessPOS,
      ),
      _DashboardAction(
        label: 'OPD Queue',
        icon: Icons.personal_injury_rounded,
        color: AppTheme.indigo,
        screen: const OpdQueueWindows(),
        isAllowed: auth.canAccessOPD,
      ),
      _DashboardAction(
        label: 'Warehouse',
        icon: Icons.inventory_2_rounded,
        color: const Color(0xFFF59E0B),
        screen: const WarehouseScreen(),
        isAllowed: auth.canViewWarehouse,
      ),
      _DashboardAction(
        label: 'Staff',
        icon: Icons.badge_rounded,
        color: AppTheme.teal,
        screen: const UserManagementScreen(),
        isAllowed: auth.canManageUsers,
      ),
      _DashboardAction(
        label: 'History',
        icon: Icons.history_rounded,
        color: Colors.grey,
        screen: const SalesHistoryScreen(),
        isAllowed: auth.canViewSalesHistory,
      ),
      _DashboardAction(
        label: 'Settings',
        icon: Icons.settings_rounded,
        color: Colors.blueGrey,
        screen: const SettingsScreen(),
        isAllowed: auth.canAccessSettings,
      ),
      _DashboardAction(
        label: 'Analysis Hub',
        icon: Icons.analytics_rounded,
        color: AppTheme.primary,
        screen: const AnalysisHubScreen(),
        isAllowed: auth.canViewAnalytics,
      ),
      _DashboardAction(
        label: 'Audit Logs',
        icon: Icons.history_toggle_off_rounded,
        color: AppTheme.orange,
        screen: const AuditLogsScreen(),
        isAllowed: auth.isAdmin || auth.currentUser?.role.toLowerCase() == 'manager',
      ),
    ];

    final allowedActions = allActions.where((a) => a.isAllowed).toList();

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: allowedActions.map((action) {
        return SizedBox(
          width: 200, // Fixed width for consistent grid-like appearance
          child: _ModernActionCard(
            label: action.label,
            icon: action.icon,
            color: action.color,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => action.screen),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ModernActionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ModernActionCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InteractiveHover(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.05),
            width: 1.2,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 22),
                  const SizedBox(width: 12),
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Inventory Alerts Component ─────────────────────────────────────────────

class _InventoryAlertSection extends StatelessWidget {
  const _InventoryAlertSection();

  @override
  Widget build(BuildContext context) {
    return const _ActivityAndInsightsSection();
  }
}

class _ActivityAndInsightsSection extends StatelessWidget {
  const _ActivityAndInsightsSection();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isVertical = constraints.maxWidth < 1000;

      if (isVertical) {
        return const Column(
          children: [
            _RecentTransfersTimeline(),
            SizedBox(height: 24),
            _TopPerformingMedicines(),
          ],
        );
      }

      return const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _RecentTransfersTimeline()),
          SizedBox(width: 24),
          Expanded(flex: 2, child: _TopPerformingMedicines()),
        ],
      );
    });
  }
}

class _RecentTransfersTimeline extends StatelessWidget {
  const _RecentTransfersTimeline();

  @override
  Widget build(BuildContext context) {
    final wh = context.watch<WarehouseProvider>();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final transfers = wh.transfers.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outline.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz_rounded, color: AppTheme.primary, size: 22),
              const SizedBox(width: 12),
              Text(
                'Live Stock Operations Timeline',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                      letterSpacing: -0.5,
                    ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'REAL-TIME AUDIT',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primary,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (transfers.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(Icons.swap_horizontal_circle_outlined,
                      color: cs.onSurface.withValues(alpha: 0.2), size: 40),
                  const SizedBox(height: 12),
                  Text(
                    'No stock activities recorded yet',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: transfers.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final t = transfers[index];
                final isSendOut = t.fromWarehouse == 'main' || t.fromWarehouse == 'clinic';
                final accentColor = isSendOut ? AppTheme.success : AppTheme.indigo;
                
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Step timeline node
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isSendOut ? Icons.outbox_rounded : Icons.move_to_inbox_rounded,
                            color: accentColor,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                t.medicineName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${isSendOut ? "-" : "+"}${t.qty} PCS',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  color: accentColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                '${t.fromWarehouse.toUpperCase()} → ${t.toWarehouse.toUpperCase()}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.circle, size: 4, color: cs.onSurface.withValues(alpha: 0.3)),
                              const SizedBox(width: 8),
                              Text(
                                '${t.transferredAt.hour.toString().padLeft(2, '0')}:${t.transferredAt.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                          if (t.note.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: cs.onSurface.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                t.note,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface.withValues(alpha: 0.6),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _TopPerformingMedicines extends StatelessWidget {
  const _TopPerformingMedicines();

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesProvider>();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Aggregate sold items
    final Map<String, int> medicineQuantities = {};
    for (final sale in sales.sales) {
      final items = sales.getSaleItems(sale);
      for (final item in items) {
        medicineQuantities[item.medicineName] =
            (medicineQuantities[item.medicineName] ?? 0) + item.qty;
      }
    }

    // Sort by quantity
    final sorted = medicineQuantities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topPerformers = sorted.take(5).toList();
    final maxQty = topPerformers.isEmpty ? 1 : topPerformers.first.value;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outline.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.leaderboard_rounded, color: AppTheme.orange, size: 22),
              const SizedBox(width: 12),
              Text(
                'Top Selling Medicines',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                      letterSpacing: -0.5,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (topPerformers.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(Icons.query_stats_rounded,
                      color: cs.onSurface.withValues(alpha: 0.2), size: 40),
                  const SizedBox(height: 12),
                  Text(
                    'No sales recorded for this period',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topPerformers.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final item = topPerformers[index];
                final name = item.key;
                final qty = item.value;
                final double ratio = qty / maxQty;

                // Color based on rank
                Color rankColor = AppTheme.orange;
                if (index == 0) rankColor = const Color(0xFFFFD700); // Gold
                if (index == 1) rankColor = const Color(0xFFC0C0C0); // Silver
                if (index == 2) rankColor = const Color(0xFFCD7F32); // Bronze

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Rank Indicator
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: rankColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: rankColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '$qty PCS',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        backgroundColor: cs.onSurface.withValues(alpha: 0.05),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          rankColor.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
