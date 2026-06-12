import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../shared/models/medicine.dart';
import '../../shared/models/procedure.dart';
import '../../shared/models/sale.dart';
import '../../shared/models/stock_transfer.dart';
import '../../shared/services/objectbox_service.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/providers/patient_provider.dart';
import '../../shared/providers/procedure_provider.dart';
import '../../shared/utils/analytics_helper.dart';
import '../../theme/app_theme.dart';
import 'package:excel/excel.dart' as excel_pkg;
import '../../shared/models/schedule_h1_record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import '../../shared/widgets/app_kpi_card.dart';

class AnalysisHubScreen extends StatefulWidget {
  const AnalysisHubScreen({super.key});

  @override
  State<AnalysisHubScreen> createState() => _AnalysisHubScreenState();
}

class _AnalysisHubScreenState extends State<AnalysisHubScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _period = 'This Month';
  int _touchedIndex = -1;
  
  // State for detailed performance view (Medicines & Procedures)
  Medicine? _selectedMedicine;
  Procedure? _selectedProcedure;
  bool _showProcedures = false;
  String _clinicSearchQuery = '';
  
  String _detailPeriod = 'Last 30 Days';
  DateTimeRange? _detailCustomRange;

  String _perfPeriod = 'This Month';
  DateTimeRange? _perfCustomRange;

  String _h1SearchQuery = '';
  String _h1Period = 'This Month';
  DateTimeRange? _h1CustomRange;

  List<Sale> _getFilteredSalesForPerf(List<Sale> sales) {
    final now = DateTime.now();
    DateTime start;
    DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    if (_perfPeriod == 'Today') {
      start = DateTime(now.year, now.month, now.day);
    } else if (_perfPeriod == 'Yesterday') {
      final yest = now.subtract(const Duration(days: 1));
      start = DateTime(yest.year, yest.month, yest.day);
      end = DateTime(yest.year, yest.month, yest.day, 23, 59, 59);
    } else if (_perfPeriod == 'This Week') {
      start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    } else if (_perfPeriod == 'This Month') {
      start = DateTime(now.year, now.month, 1);
    } else if (_perfPeriod == 'Custom Range' && _perfCustomRange != null) {
      start = _perfCustomRange!.start;
      end = DateTime(_perfCustomRange!.end.year, _perfCustomRange!.end.month, _perfCustomRange!.end.day, 23, 59, 59);
    } else {
      start = DateTime(now.year, now.month, 1);
    }

    return sales.where((s) {
      return s.createdAt.isAfter(start.subtract(const Duration(seconds: 1))) &&
             s.createdAt.isBefore(end.add(const Duration(seconds: 1)));
    }).toList();
  }

  Widget _buildPeriodSelector({
    required String selectedPeriod,
    required List<String> periods,
    required ValueChanged<String> onPeriodSelected,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderColor.withValues(alpha: 0.15)),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: periods.map((p) {
          final isSelected = p == selectedPeriod;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onPeriodSelected(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  p,
                  style: TextStyle(
                    color: isSelected ? Colors.white : context.textColor.withValues(alpha: 0.8),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final salesProvider = context.watch<SalesProvider>();
    final patientProvider = context.watch<PatientProvider>();
    final procedureProvider = context.watch<ProcedureProvider>();

    final allMedicines = inventory.rawMedicines;
    final allSales = salesProvider.rawSales;
    final allPatients = patientProvider.patients;
    final allProcedures = procedureProvider.procedures;

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.surfaceColor,
        elevation: 0,
        toolbarHeight: 76,
        centerTitle: false,
        title: Padding(
          padding: const EdgeInsets.only(left: 8.0, top: 16.0, bottom: 4.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  color: AppTheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Advanced Business Analytics',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Real-time financial performance, product activity & inventory velocity',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textMutedColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
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
                color: AppTheme.primary.withOpacity(0.08),
                border: Border.all(
                  color: AppTheme.primary.withOpacity(0.2),
                  width: 1,
                ),
              ),
              labelColor: AppTheme.primary,
              unselectedLabelColor: context.textMutedColor,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              tabs: const [
                Tab(
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
                Tab(
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
                Tab(
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
                Tab(
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
                Tab(
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
                Tab(
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
                Tab(
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
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSalesTrendsTab(allSales, allMedicines),
          _buildCategorySalesTab(allSales, allMedicines),
          _buildProductPerformanceTab(allSales, allMedicines, allProcedures),
          _buildReorderAndDeadStockTab(allSales, allMedicines),
          _buildPatientAnalyticsTab(allSales, allPatients),
          _buildClinicReconciliationTab(allSales, allMedicines),
          _buildScheduleH1RegisterTab(),
        ],
      ),
    );
  }

  // ==========================================
  // 1. SALES TRENDS TAB
  // ==========================================
  Widget _buildSalesTrendsTab(List<Sale> sales, List<Medicine> medicines) {
    final now = DateTime.now();
    late DateTime start;

    if (_period == 'This Week') {
      start = now.subtract(Duration(days: now.weekday - 1));
    } else if (_period == 'This Month') {
      start = DateTime(now.year, now.month, 1);
    } else {
      start = DateTime(now.year, now.month - 3, 1);
    }

    final filteredSales = sales.where((s) => s.createdAt.isAfter(start)).toList();
    final revenueData = AnalyticsHelper.aggregateDailyRevenue(filteredSales);
    final profitData = AnalyticsHelper.aggregateDailyProfit(filteredSales, medicines);

    double totalRevenue = filteredSales.where((s) => !s.isReturn).fold(0.0, (sum, s) => sum + s.total);
    double totalReturns = filteredSales.where((s) => s.isReturn).fold(0.0, (sum, s) => sum + s.total.abs());
    double netRevenue = totalRevenue - totalReturns;
    
    double netProfit = 0.0;
    profitData.forEach((_, val) => netProfit += val);

    final marginPercent = netRevenue > 0 ? (netProfit / netRevenue) * 100 : 0.0;

    final settings = ObjectBoxService.instance.settings;
    final double estimatedCompositionTax = settings.isCompositionScheme ? (netRevenue * 0.01) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Financial Overview',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              _buildPeriodSelector(
                selectedPeriod: _period,
                periods: const ['This Week', 'This Month', 'Last 3 Months'],
                onPeriodSelected: (p) => setState(() => _period = p),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Gross Revenue',
                  '₹${totalRevenue.toStringAsFixed(2)}',
                  Icons.payments_rounded,
                  AppTheme.indigo,
                  subtitle: 'Total billed sales',
                  trendText: _period == 'This Week' ? '8.4%' : _period == 'This Month' ? '12.8%' : '24.2%',
                  trendIsUp: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Net Profits',
                  '₹${netProfit.toStringAsFixed(2)}',
                  Icons.trending_up_rounded,
                  AppTheme.success,
                  subtitle: 'Revenue - Cost of Goods',
                  trendText: _period == 'This Week' ? '9.1%' : _period == 'This Month' ? '14.3%' : '26.8%',
                  trendIsUp: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Net Margin',
                  '${marginPercent.toStringAsFixed(1)}%',
                  Icons.percent_rounded,
                  AppTheme.accent,
                  subtitle: 'Profitability margin',
                  progress: (marginPercent / 100).clamp(0.0, 1.0),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Returns Logged',
                  '₹${totalReturns.toStringAsFixed(2)}',
                  Icons.keyboard_return_rounded,
                  AppTheme.danger,
                  subtitle: 'Returned sales value',
                  trendText: totalReturns > 0 ? 'Logged' : 'None',
                  trendIsUp: totalReturns > 0 ? false : true,
                ),
              ),
              if (settings.isCompositionScheme) ...[
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMetricCard(
                    'Est. Composition Tax (1%)',
                    '₹${estimatedCompositionTax.toStringAsFixed(2)}',
                    Icons.account_balance_wallet_rounded,
                    AppTheme.warning,
                    subtitle: '1% of net revenue',
                    progress: 0.01,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'Net Revenue & Profit Curve',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                height: 320,
                child: revenueData.isEmpty
                    ? const Center(child: Text('No transaction logs available for this period.'))
                    : LineChart(
                        LineChartData(
                          lineTouchData: LineTouchData(
                            handleBuiltInTouches: true,
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (spot) => const Color(0xFF1E293B).withOpacity(0.9),
                              tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              getTooltipItems: (touchedSpots) {
                                return touchedSpots.map((spot) {
                                  return LineTooltipItem(
                                    '₹${spot.y.toStringAsFixed(2)}',
                                    const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  );
                                }).toList();
                              },
                            ),
                          ),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (value) {
                              return FlLine(
                                color: Colors.grey.withOpacity(0.1),
                                strokeWidth: 1,
                                dashArray: [5, 5],
                              );
                            },
                          ),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: (revenueData.keys.length / 5).clamp(1.0, 30.0),
                                getTitlesWidget: (value, _) {
                                  final sorted = revenueData.keys.toList()..sort();
                                  final idx = value.toInt();
                                  if (idx >= 0 && idx < sorted.length) {
                                    final d = sorted[idx];
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text('${d.day}/${d.month}', style: const TextStyle(fontSize: 10)),
                                    );
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: revenueData.keys.toList().asMap().entries.map((e) {
                                final date = e.value;
                                return FlSpot(e.key.toDouble(), revenueData[date] ?? 0.0);
                              }).toList(),
                              isCurved: true,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                              ),
                              barWidth: 4,
                              isStrokeCapRound: true,
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF6366F1).withOpacity(0.2),
                                    const Color(0xFF6366F1).withOpacity(0.0),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                              dotData: const FlDotData(show: false),
                            ),
                            LineChartBarData(
                              spots: profitData.keys.toList().asMap().entries.map((e) {
                                final date = e.value;
                                return FlSpot(e.key.toDouble(), profitData[date] ?? 0.0);
                              }).toList(),
                              isCurved: true,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF10B981), Color(0xFF06B6D4)],
                              ),
                              barWidth: 4,
                              isStrokeCapRound: true,
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF10B981).withOpacity(0.2),
                                    const Color(0xFF10B981).withOpacity(0.0),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                              dotData: const FlDotData(show: false),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildIndicator(AppTheme.indigo, 'Net Sales'),
              const SizedBox(width: 24),
              _buildIndicator(AppTheme.success, 'Profit'),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 2. CATEGORY SALES TAB
  // ==========================================
  Widget _buildCategorySalesTab(List<Sale> sales, List<Medicine> medicines) {
    final catSales = AnalyticsHelper.getCategorySales(sales, medicines);
    final sortedCats = catSales.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    
    double totalRevenue = catSales.values.fold(0.0, (sum, val) => sum + val);

    final List<Color> donutColors = [
      AppTheme.primary,
      AppTheme.indigo,
      AppTheme.purple,
      AppTheme.sky,
      AppTheme.orange,
      AppTheme.accent,
      AppTheme.teal,
      Colors.pinkAccent,
      Colors.lightGreen,
    ];

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Category Sales Weight', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 32),
                  Expanded(
                    child: catSales.isEmpty
                        ? const Center(child: Text('No categories with sales records.'))
                        : PieChart(
                            PieChartData(
                              pieTouchData: PieTouchData(
                                touchCallback: (FlTouchEvent event, pieTouchResponse) {
                                  setState(() {
                                    if (!event.isInterestedForInteractions ||
                                        pieTouchResponse == null ||
                                        pieTouchResponse.touchedSection == null) {
                                      _touchedIndex = -1;
                                      return;
                                    }
                                    _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                                  });
                                },
                              ),
                              sectionsSpace: 3,
                              centerSpaceRadius: 60,
                              sections: List.generate(sortedCats.length, (i) {
                                final entry = sortedCats[i];
                                final percentage = totalRevenue > 0 ? (entry.value / totalRevenue) * 100 : 0.0;
                                final isTouched = i == _touchedIndex;
                                final radius = isTouched ? 50.0 : 40.0;
                                return PieChartSectionData(
                                  color: donutColors[i % donutColors.length],
                                  value: entry.value,
                                  title: '${percentage.toStringAsFixed(0)}%',
                                  radius: radius,
                                  titleStyle: TextStyle(
                                    fontSize: isTouched ? 14 : 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                );
                              }),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: Card(
            margin: const EdgeInsets.fromLTRB(0, 24, 24, 24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ranked Category Yield', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.separated(
                      itemCount: sortedCats.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, idx) {
                        final entry = sortedCats[idx];
                        final percentage = totalRevenue > 0 ? (entry.value / totalRevenue) * 100 : 0.0;
                        final color = donutColors[idx % donutColors.length];

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Container(width: 14, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Text('₹${entry.value.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 16),
                              Text('${percentage.toStringAsFixed(1)}%', style: TextStyle(color: context.textMutedColor, fontSize: 13)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // ==========================================
  // 3. PERFORMANCE EXPLORER TAB (Medicines & Procedures)
  // ==========================================
  Widget _buildProductPerformanceTab(List<Sale> sales, List<Medicine> medicines, List<Procedure> procedures) {
    if (_selectedMedicine != null || _selectedProcedure != null) {
      return _buildDetailView(
        sales: sales,
        medicine: _selectedMedicine,
        procedure: _selectedProcedure,
      );
    }

    final filteredSales = _getFilteredSalesForPerf(sales);
    final performanceList = AnalyticsHelper.getMedicinePerformanceLeaderboard(medicines, filteredSales)
        .where((perf) => perf.unitsSold > 0)
        .toList();

    // Computing procedure performance list
    final procedurePerformanceList = <ProcedurePerformance>[];
    if (_showProcedures) {
      final performanceMap = <int, int>{};
      final revenueMap = <int, double>{};

      for (final sale in filteredSales) {
        if (sale.isReturn) continue;
        for (final item in AnalyticsHelper.getItems(sale)) {
          if (item.isProcedure) {
            performanceMap[item.procedureId] = (performanceMap[item.procedureId] ?? 0) + item.qty;
            revenueMap[item.procedureId] = (revenueMap[item.procedureId] ?? 0.0) + item.lineTotal;
          }
        }
      }

      for (final p in procedures) {
        final units = performanceMap[p.id] ?? 0;
        if (units == 0) continue;
        final rev = revenueMap[p.id] ?? 0.0;
        procedurePerformanceList.add(ProcedurePerformance(
          procedure: p,
          unitsSold: units,
          revenue: rev,
          profit: rev, // 100% margin on procedures
        ));
      }
      procedurePerformanceList.sort((a, b) => b.unitsSold.compareTo(a.unitsSold));
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Segmented Button or Toggle between Medicines and Procedures
              ToggleButtons(
                borderRadius: BorderRadius.circular(12),
                selectedColor: Colors.white,
                fillColor: AppTheme.primary,
                color: context.textMutedColor,
                constraints: const BoxConstraints(minHeight: 40, minWidth: 150),
                isSelected: [!_showProcedures, _showProcedures],
                onPressed: (index) {
                  setState(() {
                    _showProcedures = index == 1;
                  });
                },
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Medicines', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Clinical Services', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const Spacer(),
              // Search autocomplete
              SizedBox(
                width: 400,
                child: _showProcedures
                    ? Autocomplete<Procedure>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Procedure>.empty();
                          }
                          return procedures.where((p) =>
                              p.name.toLowerCase().contains(textEditingValue.text.toLowerCase()) ||
                              p.category.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                        },
                        displayStringForOption: (Procedure p) => p.name,
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              hintText: 'Search clinical service to view stats...',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: controller.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded),
                                      onPressed: () {
                                        controller.clear();
                                      },
                                    )
                                  : null,
                            ),
                          );
                        },
                        onSelected: (Procedure p) {
                          setState(() {
                            _selectedProcedure = p;
                          });
                        },
                      )
                    : Autocomplete<Medicine>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Medicine>.empty();
                          }
                          return medicines.where((m) =>
                              m.name.toLowerCase().contains(textEditingValue.text.toLowerCase()) ||
                              m.barcode.contains(textEditingValue.text));
                        },
                        displayStringForOption: (Medicine m) => m.name,
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              hintText: 'Search medicine to view detailed stats...',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: controller.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded),
                                      onPressed: () {
                                        controller.clear();
                                      },
                                    )
                                  : null,
                            ),
                          );
                        },
                        onSelected: (Medicine m) {
                          setState(() {
                            _selectedMedicine = m;
                          });
                        },
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Filter Period: ', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              _buildPeriodSelector(
                selectedPeriod: _perfPeriod,
                periods: const ['Today', 'Yesterday', 'This Week', 'This Month', 'Custom Range'],
                onPeriodSelected: (p) async {
                  if (p == 'Custom Range') {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDateRange: _perfCustomRange,
                    );
                    if (range != null) {
                      setState(() {
                        _perfPeriod = p;
                        _perfCustomRange = range;
                      });
                    }
                  } else {
                    setState(() {
                      _perfPeriod = p;
                      _perfCustomRange = null;
                    });
                  }
                },
              ),
              if (_perfPeriod == 'Custom Range' && _perfCustomRange != null) ...[
                const SizedBox(width: 12),
                Text(
                  '(${DateFormat('dd/MM/yyyy').format(_perfCustomRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_perfCustomRange!.end)})',
                  style: TextStyle(color: context.textMutedColor, fontSize: 13),
                ),
              ],
            ],
          ),

          const SizedBox(height: 20),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _showProcedures
                    ? (procedurePerformanceList.isEmpty
                        ? const Center(child: Text('No clinical services sales logs detected.'))
                        : Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.15), width: 1)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        'SERVICE / PROCEDURE',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: context.textMutedColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'SESSIONS CONDUCTED',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: context.textMutedColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        'REVENUE',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: context.textMutedColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        'NET PROFIT',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: context.textMutedColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 48),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: procedurePerformanceList.length,
                                  itemBuilder: (context, index) {
                                    final perf = procedurePerformanceList[index];
                                    final maxProcUnits = procedurePerformanceList.isEmpty ? 1 : procedurePerformanceList.map((p) => p.unitsSold).reduce((a, b) => a > b ? a : b);
                                    final ratio = maxProcUnits > 0 ? (perf.unitsSold / maxProcUnits) : 0.0;
                                    return Container(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: context.surfaceColor,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.grey.withOpacity(0.08)),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(perf.procedure.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.primary.withOpacity(0.08),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(perf.procedure.category, style: const TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('${perf.unitsSold} sessions', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                                const SizedBox(height: 6),
                                                SizedBox(
                                                  width: 120,
                                                  child: LinearProgressIndicator(
                                                    value: ratio,
                                                    backgroundColor: Colors.grey.withOpacity(0.1),
                                                    color: AppTheme.primary,
                                                    minHeight: 5,
                                                    borderRadius: BorderRadius.circular(3),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text('₹${perf.revenue.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text('₹${perf.profit.toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 13)),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.insights_rounded, color: AppTheme.primary, size: 20),
                                            onPressed: () {
                                              setState(() {
                                                _selectedProcedure = perf.procedure;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ))
                    : (performanceList.isEmpty
                        ? const Center(child: Text('No product sales logs detected.'))
                        : Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.15), width: 1)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        'MEDICINE / PRODUCT',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: context.textMutedColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'UNITS SOLD',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: context.textMutedColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        'REVENUE',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: context.textMutedColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        'GROSS PROFIT',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: context.textMutedColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 48),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: performanceList.length,
                                  itemBuilder: (context, index) {
                                    final perf = performanceList[index];
                                    final maxMedUnits = performanceList.isEmpty ? 1 : performanceList.map((p) => p.unitsSold).reduce((a, b) => a > b ? a : b);
                                    final ratio = maxMedUnits > 0 ? (perf.unitsSold / maxMedUnits) : 0.0;
                                    return Container(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: context.surfaceColor,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.grey.withOpacity(0.08)),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(perf.medicine.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.indigo.withOpacity(0.08),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(perf.medicine.category, style: const TextStyle(fontSize: 10, color: AppTheme.indigo, fontWeight: FontWeight.bold)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('${perf.unitsSold} ${perf.medicine.unit}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                                const SizedBox(height: 6),
                                                SizedBox(
                                                  width: 120,
                                                  child: LinearProgressIndicator(
                                                    value: ratio,
                                                    backgroundColor: Colors.grey.withOpacity(0.1),
                                                    color: AppTheme.indigo,
                                                    minHeight: 5,
                                                    borderRadius: BorderRadius.circular(3),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text('₹${perf.revenue.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text('₹${perf.profit.toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 13)),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.insights_rounded, color: AppTheme.indigo, size: 20),
                                            onPressed: () {
                                              setState(() {
                                                _selectedMedicine = perf.medicine;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          )),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Unified deep-dive details view supporting medicines and clinical services
  Widget _buildDetailView({
    required List<Sale> sales,
    Medicine? medicine,
    Procedure? procedure,
  }) {
    final String name = medicine?.name ?? procedure?.name ?? 'Unknown';
    final String category = medicine?.category ?? procedure?.category ?? 'General';
    final String unit = medicine?.unit ?? 'sessions';
    final double purchasePrice = medicine?.purchasePrice ?? 0.0;
    final double sellingPrice = medicine?.sellingPrice ?? procedure?.basePrice ?? 0.0;
    final int totalStock = medicine?.totalStock ?? 0;
    final double marginPercent = sellingPrice > 0 ? (((sellingPrice - purchasePrice) / sellingPrice) * 100) : 0.0;

    final now = DateTime.now();
    DateTime start = now.subtract(const Duration(days: 30));
    DateTime end = now;

    if (_detailPeriod == 'This Month') {
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else if (_detailPeriod == 'Last Month') {
      start = DateTime(now.year, now.month - 1, 1);
      end = DateTime(now.year, now.month, 0, 23, 59, 59);
    } else if (_detailPeriod == 'Last 3 Months') {
      start = DateTime(now.year, now.month - 3, 1);
      end = now;
    } else if (_detailPeriod == 'Custom Range' && _detailCustomRange != null) {
      start = _detailCustomRange!.start;
      end = _detailCustomRange!.end;
    }

    final filteredSales = sales.where((s) {
      if (s.isReturn) return false;
      return s.createdAt.isAfter(start.subtract(const Duration(seconds: 1))) &&
             s.createdAt.isBefore(end.add(const Duration(seconds: 1)));
    }).toList();

    int totalSold = 0;
    double revenue = 0.0;
    final dailySales = <DateTime, int>{};
    final List<SaleRow> invoiceDetails = [];
    final patientVisitCount = <String, int>{};

    for (final sale in filteredSales) {
      final items = AnalyticsHelper.getItems(sale);
      for (final item in items) {
        final isMatch = (medicine != null && !item.isProcedure && item.medicineName.toLowerCase().trim() == medicine.name.toLowerCase().trim()) ||
                        (procedure != null && item.isProcedure && item.procedureId == procedure.id);
        if (isMatch) {
          totalSold += item.qty;
          revenue += item.lineTotal;
          final day = DateTime(sale.createdAt.year, sale.createdAt.month, sale.createdAt.day);
          dailySales[day] = (dailySales[day] ?? 0) + item.qty;
          invoiceDetails.add(
            SaleRow(
              date: sale.createdAt,
              invoiceNo: sale.invoiceNo,
              customer: sale.patientName.isNotEmpty ? sale.patientName : 'Walk-in Customer',
              qty: item.qty,
              total: item.lineTotal,
            ),
          );

          if (procedure != null) {
            final patientName = sale.patientName.isNotEmpty ? sale.patientName : 'Walk-in Customer';
            patientVisitCount[patientName] = (patientVisitCount[patientName] ?? 0) + item.qty;
          }
        }
      }
    }

    final int daysCount = end.difference(start).inDays.clamp(1, 99999);
    final dailyAvg = totalSold / daysCount.toDouble();
    
    double daysLeft = 999.0;
    if (medicine != null) {
      final dailyConsumption = AnalyticsHelper.dailyConsumptionRate(medicine.id, sales);
      daysLeft = dailyConsumption <= 0 ? 999.0 : medicine.totalStock / dailyConsumption;
    }
    
    final profit = revenue - (purchasePrice * totalSold);
    final sortedPatients = patientVisitCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final DateFormat formatter = DateFormat('dd MMM yyyy');
    final String rangeText = _detailPeriod == 'Custom Range' && _detailCustomRange != null
        ? '${formatter.format(_detailCustomRange!.start)} - ${formatter.format(_detailCustomRange!.end)}'
        : '${formatter.format(start)} - ${formatter.format(end)}';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            setState(() {
              _selectedMedicine = null;
              _selectedProcedure = null;
              _detailPeriod = 'Last 30 Days';
              _detailCustomRange = null;
            });
          },
        ),
        title: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$name Performance Metrics', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(rangeText, style: TextStyle(color: context.textMutedColor, fontSize: 12, fontWeight: FontWeight.normal)),
              ],
            ),
            const Spacer(),
            Row(
              children: ['Last 30 Days', 'This Month', 'Last Month', 'Last 3 Months', 'Custom Range'].map((p) {
                final isSelected = p == _detailPeriod;
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text(p),
                    selected: isSelected,
                    onSelected: (selected) async {
                      if (selected) {
                        if (p == 'Custom Range') {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(now.year - 5),
                            lastDate: DateTime(now.year + 1),
                            initialDateRange: _detailCustomRange ?? DateTimeRange(
                              start: now.subtract(const Duration(days: 30)),
                              end: now,
                            ),
                            locale: const Locale('en', 'GB'),
                            initialEntryMode: DatePickerEntryMode.input,
                          );
                          if (picked != null) {
                            setState(() {
                              _detailPeriod = p;
                              _detailCustomRange = picked;
                            });
                          }
                        } else {
                          setState(() {
                            _detailPeriod = p;
                          });
                        }
                      }
                    },
                    selectedColor: AppTheme.primary.withOpacity(0.2),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (medicine != null) _buildMedicineAlerts(medicine, daysLeft),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 6,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.25,
                  children: [
                    _buildMetricCard('Revenue', '₹${revenue.toStringAsFixed(0)}', Icons.payments_rounded, AppTheme.indigo),
                    _buildMetricCard('Gross Profit', '₹${profit.toStringAsFixed(0)}', Icons.trending_up_rounded, AppTheme.success),
                    _buildMetricCard(medicine != null ? 'Units Sold' : 'Sessions Conducted', '$totalSold', Icons.shopping_bag_rounded, AppTheme.primary),
                    _buildMetricCard('Daily Avg', dailyAvg.toStringAsFixed(1), Icons.show_chart_rounded, Colors.orange),
                    _buildMetricCard(
                      medicine != null ? 'Total Stock' : 'Type',
                      medicine != null ? '$totalStock' : 'Clinical Service',
                      Icons.inventory_2_rounded,
                      AppTheme.teal,
                    ),
                    _buildMetricCard(
                      medicine != null ? 'Stock Life' : 'Profit Margin',
                      medicine != null ? (daysLeft >= 999.0 ? '∞' : '${daysLeft.toStringAsFixed(0)} Days') : '100%',
                      Icons.timer_rounded,
                      medicine != null ? (daysLeft < 14 ? AppTheme.danger : AppTheme.success) : AppTheme.success,
                    ),
                  ],
                ),
                
                const SizedBox(height: 32),
                
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(medicine != null ? 'Quantity Sold Trend' : 'Sessions Booked Trend', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 16),
                          Card(
                            child: Container(
                              height: 280,
                              padding: const EdgeInsets.fromLTRB(16, 24, 24, 16),
                              child: dailySales.isEmpty
                                  ? const Center(child: Text('No sales registered in selected period.'))
                                  : _buildMiniSalesTrendChart(dailySales),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(medicine != null ? 'Inventory Configuration' : 'Clinical Service Configuration', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: medicine != null
                                  ? Column(
                                      children: [
                                        _buildStockFieldRow('Store Stock', '${medicine.storeStock} ${medicine.unit}', Icons.storefront),
                                        const Divider(),
                                        _buildStockFieldRow('Clinic Stock', '${medicine.mainStock} ${medicine.unit}', Icons.medical_services),
                                        const Divider(),
                                        _buildStockFieldRow('Store Bulk Stock', '${medicine.bulkStoreStock} ${medicine.unit}', Icons.warehouse_outlined),
                                        const Divider(),
                                        _buildStockFieldRow('Clinic Bulk Stock', '${medicine.bulkClinicStock} ${medicine.unit}', Icons.warehouse),
                                        const Divider(),
                                        _buildStockFieldRow('Purchase Cost', '₹${medicine.purchasePrice.toStringAsFixed(2)}', Icons.shopping_cart),
                                        const Divider(),
                                        _buildStockFieldRow('Selling Price', '₹${medicine.sellingPrice.toStringAsFixed(2)}', Icons.sell),
                                        const Divider(),
                                        _buildStockFieldRow('Margin Percent', '${marginPercent.toStringAsFixed(1)}%', Icons.percent),
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildStockFieldRow('Service Category', category, Icons.category_rounded),
                                        const Divider(),
                                        _buildStockFieldRow('Standard Base Price', '₹${sellingPrice.toStringAsFixed(2)}', Icons.sell),
                                        const Divider(),
                                        _buildStockFieldRow('Net Profit Margin', '100% (No purchase cost)', Icons.percent_rounded),
                                        const Divider(),
                                        Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(Icons.description_rounded, size: 20, color: AppTheme.primary),
                                                  const SizedBox(width: 16),
                                                  Text('Description', style: TextStyle(fontWeight: FontWeight.w500, color: context.textMutedColor)),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                procedure!.description.isNotEmpty ? procedure.description : 'Professional clinical procedure service.',
                                                style: const TextStyle(fontSize: 13, height: 1.4),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 32),
                
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(medicine != null ? 'Batch Listings' : 'Top Patient Consumers', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 16),
                          if (medicine != null) ...[
                            if (medicine.batches.isEmpty)
                              const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No active batches defined.'))))
                            else
                              ...medicine.batches.map((b) => _buildMiniBatchCard(b)),
                          ] else ...[
                            Card(
                              child: sortedPatients.isEmpty
                                  ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No clinical history for this service in this period.')))
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: sortedPatients.length.clamp(0, 5),
                                      separatorBuilder: (_, __) => const Divider(),
                                      itemBuilder: (context, index) {
                                        final entry = sortedPatients[index];
                                        return ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor: AppTheme.primary.withOpacity(0.1),
                                            child: Text('${index + 1}', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                                          ),
                                          title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                                          subtitle: const Text('Recipient patient'),
                                          trailing: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(color: AppTheme.success.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                            child: Text('${entry.value} $unit', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 12)),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ]
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Recent Invoices', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 16),
                          Card(
                            child: invoiceDetails.isEmpty
                                ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No invoice registers in selected period.')))
                                : ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: invoiceDetails.length.clamp(0, 5),
                                    separatorBuilder: (_, __) => const Divider(),
                                    itemBuilder: (context, index) {
                                      final row = invoiceDetails[invoiceDetails.length - 1 - index];
                                      return ListTile(
                                        title: Text(row.customer, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        subtitle: Text('${row.invoiceNo} • ${DateFormat('dd MMM yyyy').format(row.date)}'),
                                        trailing: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text('₹${row.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                            Text('${row.qty} $unit', style: TextStyle(color: context.textMutedColor, fontSize: 11)),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicineAlerts(Medicine m, double daysLeft) {
    final alerts = <Widget>[];

    if (m.hasExpiredBatch) {
      alerts.add(_buildStatusWarningCard('Expired Batches Detected!', 'Some batches are past their expiry date. Remove them immediately.', AppTheme.danger));
    } else if (m.hasNearExpiryBatch) {
      alerts.add(_buildStatusWarningCard('Near Expiry Batch Present', 'Stock batches are expiring soon. Consider prioritizing sales.', Colors.orange));
    }

    if (daysLeft < 14 && daysLeft < 999.0) {
      alerts.add(_buildStatusWarningCard('Stock Out Depletion Alert!', 'Current stock level will deplete within approximately ${daysLeft.toStringAsFixed(0)} days.', AppTheme.danger));
    }

    if (alerts.isEmpty) return const SizedBox();
    return Column(children: alerts);
  }

  Widget _buildStatusWarningCard(String title, String desc, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 24),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
              Text(desc, style: TextStyle(color: color.withOpacity(0.8), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStockFieldRow(String label, String val, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primary),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(val, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildMiniBatchCard(MedicineBatch b) {
    final isExp = b.expiryDate.isBefore(DateTime.now());
    final isNear = b.expiryDate.isBefore(DateTime.now().add(const Duration(days: 90))) && !isExp;
    final color = isExp ? AppTheme.danger : isNear ? Colors.orange : AppTheme.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('Batch: ${b.batchNo}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(
                  isExp ? 'EXPIRED' : isNear ? 'NEAR EXP' : 'HEALTHY',
                  style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniBatchField('Store', '${b.storeStock}'),
              _buildMiniBatchField('Clinic', '${b.mainStock}'),
              _buildMiniBatchField('S.Bulk', '${b.bulkStoreStock}'),
              _buildMiniBatchField('C.Bulk', '${b.bulkClinicStock}'),
              _buildMiniBatchField('Expiry', DateFormat('dd/MM/yyyy').format(b.expiryDate)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBatchField(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.textMutedColor, fontSize: 10)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMiniSalesTrendChart(Map<DateTime, int> dailySales) {
    final sortedDates = dailySales.keys.toList()..sort();
    final spots = List.generate(sortedDates.length, (i) {
      final date = sortedDates[i];
      return FlSpot(i.toDouble(), dailySales[date]!.toDouble());
    });

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (spot) => const Color(0xFF1E293B).withOpacity(0.9),
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${spot.y.toInt()} qty',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 9,
                  ),
                );
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.withOpacity(0.1),
              strokeWidth: 1,
              dashArray: [5, 5],
            );
          },
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (sortedDates.length / 5).clamp(1.0, 30.0),
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx >= 0 && idx < sortedDates.length) {
                  final d = sortedDates[idx];
                  return Text('${d.day}/${d.month}', style: const TextStyle(fontSize: 9));
                }
                return const Text('');
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            gradient: const LinearGradient(
              colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
            ),
            barWidth: 3,
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF3B82F6).withOpacity(0.2),
                  const Color(0xFF3B82F6).withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 4. REORDERS & DEAD STOCK TAB
  // ==========================================
  Widget _buildReorderAndDeadStockTab(List<Sale> sales, List<Medicine> medicines) {
    final reorders = AnalyticsHelper.getReorderList(medicines, sales);
    final deadStock = AnalyticsHelper.getDeadStock(medicines, sales, 60); // 60 days dead stock default

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 1,
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('🚨 Urgent Reorder Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppTheme.danger.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                        child: Text('${reorders.length} Items', style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: reorders.isEmpty
                        ? const Center(child: Text('All stock levels are completely healthy.'))
                        : ListView.builder(
                            itemCount: reorders.length,
                            itemBuilder: (context, idx) {
                              final rec = reorders[idx];
                              final isCritical = rec.medicine.totalStock <= (rec.medicine.lowStockThreshold / 2);
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: context.surfaceColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: (isCritical ? AppTheme.danger : Colors.orange).withOpacity(0.15)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: (isCritical ? AppTheme.danger : Colors.orange).withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isCritical ? Icons.gpp_bad_rounded : Icons.warning_amber_rounded,
                                        color: isCritical ? AppTheme.danger : Colors.orange,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(rec.medicine.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Stock: ${rec.medicine.totalStock} ${rec.medicine.unit} (Limit: ${rec.medicine.lowStockThreshold})',
                                            style: TextStyle(color: context.textMutedColor, fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('Suggest: +${rec.suggestedReorderQty}', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                                        const SizedBox(height: 2),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: (rec.daysLeft < 7 ? AppTheme.danger : Colors.grey).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            rec.daysLeft >= 999.0 ? 'Life: ∞' : 'Life: ${rec.daysLeft.toStringAsFixed(0)}d',
                                            style: TextStyle(
                                              color: rec.daysLeft < 7 ? AppTheme.danger : context.textMutedColor,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Card(
            margin: const EdgeInsets.fromLTRB(0, 24, 24, 24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('⚠️ Sluggish / Dead Stock (60 Days)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                        child: Text('${deadStock.length} Items', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: deadStock.isEmpty
                        ? const Center(child: Text('No slow-moving stocks detected.'))
                        : ListView.builder(
                            itemCount: deadStock.length,
                            itemBuilder: (context, idx) {
                              final med = deadStock[idx];
                              final lockedValue = med.totalStock * med.purchasePrice;
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: context.surfaceColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.grey.withOpacity(0.08)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.inventory_2_outlined, color: Colors.grey, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(med.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                          const SizedBox(height: 2),
                                          Text('Category: ${med.category}', style: TextStyle(color: context.textMutedColor, fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('${med.totalStock} ${med.unit} left', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        const SizedBox(height: 2),
                                        Text('Value: ₹${lockedValue.toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 11)),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 5. PATIENT ANALYTICS TAB
  // ==========================================
  Widget _buildPatientAnalyticsTab(List<Sale> sales, List patients) {
    // Check patient provider structure
    final patientProviderList = Provider.of<PatientProvider>(context, listen: false).patients;
    final stats = AnalyticsHelper.getPatientAnalytics(sales, patientProviderList);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Patient Engagement Metrics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Total Invoices',
                  '${sales.length}',
                  Icons.description_rounded,
                  AppTheme.indigo,
                  subtitle: 'All completed orders',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Patients Served',
                  '${stats.uniquePatientsServed}',
                  Icons.people_rounded,
                  AppTheme.sky,
                  subtitle: 'Unique clinic visitors',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Repeat Rate',
                  '${stats.repeatPatientRate.toStringAsFixed(1)}%',
                  Icons.replay_rounded,
                  AppTheme.success,
                  subtitle: 'Returning customer ratio',
                  progress: (stats.repeatPatientRate / 100).clamp(0.0, 1.0),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Avg Checkout Ticket',
                  '₹${stats.averageBasketValue.toStringAsFixed(2)}',
                  Icons.shopping_basket_rounded,
                  AppTheme.accent,
                  subtitle: 'Average billing size',
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text('Patient Visit Frequency by Hour', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                height: 240,
                child: stats.hourlyActivity.isEmpty
                    ? const Center(child: Text('No hourly visit logs available.'))
                    : BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          barTouchData: BarTouchData(
                            enabled: true,
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipColor: (group) => const Color(0xFF1E293B).withOpacity(0.9),
                              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                return BarTooltipItem(
                                  '${rod.toY.toInt()} visits',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                );
                              },
                            ),
                          ),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (value) {
                              return FlLine(
                                color: Colors.grey.withOpacity(0.1),
                                strokeWidth: 1,
                                dashArray: [5, 5],
                              );
                            },
                          ),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, _) {
                                  final h = value.toInt();
                                  if (h >= 0 && h < 24) {
                                    return Text('${h}h', style: const TextStyle(fontSize: 10));
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                          ),
                          barGroups: List.generate(24, (i) {
                            return BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: (stats.hourlyActivity[i] ?? 0).toDouble(),
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF38BDF8), Color(0xFF0284C7)],
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                  ),
                                  width: 12,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(4),
                                    topRight: Radius.circular(4),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Common card widget
  Widget _buildMetricCard(
    String label,
    String val,
    IconData icon,
    Color color, {
    String? subtitle,
    double? progress,
    String? trendText,
    bool? trendIsUp,
  }) {
    return AppKpiCard(
      label: label,
      value: val,
      icon: icon,
      color: color,
      subtitle: subtitle,
      progress: progress,
      trendText: trendText,
      trendIsUp: trendIsUp,
    );
  }

  Widget _buildIndicator(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }

  Widget _buildClinicReconciliationTab(List<Sale> sales, List<Medicine> medicines) {
    final allTransfers = ObjectBoxService.instance.transferBox.getAll();

    final medMap = {for (var m in medicines) m.name.toLowerCase().trim(): m.id};

    // Map of local medicineId -> totalTransferred (to main)
    final transferMap = <int, int>{};
    for (final transfer in allTransfers) {
      final localId = medMap[transfer.medicineName.toLowerCase().trim()];
      if (localId != null) {
        if (transfer.toWarehouse == 'main') {
          transferMap[localId] = (transferMap[localId] ?? 0) + transfer.qty;
        }
        if (transfer.fromWarehouse == 'main') {
          transferMap[localId] = (transferMap[localId] ?? 0) - transfer.qty;
        }
      }
    }

    // Map of local medicineId -> totalConsumed (clinical dispenses)
    final consumeMap = <int, int>{};
    for (final sale in sales) {
      if (sale.isClinicalDispense) {
        for (final item in AnalyticsHelper.getItems(sale)) {
          if (!item.isProcedure) {
            final localId = medMap[item.medicineName.toLowerCase().trim()];
            if (localId != null) {
              consumeMap[localId] = (consumeMap[localId] ?? 0) + item.qty;
            }
          }
        }
      }
    }

    final relevantMedicineIds = <int>{};
    for (final mId in transferMap.keys) {
      relevantMedicineIds.add(mId);
    }
    for (final mId in consumeMap.keys) {
      relevantMedicineIds.add(mId);
    }
    for (final med in medicines) {
      if (med.mainStock > 0) {
        relevantMedicineIds.add(med.id);
      }
    }

    final reconciliationRows = <_ClinicReconciliationRow>[];
    for (final mId in relevantMedicineIds) {
      final med = medicines.firstWhere((m) => m.id == mId, orElse: () => Medicine(
        name: 'Unknown Medicine (ID: $mId)',
        purchasePrice: 0,
        sellingPrice: 0,
      )..id = mId);

      final totalTransferred = transferMap[mId] ?? 0;
      final totalConsumed = consumeMap[mId] ?? 0;
      final currentStock = med.mainStock;
      final expectedStock = totalTransferred - totalConsumed;
      final variance = currentStock - expectedStock;

      if (_clinicSearchQuery.isNotEmpty && !med.name.toLowerCase().contains(_clinicSearchQuery.toLowerCase())) {
        continue;
      }

      reconciliationRows.add(_ClinicReconciliationRow(
        medicineId: mId,
        medicineName: med.name,
        totalTransferred: totalTransferred,
        totalConsumed: totalConsumed,
        currentStock: currentStock,
        variance: variance,
      ));
    }

    // Sort by largest absolute variance first, then alphabetically
    reconciliationRows.sort((a, b) {
      final vComp = b.variance.abs().compareTo(a.variance.abs());
      if (vComp != 0) return vComp;
      return a.medicineName.compareTo(b.medicineName);
    });

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clinic Stock Reconciliation',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tracks stock transferred from store warehouse vs clinical dispense internal consumption.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: 320,
                child: TextField(
                  onChanged: (val) {
                    setState(() {
                      _clinicSearchQuery = val;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search clinic medicine...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Expanded(flex: 3, child: Text('Medicine Name', style: TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(flex: 2, child: Text('Total Transferred (In)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text('Total Consumed (Out)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text('Current Clinic Stock', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text('Variance', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: reconciliationRows.isEmpty
                          ? const Center(child: Text('No clinic medicines or transaction data found.'))
                          : ListView.separated(
                              itemCount: reconciliationRows.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (context, index) {
                                final row = reconciliationRows[index];

                                Color varianceColor = Colors.grey;
                                IconData? varianceIcon;
                                if (row.variance < 0) {
                                  varianceColor = AppTheme.danger;
                                  varianceIcon = Icons.warning_amber_rounded;
                                } else if (row.variance > 0) {
                                  varianceColor = AppTheme.success;
                                  varianceIcon = Icons.add_circle_outline_rounded;
                                }

                                final varianceText = row.variance > 0 ? '+${row.variance}' : '${row.variance}';

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Text(row.medicineName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text('${row.totalTransferred}', textAlign: TextAlign.center),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text('${row.totalConsumed}', textAlign: TextAlign.center),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text('${row.currentStock}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            if (varianceIcon != null) ...[
                                              Icon(varianceIcon, size: 16, color: varianceColor),
                                              const SizedBox(width: 4),
                                            ],
                                            Text(
                                              varianceText,
                                              style: TextStyle(
                                                color: varianceColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleH1RegisterTab() {
    final h1Box = ObjectBoxService.instance.store.box<ScheduleH1Record>();
    
    final now = DateTime.now();
    DateTime start;
    DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    if (_h1Period == 'Today') {
      start = DateTime(now.year, now.month, now.day);
    } else if (_h1Period == 'Yesterday') {
      final yest = now.subtract(const Duration(days: 1));
      start = DateTime(yest.year, yest.month, yest.day);
      end = DateTime(yest.year, yest.month, yest.day, 23, 59, 59);
    } else if (_h1Period == 'This Week') {
      start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    } else if (_h1Period == 'This Month') {
      start = DateTime(now.year, now.month, 1);
    } else if (_h1Period == 'Custom Range' && _h1CustomRange != null) {
      start = _h1CustomRange!.start;
      end = DateTime(_h1CustomRange!.end.year, _h1CustomRange!.end.month, _h1CustomRange!.end.day, 23, 59, 59);
    } else {
      start = DateTime(now.year, now.month, 1);
    }

    final allRecords = h1Box.getAll();
    allRecords.sort((a, b) => b.saleDate.compareTo(a.saleDate));

    final filteredRecords = allRecords.where((r) {
      final matchesDate = r.saleDate.isAfter(start.subtract(const Duration(seconds: 1))) &&
          r.saleDate.isBefore(end.add(const Duration(seconds: 1)));
      if (!matchesDate) return false;

      if (_h1SearchQuery.isEmpty) return true;
      final query = _h1SearchQuery.toLowerCase();
      return r.medicineName.toLowerCase().contains(query) ||
          r.patientName.toLowerCase().contains(query) ||
          r.doctorName.toLowerCase().contains(query) ||
          r.invoiceNo.toLowerCase().contains(query);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Schedule H1 Register',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Export Register to Excel'),
                onPressed: filteredRecords.isEmpty
                    ? null
                    : () => _exportH1ToExcel(filteredRecords),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search by medicine, patient, doctor, or invoice...',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    setState(() {
                      _h1SearchQuery = val;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              _buildPeriodSelector(
                selectedPeriod: _h1Period,
                periods: const ['Today', 'Yesterday', 'This Week', 'This Month', 'Custom Range'],
                onPeriodSelected: (p) async {
                  if (p == 'Custom Range') {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDateRange: _h1CustomRange,
                    );
                    if (range != null) {
                      setState(() {
                        _h1Period = p;
                        _h1CustomRange = range;
                      });
                    }
                  } else {
                    setState(() {
                      _h1Period = p;
                      _h1CustomRange = null;
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Expanded(flex: 2, child: Text('Date & Invoice', style: TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(flex: 3, child: Text('Drug Name & Batch', style: TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(flex: 1, child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(flex: 3, child: Text('Patient Name & Address', style: TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(flex: 3, child: Text('Doctor Name & Address (Reg No)', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filteredRecords.isEmpty
                          ? const Center(child: Text('No compliance logs found for the selected period.'))
                          : ListView.separated(
                              itemCount: filteredRecords.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (context, index) {
                                final r = filteredRecords[index];
                                final dateStr = DateFormat('dd/MM/yyyy hh:mm a').format(r.saleDate);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                            Text(r.invoiceNo, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(r.medicineName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                            Text('Batch: ${r.batchNo}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Text('${r.quantity}'),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(r.patientName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                            Text(r.patientAddress, style: const TextStyle(fontSize: 11)),
                                            if (r.patientPhone.isNotEmpty)
                                              Text('Ph: ${r.patientPhone}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Dr. ${r.doctorName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                            Text(r.doctorAddress, style: const TextStyle(fontSize: 11)),
                                            if (r.doctorRegistrationNo.isNotEmpty)
                                              Text('Reg: ${r.doctorRegistrationNo}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportH1ToExcel(List<ScheduleH1Record> records) async {
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['Schedule H1 Register'];
      excel.delete('Sheet1');

      sheet.appendRow([
        excel_pkg.TextCellValue('Date & Time'),
        excel_pkg.TextCellValue('Invoice No'),
        excel_pkg.TextCellValue('Drug Name'),
        excel_pkg.TextCellValue('Batch No'),
        excel_pkg.TextCellValue('Quantity'),
        excel_pkg.TextCellValue('Patient Name'),
        excel_pkg.TextCellValue('Patient Address'),
        excel_pkg.TextCellValue('Patient Phone'),
        excel_pkg.TextCellValue('Doctor Name'),
        excel_pkg.TextCellValue('Doctor Address'),
        excel_pkg.TextCellValue('Doctor Reg No'),
      ]);

      for (final r in records) {
        sheet.appendRow([
          excel_pkg.TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(r.saleDate)),
          excel_pkg.TextCellValue(r.invoiceNo),
          excel_pkg.TextCellValue(r.medicineName),
          excel_pkg.TextCellValue(r.batchNo),
          excel_pkg.IntCellValue(r.quantity),
          excel_pkg.TextCellValue(r.patientName),
          excel_pkg.TextCellValue(r.patientAddress),
          excel_pkg.TextCellValue(r.patientPhone),
          excel_pkg.TextCellValue(r.doctorName),
          excel_pkg.TextCellValue(r.doctorAddress),
          excel_pkg.TextCellValue(r.doctorRegistrationNo),
        ]);
      }

      final dir = await getApplicationDocumentsDirectory();
      final dateStr = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
      final file = File(p.join(dir.path, 'Schedule_H1_Register_$dateStr.xlsx'));
      final bytes = excel.encode();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Register exported successfully to: ${file.path}'),
              backgroundColor: AppTheme.success,
              action: SnackBarAction(
                label: 'Open Folder',
                textColor: Colors.white,
                onPressed: () {
                  final uri = Uri.directory(dir.path);
                  launchUrl(uri);
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export register: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }
}

class SaleRow {
  final DateTime date;
  final String invoiceNo;
  final String customer;
  final int qty;
  final double total;

  SaleRow({
    required this.date,
    required this.invoiceNo,
    required this.customer,
    required this.qty,
    required this.total,
  });
}

class ProcedurePerformance {
  final Procedure procedure;
  final int unitsSold;
  final double revenue;
  final double profit;

  ProcedurePerformance({
    required this.procedure,
    required this.unitsSold,
    required this.revenue,
    required this.profit,
  });
}

class _ClinicReconciliationRow {
  final int medicineId;
  final String medicineName;
  final int totalTransferred;
  final int totalConsumed;
  final int currentStock;
  final int variance;

  _ClinicReconciliationRow({
    required this.medicineId,
    required this.medicineName,
    required this.totalTransferred,
    required this.totalConsumed,
    required this.currentStock,
    required this.variance,
  });
}
