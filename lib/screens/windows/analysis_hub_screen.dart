import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import 'analysis/tabs/sales_trends_tab.dart';
import 'analysis/tabs/category_sales_tab.dart';
import 'analysis/tabs/product_performance_tab.dart';
import 'analysis/tabs/reorder_dead_stock_tab.dart';
import 'analysis/tabs/patient_analytics_tab.dart';
import 'analysis/tabs/clinic_reconciliation_tab.dart';
import 'analysis/tabs/schedule_h1_register_tab.dart';

class AnalysisHubScreen extends StatefulWidget {
  const AnalysisHubScreen({super.key});

  @override
  State<AnalysisHubScreen> createState() => _AnalysisHubScreenState();
}

class _AnalysisHubScreenState extends State<AnalysisHubScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<String> _allowedTabTitles = [];

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _allowedTabTitles = [];
    if (auth.currentUser != null) {
      if (auth.canViewFinancialAnalytics) {
        _allowedTabTitles.add('Trends');
        _allowedTabTitles.add('Categories');
      }
      if (auth.canViewAnalytics) {
        _allowedTabTitles.add('Explorer');
      }
      if (auth.hasInventoryWriteAccess) {
        _allowedTabTitles.add('Reorder');
      }
      if (auth.canAccessOPD) {
        _allowedTabTitles.add('Patients');
      }
      if (auth.canViewFinancialAnalytics) {
        _allowedTabTitles.add('Reconcile');
      }
      if (auth.canViewOpdReports) {
        _allowedTabTitles.add('H1 Compliance');
      }
    }
    final length = _allowedTabTitles.isEmpty ? 1 : _allowedTabTitles.length;
    _tabController = TabController(length: length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_allowedTabTitles.isEmpty) {
      return Scaffold(
        backgroundColor: context.bgColor,
        appBar: AppBar(
          backgroundColor: context.surfaceColor,
          elevation: 0,
          title: const Text('Business Analytics'),
        ),
        body: const Center(
          child: Text(
            'You do not have permission to view Business Analytics.',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    final List<Widget> tabWidgets = [];
    final List<Widget> tabViews = [];
    for (final title in _allowedTabTitles) {
      if (title == 'Trends') {
        tabWidgets.add(
          const Tab(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.analytics_rounded, size: 16),
                  SizedBox(width: 6),
                  Text('Sales Trends'),
                ],
              ),
            ),
          ),
        );
        tabViews.add(const SalesTrendsTab());
      } else if (title == 'Categories') {
        tabWidgets.add(
          const Tab(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.pie_chart_rounded, size: 16),
                  SizedBox(width: 6),
                  Text('Category Sales Weight'),
                ],
              ),
            ),
          ),
        );
        tabViews.add(const CategorySalesTab());
      } else if (title == 'Explorer') {
        tabWidgets.add(
          const Tab(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bar_chart_rounded, size: 16),
                  SizedBox(width: 6),
                  Text('Performance Explorer'),
                ],
              ),
            ),
          ),
        );
        tabViews.add(const ProductPerformanceTab());
      } else if (title == 'Reorder') {
        tabWidgets.add(
          const Tab(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16),
                  SizedBox(width: 6),
                  Text('Reorder & Dead Stock'),
                ],
              ),
            ),
          ),
        );
        tabViews.add(const ReorderAndDeadStockTab());
      } else if (title == 'Patients') {
        tabWidgets.add(
          const Tab(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_rounded, size: 16),
                  SizedBox(width: 6),
                  Text('Patient Analytics'),
                ],
              ),
            ),
          ),
        );
        tabViews.add(const PatientAnalyticsTab());
      } else if (title == 'Reconcile') {
        tabWidgets.add(
          const Tab(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.compare_arrows_rounded, size: 16),
                  SizedBox(width: 6),
                  Text('Clinic Reconciliation'),
                ],
              ),
            ),
          ),
        );
        tabViews.add(const ClinicReconciliationTab());
      } else if (title == 'H1 Compliance') {
        tabWidgets.add(
          const Tab(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_rounded, size: 16),
                  SizedBox(width: 6),
                  Text('Schedule H1 Register'),
                ],
              ),
            ),
          ),
        );
        tabViews.add(const ScheduleH1RegisterTab());
      }
    }

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.surfaceColor,
        elevation: 0,
        centerTitle: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.insights_rounded,
                color: AppTheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Business Analytics Hub',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: context.surfaceColor,
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.symmetric(vertical: 2),
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: AppTheme.primary.withValues(alpha: 0.08),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              labelColor: AppTheme.primary,
              unselectedLabelColor: context.textMutedColor,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              tabs: tabWidgets,
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: tabViews,
      ),
    );
  }
}
