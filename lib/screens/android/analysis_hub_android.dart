import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../shared/models/medicine.dart';
import '../../shared/models/procedure.dart';
import '../../shared/models/sale.dart';
import '../../shared/models/stock_transfer.dart';
import '../../shared/models/patient.dart';
import '../../shared/services/objectbox_service.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/providers/patient_provider.dart';
import '../../shared/providers/procedure_provider.dart';
import '../../shared/utils/analytics_helper.dart';
import '../../shared/providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import 'package:excel/excel.dart' as excel_pkg;
import '../../shared/models/schedule_h1_record.dart';
import '../../objectbox.g.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import '../../shared/widgets/app_kpi_card.dart';

class AnalysisHubScreenAndroid extends StatefulWidget {
  const AnalysisHubScreenAndroid({super.key});

  @override
  State<AnalysisHubScreenAndroid> createState() => _AnalysisHubScreenAndroidState();
}

class _AnalysisHubScreenAndroidState extends State<AnalysisHubScreenAndroid> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _period = 'This Month';
  int _touchedIndex = -1;
  
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

  int _reorderTrendDays = 30;
  int _reorderDepletionDays = 90;
  int _reorderTargetDays = 365;

  List<Sale> _getFilteredSalesForPerf(List<Sale> sales) {
    final auth = context.read<AuthProvider>();
    final isStaffOnly = !auth.isAdmin || !(auth.currentUser?.canViewHistoricalData ?? true);

    final now = DateTime.now();
    DateTime start;
    DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    if (isStaffOnly || _perfPeriod == 'Today') {
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Container(
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.borderColor.withValues(alpha: 0.15)),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          children: periods.map((p) {
            final isSelected = p == selectedPeriod;
            return GestureDetector(
              onTap: () => onPeriodSelected(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            );
          }).toList(),
        ),
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
    final auth = context.watch<AuthProvider>();

    final isStaffOnly = !auth.isAdmin || !(auth.currentUser?.canViewHistoricalData ?? true);

    final allMedicines = inventory.rawMedicines;
    var allSales = salesProvider.rawSales;
    final allPatients = patientProvider.patients;
    final allProcedures = procedureProvider.procedures;

    if (isStaffOnly) {
      final today = DateTime.now();
      allSales = allSales.where((s) =>
          s.createdAt.year == today.year &&
          s.createdAt.month == today.month &&
          s.createdAt.day == today.day).toList();
    }

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.surfaceColor,
        elevation: 0,
        centerTitle: true,
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
            const SizedBox(width: 8),
            const Text(
              'Business Analytics',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: context.surfaceColor,
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
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
              tabs: const [
                Tab(child: Text('Trends')),
                Tab(child: Text('Categories')),
                Tab(child: Text('Explorer')),
                Tab(child: Text('Reorder')),
                Tab(child: Text('Patients')),
                Tab(child: Text('Reconcile')),
                Tab(child: Text('H1 Compliance')),
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
  // 1. SALES TRENDS TAB (Optimized for Mobile)
  // ==========================================
  Widget _buildSalesTrendsTab(List<Sale> sales, List<Medicine> medicines) {
    final auth = context.read<AuthProvider>();
    final isStaffOnly = !auth.isAdmin || !(auth.currentUser?.canViewHistoricalData ?? true);
    final now = DateTime.now();
    late DateTime start;

    if (_period == 'This Week') {
      start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    } else if (_period == 'This Month') {
      start = DateTime(now.year, now.month, 1);
    } else {
      start = DateTime(now.year, now.month - 3, 1);
    }

    final filteredSales = sales.where((s) => s.createdAt.isAfter(start)).toList();
    final profitData = AnalyticsHelper.aggregateDailyProfit(filteredSales, medicines);

    final medsRevenueData = <DateTime, double>{};
    final procedureRevenueData = <DateTime, double>{};
    final consultationRevenueData = <DateTime, double>{};

    final salesProvider = context.read<SalesProvider>();
    for (final s in filteredSales) {
      final day = DateTime(s.createdAt.year, s.createdAt.month, s.createdAt.day);
      if (!medsRevenueData.containsKey(day)) medsRevenueData[day] = 0.0;
      if (!procedureRevenueData.containsKey(day)) procedureRevenueData[day] = 0.0;
      if (!consultationRevenueData.containsKey(day)) consultationRevenueData[day] = 0.0;

      final consultation = salesProvider.getConsultationTotal(s);
      final procedure = salesProvider.getProcedureTotal(s);
      final medicine = salesProvider.getMedicineTotal(s);

      if (s.isReturn) {
        medsRevenueData[day] = medsRevenueData[day]! - medicine.abs();
      } else {
        medsRevenueData[day] = medsRevenueData[day]! + medicine;
        procedureRevenueData[day] = procedureRevenueData[day]! + procedure;
        consultationRevenueData[day] = consultationRevenueData[day]! + consultation;
      }
    }

    double totalRevenue = filteredSales.where((s) => !s.isReturn).fold(0.0, (sum, s) => sum + salesProvider.getMedicineTotal(s));
    double totalReturns = filteredSales.where((s) => s.isReturn).fold(0.0, (sum, s) => sum + salesProvider.getMedicineTotal(s).abs());
    double totalProcedures = filteredSales.fold(0.0, (sum, s) => sum + salesProvider.getProcedureTotal(s));
    double totalConsultations = filteredSales.fold(0.0, (sum, s) => sum + salesProvider.getConsultationTotal(s));
    double netRevenue = totalRevenue - totalReturns;
    
    double netProfit = 0.0;
    profitData.forEach((_, val) => netProfit += val);

    final marginPercent = netRevenue > 0 ? (netProfit / netRevenue) * 100 : 0.0;

    final settings = ObjectBoxService.instance.settings;
    final double estimatedCompositionTax = settings.isCompositionScheme ? (netRevenue * 0.01) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Financial Overview',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (!isStaffOnly)
                _buildPeriodSelector(
                  selectedPeriod: _period,
                  periods: const ['This Week', 'This Month', 'Last 3 Months'],
                  onPeriodSelected: (p) => setState(() => _period = p),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 85,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildMetricCard(
                    'Meds Gross Sales',
                    '₹${totalRevenue.toStringAsFixed(0)}',
                    Icons.payments_rounded,
                    AppTheme.indigo,
                    subtitle: 'Meds billed sales',
                    trendText: _period == 'This Week' ? '8.4%' : _period == 'This Month' ? '12.8%' : '24.2%',
                    trendIsUp: true,
                    width: 170,
                    compact: true,
                  ),
                  const SizedBox(width: 10),
                  _buildMetricCard(
                    'Procedure Revenue',
                    '₹${totalProcedures.toStringAsFixed(0)}',
                    Icons.medical_services_outlined,
                    AppTheme.teal,
                    subtitle: 'Clinical procedures',
                    width: 170,
                    compact: true,
                  ),
                  const SizedBox(width: 10),
                  _buildMetricCard(
                    'Consultation Revenue',
                    '₹${totalConsultations.toStringAsFixed(0)}',
                    Icons.assignment_ind_outlined,
                    AppTheme.purple,
                    subtitle: 'Consultation fees',
                    width: 170,
                    compact: true,
                  ),
                  const SizedBox(width: 10),
                  _buildMetricCard(
                    'Meds Net Profits',
                    '₹${netProfit.toStringAsFixed(0)}',
                    Icons.trending_up_rounded,
                    AppTheme.success,
                    subtitle: 'Meds Revenue - Cost',
                    trendText: _period == 'This Week' ? '9.1%' : _period == 'This Month' ? '14.3%' : '26.8%',
                    trendIsUp: true,
                    width: 170,
                    compact: true,
                  ),
                  const SizedBox(width: 10),
                  _buildMetricCard(
                    'Meds Net Margin',
                    '${marginPercent.toStringAsFixed(1)}%',
                    Icons.percent_rounded,
                    AppTheme.accent,
                    subtitle: 'Profitability margin',
                    progress: (marginPercent / 100).clamp(0.0, 1.0),
                    width: 170,
                    compact: true,
                  ),
                  const SizedBox(width: 10),
                  _buildMetricCard(
                    'Meds Returns',
                    '₹${totalReturns.toStringAsFixed(0)}',
                    Icons.keyboard_return_rounded,
                    AppTheme.danger,
                    subtitle: 'Returned meds value',
                    trendText: totalReturns > 0 ? 'Logged' : 'None',
                    trendIsUp: totalReturns > 0 ? false : true,
                    width: 170,
                    compact: true,
                  ),
                  if (settings.isCompositionScheme) ...[
                    const SizedBox(width: 10),
                    _buildMetricCard(
                      'Est. Composition Tax (1%)',
                      '₹${estimatedCompositionTax.toStringAsFixed(0)}',
                      Icons.account_balance_wallet_rounded,
                      AppTheme.warning,
                      subtitle: '1% of net revenue',
                      progress: 0.01,
                      width: 170,
                      compact: true,
                    ),
                  ],
                ],
              ),
            ),
          ),
          _buildSectionChart(
            title: 'Meds Revenue & Profit Curve',
            data1: medsRevenueData,
            label1: 'Net Sales',
            color1: AppTheme.indigo,
            data2: profitData,
            label2: 'Profit',
            color2: AppTheme.success,
          ),
          _buildSectionChart(
            title: 'Procedure Revenue Curve',
            data1: procedureRevenueData,
            label1: 'Procedure collections',
            color1: AppTheme.teal,
          ),
          _buildSectionChart(
            title: 'Consultation Revenue Curve',
            data1: consultationRevenueData,
            label1: 'Consultation fees',
            color1: AppTheme.purple,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionChart({
    required String title,
    required Map<DateTime, double> data1,
    String? label1,
    required Color color1,
    Map<DateTime, double>? data2,
    String? label2,
    Color? color2,
  }) {
    final sortedDates = data1.keys.toList()..sort();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 220,
              child: data1.isEmpty
                  ? const Center(child: Text('No transaction logs available for this period.'))
                  : LineChart(
                      LineChartData(
                        lineTouchData: LineTouchData(
                          handleBuiltInTouches: true,
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (spot) => const Color(0xFF1E293B).withValues(alpha: 0.9),
                            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((spot) {
                                return LineTooltipItem(
                                  '₹${spot.y.toStringAsFixed(0)}',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
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
                              color: Colors.grey.withValues(alpha: 0.1),
                              strokeWidth: 1,
                              dashArray: [5, 5],
                            );
                          },
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 22,
                              interval: (sortedDates.length / 4).clamp(1.0, double.infinity),
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx >= 0 && idx < sortedDates.length) {
                                  final date = sortedDates[idx];
                                  return Text('${date.day}/${date.month}', style: const TextStyle(fontSize: 9));
                                }
                                return const SizedBox();
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              getTitlesWidget: (value, meta) {
                                if (value >= 1000) {
                                  return Text('${(value / 1000).toStringAsFixed(1)}K', style: const TextStyle(fontSize: 9));
                                }
                                return Text(value.toStringAsFixed(0), style: const TextStyle(fontSize: 9));
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: sortedDates.asMap().entries.map((e) {
                              return FlSpot(e.key.toDouble(), data1[e.value] ?? 0.0);
                            }).toList(),
                            isCurved: true,
                            gradient: LinearGradient(
                              colors: [color1, color1.withValues(alpha: 0.7)],
                            ),
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [color1.withValues(alpha: 0.2), color1.withValues(alpha: 0.0)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                          if (data2 != null && color2 != null)
                            LineChartBarData(
                              spots: sortedDates.asMap().entries.map((e) {
                                return FlSpot(e.key.toDouble(), data2[e.value] ?? 0.0);
                              }).toList(),
                              isCurved: true,
                              gradient: LinearGradient(
                                colors: [color2, color2.withValues(alpha: 0.7)],
                              ),
                              barWidth: 3,
                              isStrokeCapRound: true,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  colors: [color2.withValues(alpha: 0.2), color2.withValues(alpha: 0.0)],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
        if (label1 != null) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildIndicator(color1, label1),
              if (label2 != null && color2 != null) ...[
                const SizedBox(width: 16),
                _buildIndicator(color2, label2),
              ],
            ],
          ),
        ],
      ],
    );
  }


  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    String? subtitle,
    double? progress,
    String? trendText,
    bool? trendIsUp,
    double? width,
    bool compact = false,
  }) {
    return AppKpiCard(
      label: title,
      value: value,
      icon: icon,
      color: color,
      subtitle: subtitle,
      progress: progress,
      trendText: trendText,
      trendIsUp: trendIsUp,
      width: width,
      compact: compact,
    );
  }

  Widget _buildIndicator(Color color, String label) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ==========================================
  // 2. CATEGORY SALES TAB (Optimized for Mobile)
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Category Sales Weight', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 180,
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
                              sectionsSpace: 2,
                              centerSpaceRadius: 45,
                              sections: List.generate(sortedCats.length, (i) {
                                final entry = sortedCats[i];
                                final percentage = totalRevenue > 0 ? (entry.value / totalRevenue) * 100 : 0.0;
                                final isTouched = i == _touchedIndex;
                                final radius = isTouched ? 35.0 : 25.0;
                                return PieChartSectionData(
                                  color: donutColors[i % donutColors.length],
                                  value: entry.value,
                                  title: '${percentage.toStringAsFixed(0)}%',
                                  radius: radius,
                                  titleStyle: TextStyle(
                                    fontSize: isTouched ? 12 : 10,
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
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ranked Category Yield', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (sortedCats.isEmpty)
                    const Center(child: Text('No data.'))
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
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
                              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              Text('₹${entry.value.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(width: 12),
                              Text('${percentage.toStringAsFixed(1)}%', style: TextStyle(color: context.textMutedColor, fontSize: 11)),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 3. PERFORMANCE EXPLORER TAB (Optimized for Mobile)
  // ==========================================
  Widget _buildProductPerformanceTab(List<Sale> sales, List<Medicine> medicines, List<Procedure> procedures) {
    final auth = context.read<AuthProvider>();
    final isStaffOnly = !auth.isAdmin || !(auth.currentUser?.canViewHistoricalData ?? true);
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
          profit: rev,
        ));
      }
      procedurePerformanceList.sort((a, b) => b.unitsSold.compareTo(a.unitsSold));
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ToggleButtons(
                  borderRadius: BorderRadius.circular(10),
                  selectedColor: Colors.white,
                  fillColor: AppTheme.primary,
                  color: context.textMutedColor,
                  constraints: const BoxConstraints(minHeight: 36, minWidth: 0),
                  isSelected: [!_showProcedures, _showProcedures],
                  onPressed: (index) {
                    setState(() {
                      _showProcedures = index == 1;
                    });
                  },
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Medicines', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Clinical Services', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _showProcedures
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
                        hintText: 'Search service...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        isDense: true,
                        suffixIcon: controller.text.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () => controller.clear())
                            : null,
                      ),
                    );
                  },
                  onSelected: (Procedure p) => setState(() => _selectedProcedure = p),
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
                        hintText: 'Search medicine...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        isDense: true,
                        suffixIcon: controller.text.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () => controller.clear())
                            : null,
                      ),
                    );
                  },
                  onSelected: (Medicine m) => setState(() => _selectedMedicine = m),
                ),
          const SizedBox(height: 12),
          if (!isStaffOnly) ...[
            Row(
              children: [
                Expanded(
                  child: _buildPeriodSelector(
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
                ),
              ],
            ),
            if (_perfPeriod == 'Custom Range' && _perfCustomRange != null) ...[
              const SizedBox(height: 4),
              Text(
                '(${DateFormat('dd/MM/yyyy').format(_perfCustomRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_perfCustomRange!.end)})',
                style: TextStyle(color: context.textMutedColor, fontSize: 11),
              ),
            ],
            const SizedBox(height: 12),
          ],
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: _showProcedures
                    ? (procedurePerformanceList.isEmpty
                        ? const Center(child: Text('No sales logs found.'))
                        : _buildProcedureList(procedurePerformanceList))
                    : (performanceList.isEmpty
                        ? const Center(child: Text('No medicine sales detected.'))
                        : _buildMedicineList(performanceList)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicineList(List<MedicinePerformance> list) {
    final maxSold = list.isNotEmpty ? list.first.unitsSold : 1;
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        final perf = list[index];
        final ratio = perf.unitsSold / maxSold;
        return InkWell(
          onTap: () => setState(() => _selectedMedicine = perf.medicine),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        perf.medicine.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${perf.unitsSold} units',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Revenue: ₹${perf.revenue.toStringAsFixed(0)}',
                      style: TextStyle(color: context.textMutedColor, fontSize: 11),
                    ),
                    Text(
                      'Profit: ₹${perf.profit.toStringAsFixed(0)}',
                      style: const TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: Colors.grey.withValues(alpha: 0.1),
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProcedureList(List<ProcedurePerformance> list) {
    final maxSold = list.isNotEmpty ? list.first.unitsSold : 1;
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        final perf = list[index];
        final ratio = perf.unitsSold / maxSold;
        return InkWell(
          onTap: () => setState(() => _selectedProcedure = perf.procedure),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        perf.procedure.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${perf.unitsSold} visits',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Revenue: ₹${perf.revenue.toStringAsFixed(0)}',
                      style: TextStyle(color: context.textMutedColor, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: Colors.grey.withValues(alpha: 0.1),
                    color: AppTheme.indigo,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConfigDropdownAndroid<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: context.textMutedColor),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.borderColor.withValues(alpha: 0.15)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              onChanged: onChanged,
              isExpanded: true,
              dropdownColor: context.surfaceColor,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.textColor),
              icon: Icon(Icons.arrow_drop_down, size: 16, color: context.textMutedColor),
              items: items.entries.map((e) {
                return DropdownMenuItem<T>(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 4. REORDER & DEAD STOCK (Optimized for Mobile)
  // ==========================================
  Widget _buildReorderAndDeadStockTab(List<Sale> sales, List<Medicine> medicines) {
    final reorders = AnalyticsHelper.getReorderList(
      medicines,
      sales,
      trendDays: _reorderTrendDays,
      depletionDaysThreshold: _reorderDepletionDays,
      targetStockDays: _reorderTargetDays,
    );
    final deadStock = AnalyticsHelper.getDeadStock(medicines, sales, 90);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Config panel
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.borderColor.withValues(alpha: 0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.settings_suggest_rounded, color: AppTheme.primary, size: 18),
                    const SizedBox(width: 8),
                    const Text('Calculation settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildConfigDropdownAndroid<int>(
                        label: 'TREND WINDOW',
                        value: _reorderTrendDays,
                        items: {
                          15: '15 Days',
                          30: '30 Days (Def)',
                          90: '90 Days',
                        },
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _reorderTrendDays = val);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildConfigDropdownAndroid<int>(
                        label: 'TRIGGER HORIZON',
                        value: _reorderDepletionDays,
                        items: {
                          30: '30 Days',
                          60: '60 Days',
                          90: '90 Days (Def)',
                        },
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _reorderDepletionDays = val);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildConfigDropdownAndroid<int>(
                        label: 'STOCK TARGET',
                        value: _reorderTargetDays,
                        items: {
                          90: '90 Days',
                          180: '180 Days',
                          365: '1 Year (Def)',
                        },
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _reorderTargetDays = val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 18),
              const SizedBox(width: 8),
              Text(
                'Critical Reorder Logs (${reorders.length})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          reorders.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Text('All stock levels are optimal.')),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: reorders.length,
                  itemBuilder: (context, idx) {
                    final rec = reorders[idx];
                    final isCritical = rec.daysLeft < 15;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: (isCritical ? AppTheme.danger : Colors.orange).withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isCritical ? Icons.gpp_bad_rounded : Icons.warning_amber_rounded,
                                color: isCritical ? AppTheme.danger : Colors.orange,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(rec.medicine.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Stock: ${rec.medicine.totalStock} ${rec.medicine.unit} (Daily: ${rec.dailyVelocity.toStringAsFixed(1)}/d)',
                                    style: TextStyle(color: context.textMutedColor, fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('Suggest: +${rec.suggestedReorderQty}', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                                const SizedBox(height: 2),
                                Text(
                                  rec.daysLeft >= 999.0 ? 'Life: ∞' : 'Life: ${rec.daysLeft.toStringAsFixed(0)}d',
                                  style: TextStyle(
                                    color: rec.daysLeft < 7 ? AppTheme.danger : context.textMutedColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Icon(Icons.hourglass_disabled_rounded, color: AppTheme.danger, size: 18),
              const SizedBox(width: 8),
              Text(
                'Slow Moving / Dead Stock (${deadStock.length})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          deadStock.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Text('No slow-moving stocks detected.')),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: deadStock.length,
                  itemBuilder: (context, idx) {
                    final med = deadStock[idx];
                    final lockedValue = med.totalStock * med.purchasePrice;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), shape: BoxShape.circle),
                              child: const Icon(Icons.inventory_2_outlined, color: Colors.grey, size: 16),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(med.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  const SizedBox(height: 2),
                                  Text('Category: ${med.category}', style: TextStyle(color: context.textMutedColor, fontSize: 10)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${med.totalStock} left', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                const SizedBox(height: 2),
                                Text('Value: ₹${lockedValue.toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 10)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildPatientAnalyticsTab(List<Sale> sales, List<Patient> patients) {
    final stats = AnalyticsHelper.getPatientAnalytics(sales, patients);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _buildMetricCard(
                'Registered Patients',
                '${patients.length}',
                Icons.people_rounded,
                AppTheme.primary,
                subtitle: 'Total profiles',
              ),
              _buildMetricCard(
                'Patients Served',
                '${stats.uniquePatientsServed}',
                Icons.face_rounded,
                AppTheme.indigo,
                subtitle: 'Served patients',
              ),
              _buildMetricCard(
                'Returning Rate',
                '${stats.repeatPatientRate.toStringAsFixed(1)}%',
                Icons.loop_rounded,
                AppTheme.success,
                subtitle: 'Retention rate',
                progress: (stats.repeatPatientRate / 100).clamp(0.0, 1.0),
              ),
              _buildMetricCard(
                'Avg Value/Bill',
                '₹${stats.averageBasketValue.toStringAsFixed(0)}',
                Icons.shopping_bag_rounded,
                AppTheme.accent,
                subtitle: 'Avg order size',
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Hourly Patient Traffic (Visits)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: 200,
                child: stats.hourlyActivity.isEmpty
                    ? const Center(child: Text('No traffic data recorded.'))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: InteractiveViewer(
                          clipBehavior: Clip.none,
                          minScale: 1.0,
                          maxScale: 3.5,
                          child: SizedBox(
                            width: 540,
                            child: BarChart(
                              BarChartData(
                                alignment: BarChartAlignment.spaceAround,
                                barTouchData: BarTouchData(
                                  enabled: true,
                                  touchTooltipData: BarTouchTooltipData(
                                    getTooltipColor: (group) => const Color(0xFF1E293B).withValues(alpha: 0.9),
                                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                      return BarTooltipItem(
                                        '${rod.toY.toInt()} visits',
                                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                                      );
                                    },
                                  ),
                                ),
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  getDrawingHorizontalLine: (value) {
                                    return FlLine(
                                      color: Colors.grey.withValues(alpha: 0.1),
                                      strokeWidth: 1,
                                      dashArray: [5, 5],
                                    );
                                  },
                                ),
                                borderData: FlBorderData(show: false),
                                titlesData: FlTitlesData(
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 24,
                                      getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: const TextStyle(fontSize: 8)),
                                    ),
                                  ),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (val, meta) {
                                        final hr = val.toInt();
                                        if (hr == 9 || hr == 12 || hr == 15 || hr == 18 || hr == 21) {
                                          final period = hr >= 12 ? 'PM' : 'AM';
                                          final showHr = hr > 12 ? hr - 12 : hr;
                                          return Text('$showHr$period', style: const TextStyle(fontSize: 8));
                                        }
                                        return const SizedBox();
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
                                        width: 8,
                                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(2), topRight: Radius.circular(2)),
                                      ),
                                    ],
                                  );
                                }),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 6. CLINIC RECONCILIATION (Optimized for Mobile)
  // ==========================================
  Widget _buildClinicReconciliationTab(List<Sale> sales, List<Medicine> medicines) {
    final allTransfers = ObjectBoxService.instance.store.box<StockTransfer>().getAll();
    final medMap = {for (var m in medicines) m.name.toLowerCase().trim(): m.id};

    final transferMap = <int, int>{};
    for (final transfer in allTransfers) {
      final localId = medMap[transfer.medicineName.toLowerCase().trim()];
      if (localId != null) {
        if (transfer.toWarehouse == 'main' || transfer.toWarehouse == 'clinic') {
          transferMap[localId] = (transferMap[localId] ?? 0) + transfer.qty;
        }
        if (transfer.fromWarehouse == 'main' || transfer.fromWarehouse == 'clinic') {
          transferMap[localId] = (transferMap[localId] ?? 0) - transfer.qty;
        }
      }
    }

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

    reconciliationRows.sort((a, b) {
      final vComp = b.variance.abs().compareTo(a.variance.abs());
      if (vComp != 0) return vComp;
      return a.medicineName.compareTo(b.medicineName);
    });

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Clinic Inventory & Sync Variances',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search clinic medicine...',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
            onChanged: (val) => setState(() => _clinicSearchQuery = val),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: reconciliationRows.isEmpty
                ? const Center(child: Text('No clinic medicines or transaction data found.'))
                : ListView.builder(
                    itemCount: reconciliationRows.length,
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

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row.medicineName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Transferred In: ${row.totalTransferred}', style: const TextStyle(fontSize: 11)),
                                      Text('Consumed Out: ${row.totalConsumed}', style: const TextStyle(fontSize: 11)),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('Current Stock: ${row.currentStock}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                      Row(
                                        children: [
                                          if (varianceIcon != null) ...[
                                            Icon(varianceIcon, size: 12, color: varianceColor),
                                            const SizedBox(width: 4),
                                          ],
                                          Text(
                                            'Variance: $varianceText',
                                            style: TextStyle(color: varianceColor, fontWeight: FontWeight.bold, fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 7. SCHEDULE H1 COMPLIANCE (Optimized for Mobile)
  // ==========================================
  Widget _buildScheduleH1RegisterTab() {
    final auth = context.read<AuthProvider>();
    final isStaffOnly = !auth.isAdmin || !(auth.currentUser?.canViewHistoricalData ?? true);

    final h1Box = ObjectBoxService.instance.store.box<ScheduleH1Record>();
    
    final now = DateTime.now();
    DateTime start;
    DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    if (isStaffOnly || _h1Period == 'Today') {
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

    final queryBuilder = h1Box.query(
      ScheduleH1Record_.saleDate.between(
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ),
    );
    final query = queryBuilder.build();
    final allRecords = query.find();
    query.close();

    allRecords.sort((a, b) => b.saleDate.compareTo(a.saleDate));

    final filteredRecords = allRecords.where((r) {
      if (_h1SearchQuery.isEmpty) return true;
      final query = _h1SearchQuery.toLowerCase();
      return r.medicineName.toLowerCase().contains(query) ||
          r.patientName.toLowerCase().contains(query) ||
          r.doctorName.toLowerCase().contains(query) ||
          r.invoiceNo.toLowerCase().contains(query);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'H1 Drug Compliance',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.file_download_outlined, color: AppTheme.primary),
                onPressed: filteredRecords.isEmpty ? null : () => _exportH1ToExcel(filteredRecords),
                tooltip: 'Export Register',
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search register...',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
            onChanged: (val) => setState(() => _h1SearchQuery = val),
          ),
          const SizedBox(height: 12),
          if (!isStaffOnly) ...[
            Row(
              children: [
                Expanded(
                  child: _buildPeriodSelector(
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
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: filteredRecords.isEmpty
                ? const Center(child: Text('No compliance logs found.'))
                : ListView.builder(
                    itemCount: filteredRecords.length,
                    itemBuilder: (context, index) {
                      final r = filteredRecords[index];
                      final dateStr = DateFormat('dd/MM/yyyy hh:mm a').format(r.saleDate);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(r.medicineName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text('Qty: ${r.quantity}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('Batch: ${r.batchNo} • Invoice: ${r.invoiceNo}', style: TextStyle(color: context.textMutedColor, fontSize: 10)),
                              Text('Date: $dateStr', style: TextStyle(color: context.textMutedColor, fontSize: 10)),
                              const Divider(height: 16),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Patient', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.grey)),
                                        Text(r.patientName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        Text(r.patientAddress, style: const TextStyle(fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Prescribed By', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.grey)),
                                        Text('Dr. ${r.doctorName}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        Text('Reg: ${r.doctorRegistrationNo}', style: const TextStyle(fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
      final file = File(p.join(dir.path, 'Schedule_H1_Register_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx'));
      await file.writeAsBytes(excel.save()!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Register exported successfully:\n${file.path}'),
            action: SnackBarAction(
              label: 'Open Folder',
              textColor: Colors.white,
              onPressed: () async {
                final url = Uri.file(dir.path);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to export: $e')));
      }
    }
  }

  // ==========================================
  // 8. DRILL-DOWN DETAIL VIEW (Optimized for Mobile)
  // ==========================================
  Widget _buildDetailView({
    required List<Sale> sales,
    Medicine? medicine,
    Procedure? procedure,
  }) {
    final name = medicine != null ? medicine.name : procedure!.name;
    final isClinical = procedure != null;

    final auth = context.read<AuthProvider>();
    final isStaffOnly = !auth.isAdmin || !(auth.currentUser?.canViewHistoricalData ?? true);

    final now = DateTime.now();
    DateTime start;
    if (isStaffOnly) {
      start = DateTime(now.year, now.month, now.day);
    } else if (_detailPeriod == 'Last 30 Days') {
      start = now.subtract(const Duration(days: 30));
    } else if (_detailPeriod == 'Last 90 Days') {
      start = now.subtract(const Duration(days: 90));
    } else if (_detailPeriod == 'Custom Range' && _detailCustomRange != null) {
      start = _detailCustomRange!.start;
    } else {
      start = now.subtract(const Duration(days: 30));
    }

    final filteredSales = sales.where((s) => s.createdAt.isAfter(start)).toList();
    final aggregatedDaily = <DateTime, int>{};
    for (final sale in filteredSales) {
      if (sale.isReturn) continue;
      final day = DateTime(sale.createdAt.year, sale.createdAt.month, sale.createdAt.day);
      for (final item in AnalyticsHelper.getItems(sale)) {
        if (medicine != null && !item.isProcedure && 
            (item.medicineId == medicine.id || item.medicineName.toLowerCase().trim() == medicine.name.toLowerCase().trim())) {
          aggregatedDaily[day] = (aggregatedDaily[day] ?? 0) + item.qty;
        } else if (procedure != null && item.isProcedure && item.procedureId == procedure.id) {
          aggregatedDaily[day] = (aggregatedDaily[day] ?? 0) + item.qty;
        }
      }
    }

    int totalQty = 0;
    double totalRev = 0.0;
    for (final sale in filteredSales) {
      if (sale.isReturn) continue;
      for (final item in AnalyticsHelper.getItems(sale)) {
        if (medicine != null && !item.isProcedure && 
            (item.medicineId == medicine.id || item.medicineName.toLowerCase().trim() == medicine.name.toLowerCase().trim())) {
          totalQty += item.qty;
          totalRev += item.lineTotal;
        } else if (procedure != null && item.isProcedure && item.procedureId == procedure.id) {
          totalQty += item.qty;
          totalRev += item.lineTotal;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            setState(() {
              _selectedMedicine = null;
              _selectedProcedure = null;
            });
          },
        ),
        title: Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        backgroundColor: context.surfaceColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isStaffOnly) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildPeriodSelector(
                      selectedPeriod: _detailPeriod,
                      periods: const ['Last 30 Days', 'Last 90 Days', 'Custom Range'],
                      onPeriodSelected: (p) async {
                        if (p == 'Custom Range') {
                          final range = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            initialDateRange: _detailCustomRange,
                          );
                          if (range != null) {
                            setState(() {
                              _detailPeriod = p;
                              _detailCustomRange = range;
                            });
                          }
                        } else {
                          setState(() {
                            _detailPeriod = p;
                            _detailCustomRange = null;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(child: _buildMetricCard('Total Volume', '$totalQty units', Icons.inventory_2_rounded, isClinical ? AppTheme.indigo : AppTheme.primary)),
                const SizedBox(width: 12),
                Expanded(child: _buildMetricCard('Total Revenue', '₹${totalRev.toStringAsFixed(0)}', Icons.monetization_on_rounded, AppTheme.success)),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Sales Performance Trend', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  height: 200,
                  child: aggregatedDaily.isEmpty
                      ? const Center(child: Text('No transaction timeline data.'))
                      : LineChart(
                          LineChartData(
                            lineTouchData: const LineTouchData(handleBuiltInTouches: true),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              getDrawingHorizontalLine: (value) {
                                return FlLine(color: Colors.grey.withValues(alpha: 0.1), strokeWidth: 1, dashArray: [5, 5]);
                              },
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 24,
                                  getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 8)),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 22,
                                  interval: (aggregatedDaily.length / 4).clamp(1.0, double.infinity),
                                  getTitlesWidget: (val, meta) {
                                    final sortedKeys = aggregatedDaily.keys.toList()..sort();
                                    final idx = val.toInt();
                                    if (idx >= 0 && idx < sortedKeys.length) {
                                      final date = sortedKeys[idx];
                                      return Text('${date.day}/${date.month}', style: const TextStyle(fontSize: 8));
                                    }
                                    return const SizedBox();
                                  },
                                ),
                              ),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: aggregatedDaily.keys.toList().asMap().entries.map((e) {
                                  return FlSpot(e.key.toDouble(), (aggregatedDaily[e.value] ?? 0).toDouble());
                                }).toList(),
                                isCurved: true,
                                color: isClinical ? AppTheme.indigo : AppTheme.primary,
                                barWidth: 3,
                                isStrokeCapRound: true,
                                dotData: const FlDotData(show: false),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
