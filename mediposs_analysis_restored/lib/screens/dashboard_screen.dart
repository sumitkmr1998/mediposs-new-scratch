import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/hub_provider.dart';
import '../services/export_service.dart';
import '../theme/app_theme.dart';
import '../widgets/sales_trend_chart.dart';
import '../widgets/top_medicines_list.dart';
import 'login_screen.dart';
import 'ai_insights_screen.dart';
import 'ai_settings_screen.dart';
import 'profitability_screen.dart';
import 'reorder_screen.dart';
import 'sales_analytics_screen.dart';
import 'category_analysis_screen.dart';
import 'dead_stock_screen.dart';
import 'customer_analytics_screen.dart';
import 'medicines_list_screen.dart';
import 'excel_import_screen.dart';
import '../models/medicine.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  static const _navItems = [
    _NavItem(Icons.dashboard, 'Dashboard'),
    _NavItem(Icons.medication, 'Medicines'),
    _NavItem(Icons.trending_up, 'Sales'),
    _NavItem(Icons.attach_money, 'Profit'),
    _NavItem(Icons.shopping_cart, 'Reorder'),
    _NavItem(Icons.category, 'Categories'),
    _NavItem(Icons.inventory_2, 'Dead Stock'),
    _NavItem(Icons.people, 'Customers'),
    _NavItem(Icons.auto_awesome, 'AI Chat'),
  ];

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_navItems[_selectedIndex].label),
        actions: [
          IconButton(
            icon: hub.isUpdatingFromHub
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: hub.isUpdatingFromHub ? 'Updating...' : 'Refresh Data',
            onPressed: hub.isUpdatingFromHub ? null : () => hub.refreshData(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.download),
            tooltip: 'Export Reports / Import Excel',
            onSelected: (value) => _handleExportClick(value, hub),
            itemBuilder: (_) => [
              const PopupMenuDivider(),
              const PopupMenuItem(
                enabled: false,
                child: Text(
                  '📥 IMPORT',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                ),
              ),
              const PopupMenuItem(
                value: 'import_excel',
                child: Text('  📊 Import from Excel'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                enabled: false,
                child: Text(
                  '📤 EXPORT CSV',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                ),
              ),
              const PopupMenuItem(
                value: 'csv_medicines',
                child: Text('  📋 Medicines'),
              ),
              const PopupMenuItem(
                value: 'csv_sales',
                child: Text('  💰 Sales'),
              ),
              const PopupMenuItem(
                value: 'csv_profit',
                child: Text('  📈 Profitability'),
              ),
              const PopupMenuItem(
                value: 'csv_reorder',
                child: Text('  📦 Reorder'),
              ),
              const PopupMenuItem(
                value: 'csv_deadstock',
                child: Text('  💀 Dead Stock'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                enabled: false,
                child: Text(
                  '📤 EXPORT PDF',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                ),
              ),
              const PopupMenuItem(
                value: 'pdf_medicines',
                child: Text('  📋 Medicines'),
              ),
              const PopupMenuItem(
                value: 'pdf_sales',
                child: Text('  💰 Sales'),
              ),
              const PopupMenuItem(
                value: 'pdf_profit',
                child: Text('  📈 Profitability'),
              ),
              const PopupMenuItem(
                value: 'pdf_reorder',
                child: Text('  📦 Reorder'),
              ),
              const PopupMenuItem(
                value: 'pdf_deadstock',
                child: Text('  💀 Dead Stock'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'AI Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Disconnect',
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: (hub.isLoading || (hub.sales.isEmpty && hub.medicines.isEmpty && hub.error.isNotEmpty))
          ? const Center(child: CircularProgressIndicator())
          : hub.error.isNotEmpty && hub.sales.isEmpty && hub.medicines.isEmpty
          ? Center(
              child: Text(
                hub.error,
                style: const TextStyle(color: AppTheme.danger),
              ),
            )
          : Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() => _selectedIndex = index);
                  },
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: AppTheme.surface,
                  selectedIconTheme: const IconThemeData(
                    color: AppTheme.primary,
                  ),
                  selectedLabelTextStyle: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  unselectedLabelTextStyle: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10,
                  ),
                  destinations: _navItems
                      .map(
                        (item) => NavigationRailDestination(
                          icon: Icon(item.icon),
                          label: Text(item.label),
                        ),
                      )
                      .toList(),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _buildPage(hub)),
              ],
            ),
    );
  }

  Future<void> _handleExportClick(String value, HubProvider hub) async {
    // Handle Excel import
    if (value == 'import_excel') {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ExcelImportScreen()),
      );
      if (result != null && result is List<Medicine>) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Imported ${result.length} medicines'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
      return;
    }

    final parts = value.split('_');
    final format = parts[0];
    final type = parts[1];

    String path;
    if (format == 'csv') {
      switch (type) {
        case 'medicines':
          path = await ExportService.exportMedicinesCSV(hub.medicines);
          break;
        case 'sales':
          path = await ExportService.exportSalesCSV(hub.sales);
          break;
        case 'profit':
          path = await ExportService.exportProfitabilityCSV(
            hub.medicines,
            hub.totalUnitsSold,
            hub.revenueForMedicine,
          );
          break;
        case 'reorder':
          path = await ExportService.exportReorderCSV(
            hub.medicines,
            hub.dailyConsumption,
            hub.daysOfStockRemaining,
          );
          break;
        case 'deadstock':
          path = await ExportService.exportDeadStockCSV(hub.deadStock());
          break;
        default:
          return;
      }
    } else {
      switch (type) {
        case 'medicines':
          path = await ExportService.exportMedicinesPDF(hub.medicines);
          break;
        case 'sales':
          path = await ExportService.exportSalesPDF(hub.sales);
          break;
        case 'profit':
          path = await ExportService.exportProfitabilityPDF(
            hub.medicines,
            hub.totalUnitsSold,
            hub.revenueForMedicine,
          );
          break;
        case 'reorder':
          path = await ExportService.exportReorderPDF(
            hub.medicines,
            hub.dailyConsumption,
            hub.daysOfStockRemaining,
          );
          break;
        case 'deadstock':
          path = await ExportService.exportDeadStockPDF(hub.deadStock());
          break;
        default:
          return;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Exported ${format.toUpperCase()} to: $path'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: 'OK', onPressed: () {}),
      ),
    );
  }

  Widget _buildPage(HubProvider hub) {
    switch (_selectedIndex) {
      case 0:
        return _DashboardContent(hub: hub);
      case 1:
        return const MedicinesListScreen();
      case 2:
        return const SalesAnalyticsScreen();
      case 3:
        return const ProfitabilityScreen();
      case 4:
        return const ReorderScreen();
      case 5:
        return const CategoryAnalysisScreen();
      case 6:
        return const DeadStockScreen();
      case 7:
        return const CustomerAnalyticsScreen();
      case 8:
        return const AiInsightsScreen();
      default:
        return const SizedBox.shrink();
    }
  }
}

class _DashboardContent extends StatelessWidget {
  final HubProvider hub;

  const _DashboardContent({required this.hub});

  @override
  Widget build(BuildContext context) {
    final totalSales = hub.sales.fold(
      0.0,
      (sum, sale) => sum + (sale.isReturn ? -sale.total : sale.total),
    );
    final returnCount = hub.sales.where((s) => s.isReturn).length;
    final totalMedicines = hub.medicines.length;
    final totalProfit = hub.totalProfit;
    final lowStockCount = hub.medicines.where((m) => m.isLowStock).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lowStockCount > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.danger.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.danger,
                    size: 28,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Inventory Alerts',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.danger,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '$lowStockCount items are currently below their low-stock threshold and need attention.',
                          style: TextStyle(
                            color: AppTheme.danger.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      // Could set state to navigate to reorder
                    },
                    child: const Text('VIEW REORDER LIST'),
                  ),
                ],
              ),
            ),
          Text('Overview', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  title: 'Total Revenue',
                  value: '₹${totalSales.toStringAsFixed(0)}',
                  icon: Icons.currency_rupee,
                  color: AppTheme.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  title: 'Profit',
                  value: '₹${totalProfit.toStringAsFixed(0)}',
                  icon: Icons.trending_up,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  title: 'Transactions',
                  value: '${hub.sales.length}',
                  icon: Icons.receipt_long,
                  color: AppTheme.info,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  title: 'Returns',
                  value: '$returnCount',
                  icon: Icons.assignment_return,
                  color: AppTheme.danger,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  title: 'Catalog',
                  value: '$totalMedicines',
                  icon: Icons.medication,
                  color: Colors.purple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  title: 'Low Stock',
                  value: '$lowStockCount',
                  icon: Icons.warning,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            'Sales Trend (Trailing 7 Days)',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Card(
            child: Container(
              height: 300,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 32, 32, 16),
              child: SalesTrendChart(sales: hub.sales),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Low Stock Watchlist',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: TopMedicinesList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}