import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/providers/opd_provider.dart';
import '../../shared/models/medicine.dart';
import '../../theme/app_theme.dart';
import '../pos_screen.dart';
import '../warehouse_screen.dart';
import '../sales_history_screen.dart';
import '../settings_screen.dart';
import 'opd/opd_queue_windows.dart';

class DashboardWindows extends StatelessWidget {
  const DashboardWindows({super.key});

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final sales = context.watch<SalesProvider>();
    final opd = context.watch<OpdProvider>();
    final auth = context.watch<AuthProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Redesigned Header
              _DashboardHeader(auth: auth, sales: sales),

              const SizedBox(height: 32),

              // 2. High-Density KPI Grid (Now Row 1)
              _KPIGrid(sales: sales, inv: inv, opd: opd),

              const SizedBox(height: 32),

              // 3. Quick Actions (Now Horizontal Row 2/3)
              _QuickActions(),

              const SizedBox(height: 32),

              // 4. Financial Performance (Restored Colorful Style)
              _RevenueBreakdown(sales: sales, opd: opd),

              const SizedBox(height: 32),

              // 5. Inventory Health Row (Subdued Glass)
              const _InventoryAlertSection(),
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
                gradient: LinearGradient(
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

        // Right Side: Greeting + Filter Chips
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Welcome back, ${auth.currentUser?.name ?? "Admin"}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            _ModernFilterChips(sales: sales),
          ],
        ),
      ],
    );
  }
}

class _ModernFilterChips extends StatelessWidget {
  final SalesProvider sales;

  const _ModernFilterChips({required this.sales});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FilterChipBtn(
          label: 'Today',
          icon: Icons.today_rounded,
          isSelected: sales.activeFilter == SalesFilter.today,
          onTap: () => sales.setFilter(SalesFilter.today),
        ),
        _FilterChipBtn(
          label: '7 Days',
          icon: Icons.date_range_rounded,
          isSelected: sales.activeFilter == SalesFilter.last7Days,
          onTap: () => sales.setFilter(SalesFilter.last7Days),
        ),
        _FilterChipBtn(
          label: 'All Time',
          icon: Icons.all_inclusive_rounded,
          isSelected: sales.activeFilter == SalesFilter.allTime,
          onTap: () => sales.setFilter(SalesFilter.allTime),
        ),
      ],
    );
  }
}

class _FilterChipBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChipBtn({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primary
                  : (isDark ? Colors.white12 : Colors.grey.shade100),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? AppTheme.primary
                    : (isDark ? Colors.white24 : Colors.grey.shade300),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
    // Calculate total today's COLLECTED revenue (Sales + OPD)
    final double opdCollected = opd.appointments
        .where((a) => _isToday(a.scheduledAt) && a.status != 'cancelled' && a.paymentMethod != 'pending')
        .fold(0.0, (sum, a) => sum + a.consultationFee);
    final double salesCollected = sales.todayCashRevenue + sales.todayUpiRevenue + sales.todayCardRevenue;
    final double totalTodayRevenue = salesCollected + opdCollected;

    return LayoutBuilder(builder: (context, constraints) {
      return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: constraints.maxWidth > 900 ? 3 : 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 2.8,
        children: [
          _KPICard(
            label: "Today's Revenue",
            value: '₹${totalTodayRevenue.toStringAsFixed(0)}',
            icon: Icons.trending_up_rounded,
            color: const Color(0xFF10B981), // Green
            subtitle: 'Incl. OPD Fees',
          ),
          _KPICard(
            label: "Today's Sales",
            value: '${sales.todaySalesCount}',
            icon: Icons.shopping_bag_rounded,
            color: const Color(0xFF14B8A6), // Teal
          ),
          _KPICard(
            label: "OPD Today",
            value: '${opd.appointments.where((a) => _isToday(a.scheduledAt)).length}',
            icon: Icons.medical_services_rounded,
            color: AppTheme.primary,
          ),
          _KPICard(
            label: "Near Expiry",
            value: '${inv.nearExpiryCount}',
            icon: Icons.history_rounded,
            color: const Color(0xFF6366F1), // Indigo
            showBadge: inv.nearExpiryCount > 0,
          ),
          _KPICard(
            label: "Expired Stock",
            value: '${inv.expiredCount}',
            icon: Icons.event_busy_rounded,
            color: const Color(0xFFEF4444), // Red
            showBadge: inv.expiredCount > 0,
          ),
          _KPICard(
            label: "Low Stock Items",
            value: '${inv.lowStockCount}',
            icon: Icons.warning_amber_rounded,
            color: const Color(0xFFF59E0B), // Orange
            showBadge: inv.lowStockCount > 0,
          ),
        ],
      );
    });
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }
}

class _KPICard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final bool showBadge;

  const _KPICard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon Badge Left
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              if (showBadge)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppTheme.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 20),
          // Value + Label Right
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: GoogleFonts.manrope(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface.withValues(alpha: 0.5),
                    letterSpacing: 1.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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

    // Collected revenue only
    final productSales = sales.todayCashRevenue + sales.todayUpiRevenue + sales.todayCardRevenue;
    final opdAppts = opd.appointments.where((a) => _isToday(a.scheduledAt) && a.status != 'cancelled' && a.paymentMethod != 'pending');
    final opdRev = opdAppts.fold(0.0, (sum, a) => sum + a.consultationFee);
    final total = productSales + opdRev;

    final totalCash = sales.todayCashRevenue + opdAppts.where((a) => a.paymentMethod == 'cash').fold(0.0, (sum, a) => sum + a.consultationFee);
    final totalUpi = sales.todayUpiRevenue + opdAppts.where((a) => a.paymentMethod == 'upi').fold(0.0, (sum, a) => sum + a.consultationFee);
    final totalCard = sales.todayCardRevenue + opdAppts.where((a) => a.paymentMethod == 'card').fold(0.0, (sum, a) => sum + a.consultationFee);

    return Container(
      padding: const EdgeInsets.all(28),
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
              Icon(Icons.analytics_rounded, color: AppTheme.primary, size: 20),
              const SizedBox(width: 10),
              Text(
                'Financial Performance',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RevenueTotalBadge(total: total),
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
                      color: const Color(0xFF10B981),
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
                            color: const Color(0xFF10B981),
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

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }
}

class _RevenueTotalBadge extends StatelessWidget {
  final double total;
  const _RevenueTotalBadge({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF059669)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.25),
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
            'TODAY',
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
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
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
                style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 14),
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
                    BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 4),
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
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
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
    return Container(
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
    );
  }
}

// ── Quick Actions Component ────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModernActionCard(
            label: 'New Sale',
            icon: Icons.add_shopping_cart_rounded,
            color: AppTheme.primary,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PosScreen())),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _ModernActionCard(
            label: 'OPD Queue',
            icon: Icons.personal_injury_rounded,
            color: const Color(0xFF6366F1),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OpdQueueWindows())),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _ModernActionCard(
            label: 'Warehouse',
            icon: Icons.inventory_2_rounded,
            color: const Color(0xFFF59E0B),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WarehouseScreen())),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _ModernActionCard(
            label: 'History',
            icon: Icons.history_rounded,
            color: Colors.grey,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesHistoryScreen())),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _ModernActionCard(
            label: 'Settings',
            icon: Icons.settings_rounded,
            color: Colors.blueGrey,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ),
      ],
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

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
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
    );
  }
}

// ── Inventory Alerts Component ─────────────────────────────────────────────

class _InventoryAlertSection extends StatelessWidget {
  const _InventoryAlertSection();

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    return LayoutBuilder(builder: (context, constraints) {
      final isVertical = constraints.maxWidth < 1000;
      
      if (isVertical) {
        return Column(
          children: [
            _LowStockAlerts(inv: inv),
            const SizedBox(height: 24),
            _NearExpiryAlerts(inv: inv),
            const SizedBox(height: 24),
            _ExpiredAlerts(inv: inv),
          ],
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _LowStockAlerts(inv: inv)),
          const SizedBox(width: 24),
          Expanded(child: _NearExpiryAlerts(inv: inv)),
          const SizedBox(width: 24),
          Expanded(child: _ExpiredAlerts(inv: inv)),
        ],
      );
    });
  }
}

class _LowStockAlerts extends StatelessWidget {
  final InventoryProvider inv;
  const _LowStockAlerts({required this.inv});

  @override
  Widget build(BuildContext context) {
    final list = inv.medicines.where((m) => m.isLowStock).toList();
    return _AlertBox(
      title: 'Low Stock Alerts',
      icon: Icons.warning_amber_rounded,
      color: AppTheme.danger,
      items: list,
      badgeLabel: 'CONCERNS',
      emptyLabel: 'Stock levels are optimized',
      tagLabel: 'LOW',
    );
  }
}

class _NearExpiryAlerts extends StatelessWidget {
  final InventoryProvider inv;
  const _NearExpiryAlerts({required this.inv});

  @override
  Widget build(BuildContext context) {
    return _AlertBox(
      title: 'Near Expiry Alerts',
      icon: Icons.history_rounded,
      color: const Color(0xFF6366F1),
      items: inv.nearExpiryMedicines,
      badgeLabel: 'WARNINGS',
      emptyLabel: 'No near-expiry items',
      tagLabel: 'SOON',
    );
  }
}

class _ExpiredAlerts extends StatelessWidget {
  final InventoryProvider inv;
  const _ExpiredAlerts({required this.inv});

  @override
  Widget build(BuildContext context) {
    return _AlertBox(
      title: 'Expired Stock Alerts',
      icon: Icons.event_busy_rounded,
      color: const Color(0xFFEF4444),
      items: inv.expiredMedicines,
      badgeLabel: 'CRITICAL',
      emptyLabel: 'No expired items',
      tagLabel: 'EXPIRED',
    );
  }
}

class _AlertBox extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Medicine> items;
  final String badgeLabel;
  final String emptyLabel;
  final String tagLabel;

  const _AlertBox({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
    required this.badgeLabel,
    required this.emptyLabel,
    required this.tagLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outline.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              _ModernBadge(count: items.length, color: color, label: badgeLabel),
            ],
          ),
          const SizedBox(height: 24),
          if (items.isEmpty)
            _EmptyAlertState(label: emptyLabel)
          else
            SizedBox(
              height: 380,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  return _StockWarningCard(
                    medicine: items[index],
                    color: color,
                    tag: tagLabel,
                    icon: icon,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _StockWarningCard extends StatelessWidget {
  final Medicine medicine;
  final Color color;
  final String tag;
  final IconData icon;

  const _StockWarningCard({
    required this.medicine,
    required this.color,
    required this.tag,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final soonestBatch = medicine.soonestExpiringBatch;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medicine.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: cs.onSurface,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Store: ${medicine.storeStock} | Main: ${medicine.mainStock}',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (soonestBatch != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Expires: ${soonestBatch.expiryDate.day}/${soonestBatch.expiryDate.month}/${soonestBatch.expiryDate.year}',
                    style: TextStyle(
                      fontSize: 10,
                      color: color.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              tag,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared Utilities ───────────────────────────────────────────────────────

class _ModernBadge extends StatelessWidget {
  final int count;
  final Color color;
  final String label;

  const _ModernBadge({required this.count, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5)),
          const SizedBox(width: 6),
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              '$count',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyAlertState extends StatelessWidget {
  final String label;
  const _EmptyAlertState({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 24),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

