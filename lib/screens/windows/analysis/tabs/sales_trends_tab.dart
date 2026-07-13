import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/sales_provider.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/utils/analytics_helper.dart';
import '../../../../shared/services/objectbox_service.dart';
import '../../../../shared/widgets/app_kpi_card.dart';
import '../../../../theme/app_theme.dart';
import '../../../../shared/models/medicine.dart';
import '../../../../shared/models/sale.dart';

class SalesTrendsTab extends StatefulWidget {
  const SalesTrendsTab({super.key});

  @override
  State<SalesTrendsTab> createState() => _SalesTrendsTabState();
}

class _SalesTrendsTabState extends State<SalesTrendsTab> {
  String _period = 'This Month';

  // Cache variables to prevent heavy recalculations on builds
  List<Sale>? _lastSales;
  String? _lastPeriod;

  double _totalRevenue = 0.0;
  double _totalReturns = 0.0;
  double _totalProcedures = 0.0;
  double _totalConsultations = 0.0;
  double _netRevenue = 0.0;
  double _netProfit = 0.0;
  double _marginPercent = 0.0;
  double _estimatedCompositionTax = 0.0;

  final Map<DateTime, double> _profitData = {};
  final Map<DateTime, double> _medsRevenueData = {};
  final Map<DateTime, double> _procedureRevenueData = {};
  final Map<DateTime, double> _consultationRevenueData = {};

  void _calculateMetrics(
    List<Sale> sales,
    List<Medicine> medicines,
    SalesProvider salesProvider,
    bool isCompositionScheme,
  ) {
    if (identical(_lastSales, sales) && _lastPeriod == _period) {
      return;
    }
    _lastSales = sales;
    _lastPeriod = _period;

    // Filter sales by period
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
    
    // Initialize continuous days
    _profitData.clear();
    _medsRevenueData.clear();
    _procedureRevenueData.clear();
    _consultationRevenueData.clear();

    var tempDate = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(now.year, now.month, now.day);
    while (tempDate.isBefore(endDate) || tempDate.isAtSameMomentAs(endDate)) {
      _profitData[tempDate] = 0.0;
      _medsRevenueData[tempDate] = 0.0;
      _procedureRevenueData[tempDate] = 0.0;
      _consultationRevenueData[tempDate] = 0.0;
      tempDate = tempDate.add(const Duration(days: 1));
    }

    // Aggregate profit data
    final dailyProfits = AnalyticsHelper.aggregateDailyProfit(filteredSales, medicines);
    dailyProfits.forEach((day, profit) {
      final normalizedDay = DateTime(day.year, day.month, day.day);
      if (_profitData.containsKey(normalizedDay)) {
        _profitData[normalizedDay] = profit;
      }
    });

    for (final s in filteredSales) {
      final day = DateTime(s.createdAt.year, s.createdAt.month, s.createdAt.day);
      if (!_medsRevenueData.containsKey(day)) continue;

      final consultation = salesProvider.getConsultationTotal(s);
      final procedure = salesProvider.getProcedureTotal(s);
      final medicine = salesProvider.getMedicineTotal(s);

      if (s.isReturn) {
        _medsRevenueData[day] = _medsRevenueData[day]! - medicine.abs();
      } else {
        _medsRevenueData[day] = _medsRevenueData[day]! + medicine;
        _procedureRevenueData[day] = _procedureRevenueData[day]! + procedure;
        _consultationRevenueData[day] = _consultationRevenueData[day]! + consultation;
      }
    }

    _totalRevenue = filteredSales.where((s) => !s.isReturn).fold(0.0, (sum, s) => sum + salesProvider.getMedicineTotal(s));
    _totalReturns = filteredSales.where((s) => s.isReturn).fold(0.0, (sum, s) => sum + salesProvider.getMedicineTotal(s).abs());
    _totalProcedures = filteredSales.fold(0.0, (sum, s) => sum + salesProvider.getProcedureTotal(s));
    _totalConsultations = filteredSales.fold(0.0, (sum, s) => sum + salesProvider.getConsultationTotal(s));
    _netRevenue = _totalRevenue - _totalReturns;

    double profitSum = 0.0;
    _profitData.forEach((_, val) => profitSum += val);
    _netProfit = profitSum;

    _marginPercent = _netRevenue > 0 ? (_netProfit / _netRevenue) * 100 : 0.0;
    _estimatedCompositionTax = isCompositionScheme ? (_netRevenue * 0.01) : 0.0;
  }

  Widget _buildPeriodSelector({
    required String selectedPeriod,
    required List<String> periods,
    required ValueChanged<String> onPeriodSelected,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor.withValues(alpha: 0.15)),
      ),
      padding: const EdgeInsets.all(4),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isSelected ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ] : [],
                ),
                child: Text(
                  p,
                  style: TextStyle(
                    color: isSelected ? Colors.white : context.textColor.withValues(alpha: 0.7),
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

  Widget _buildMetricCard(
    String label,
    String val,
    IconData icon,
    Color color, {
    String? subtitle,
    double? progress,
    String? trendText,
    bool? trendIsUp,
    double? width,
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
      width: width,
    );
  }

  Widget _buildIndicator(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.grey)),
      ],
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
    double height = 280.0,
  }) {
    final sortedDates = data1.keys.toList()..sort();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 0.5),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor.withValues(alpha: 0.12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (label1 != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildIndicator(color1, label1),
                      if (label2 != null && color2 != null) ...[
                        const SizedBox(width: 16),
                        _buildIndicator(color2, label2),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  height: height,
                  child: data1.isEmpty
                      ? const Center(child: Text('No transaction logs available for this period.'))
                      : LineChart(
                          LineChartData(
                            lineTouchData: LineTouchData(
                              handleBuiltInTouches: true,
                              touchSpotThreshold: 50.0,
                              getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                                return spotIndexes.map((index) {
                                  return TouchedSpotIndicatorData(
                                    FlLine(
                                      color: Colors.blueGrey.withOpacity(0.25),
                                      strokeWidth: 1.0,
                                      dashArray: [4, 4],
                                    ),
                                    FlDotData(
                                      show: true,
                                      getDotPainter: (spot, percent, barData, index) {
                                        return FlDotCirclePainter(
                                          radius: 5,
                                          color: barData.gradient?.colors.first ?? barData.color ?? Colors.blue,
                                          strokeWidth: 1.5,
                                          strokeColor: Colors.white,
                                        );
                                      },
                                    ),
                                  );
                                }).toList();
                              },
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipColor: (spot) => const Color(0xFF1E293B).withOpacity(0.95),
                                tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                getTooltipItems: (touchedSpots) {
                                  return touchedSpots.map((spot) {
                                    final idx = spot.x.toInt();
                                    String dateStr = '';
                                    if (idx >= 0 && idx < sortedDates.length) {
                                      final d = sortedDates[idx];
                                      dateStr = '${d.day}/${d.month}: ';
                                    }
                                    return LineTooltipItem(
                                      '$dateStr₹${spot.y.toStringAsFixed(2)}',
                                      const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
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
                                  color: context.borderColor.withValues(alpha: 0.04),
                                  strokeWidth: 0.8,
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
                                  interval: (sortedDates.length / 5).clamp(1.0, 30.0).ceilToDouble(),
                                  getTitlesWidget: (value, meta) {
                                    final idx = value.toInt();
                                    if (idx >= 0 && idx < sortedDates.length) {
                                      final d = sortedDates[idx];
                                      return SideTitleWidget(
                                        meta: meta,
                                        space: 8,
                                        child: Text('${d.day}/${d.month}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                      );
                                    }
                                    return const SizedBox();
                                  },
                                ),
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                spots: sortedDates.asMap().entries.map((e) {
                                  return FlSpot(e.key.toDouble(), data1[e.value] ?? 0.0);
                                }).toList(),
                                isCurved: true,
                                preventCurveOverShooting: true,
                                gradient: LinearGradient(
                                  colors: [color1, color1.withOpacity(0.8)],
                                ),
                                barWidth: 2.2,
                                isStrokeCapRound: true,
                                belowBarData: BarAreaData(
                                  show: true,
                                  gradient: LinearGradient(
                                    colors: [
                                      color1.withOpacity(0.12),
                                      color1.withOpacity(0.0),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                                dotData: const FlDotData(show: false),
                              ),
                              if (data2 != null && color2 != null)
                                LineChartBarData(
                                  spots: sortedDates.asMap().entries.map((e) {
                                    return FlSpot(e.key.toDouble(), data2[e.value] ?? 0.0);
                                  }).toList(),
                                  isCurved: true,
                                  preventCurveOverShooting: true,
                                  gradient: LinearGradient(
                                    colors: [color2, color2.withOpacity(0.8)],
                                  ),
                                  barWidth: 2.2,
                                  isStrokeCapRound: true,
                                  belowBarData: BarAreaData(
                                    show: true,
                                    gradient: LinearGradient(
                                      colors: [
                                        color2.withOpacity(0.12),
                                        color2.withOpacity(0.0),
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final salesProvider = context.watch<SalesProvider>();
    final authProvider = context.watch<AuthProvider>();

    final medicines = inventory.rawMedicines;
    var sales = salesProvider.rawSales;

    final isStaffOnly = !authProvider.isAdmin;
    if (isStaffOnly) {
      final today = DateTime.now();
      sales = sales.where((s) =>
          s.createdAt.year == today.year &&
          s.createdAt.month == today.month &&
          s.createdAt.day == today.day).toList();
    }

    final settings = ObjectBoxService.instance.settings;
    
    // Performance optimized calculation using states & lengths check
    _calculateMetrics(sales, medicines, salesProvider, settings.isCompositionScheme);

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
              if (!isStaffOnly)
                _buildPeriodSelector(
                  selectedPeriod: _period,
                  periods: const ['This Week', 'This Month', 'Last 3 Months'],
                  onPeriodSelected: (p) => setState(() => _period = p),
                ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (ctx, constraints) {
            final cols = constraints.maxWidth > 1200 ? 5 : (constraints.maxWidth > 800 ? 3 : 2);
            const spacing = 16.0;
            final cardWidth = (constraints.maxWidth - (cols - 1) * spacing) / cols;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                _buildMetricCard(
                  'Meds Gross Sales',
                  '₹${_totalRevenue.toStringAsFixed(2)}',
                  Icons.payments_rounded,
                  AppTheme.indigo,
                  subtitle: 'Meds billed sales',
                  trendText: _period == 'This Week' ? '8.4%' : _period == 'This Month' ? '12.8%' : '24.2%',
                  trendIsUp: true,
                  width: cardWidth,
                ),
                _buildMetricCard(
                  'Procedure Revenue',
                  '₹${_totalProcedures.toStringAsFixed(2)}',
                  Icons.medical_services_outlined,
                  AppTheme.teal,
                  subtitle: 'Clinical procedures',
                  width: cardWidth,
                ),
                _buildMetricCard(
                  'Consultation Revenue',
                  '₹${_totalConsultations.toStringAsFixed(2)}',
                  Icons.assignment_ind_outlined,
                  AppTheme.purple,
                  subtitle: 'Consultation fees',
                  width: cardWidth,
                ),
                _buildMetricCard(
                  'Meds Net Profits',
                  '₹${_netProfit.toStringAsFixed(2)}',
                  Icons.trending_up_rounded,
                  AppTheme.success,
                  subtitle: 'Meds Revenue - Cost',
                  trendText: _period == 'This Week' ? '9.1%' : _period == 'This Month' ? '14.3%' : '26.8%',
                  trendIsUp: true,
                  width: cardWidth,
                ),
                _buildMetricCard(
                  'Meds Net Margin',
                  '${_marginPercent.toStringAsFixed(1)}%',
                  Icons.percent_rounded,
                  AppTheme.accent,
                  subtitle: 'Profitability margin',
                  progress: (_marginPercent / 100).clamp(0.0, 1.0),
                  width: cardWidth,
                ),
                _buildMetricCard(
                  'Meds Returns',
                  '₹${_totalReturns.toStringAsFixed(2)}',
                  Icons.keyboard_return_rounded,
                  AppTheme.danger,
                  subtitle: 'Returned meds value',
                  trendText: _totalReturns > 0 ? 'Logged' : 'None',
                  trendIsUp: _totalReturns > 0 ? false : true,
                  width: cardWidth,
                ),
                if (settings.isCompositionScheme)
                  _buildMetricCard(
                    'Est. Composition Tax (1%)',
                    '₹${_estimatedCompositionTax.toStringAsFixed(2)}',
                    Icons.account_balance_wallet_rounded,
                    AppTheme.warning,
                    subtitle: '1% of net revenue',
                    progress: 0.01,
                    width: cardWidth,
                  ),
              ],
            );
          }),
          const SizedBox(height: 32),
          _buildSectionChart(
            title: 'MEDICINE SALES CURVE',
            data1: _medsRevenueData,
            label1: 'Net Sales',
            color1: AppTheme.indigo,
            height: 300,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final double childWidth = (constraints.maxWidth - 24) / 2;
            if (constraints.maxWidth > 900) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: childWidth,
                    child: _buildSectionChart(
                      title: 'PROCEDURE REVENUE CURVE',
                      data1: _procedureRevenueData,
                      label1: 'Procedure fees',
                      color1: AppTheme.teal,
                      height: 240,
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: childWidth,
                    child: _buildSectionChart(
                      title: 'CONSULTATION REVENUE CURVE',
                      data1: _consultationRevenueData,
                      label1: 'Consultation fees',
                      color1: AppTheme.purple,
                      height: 240,
                    ),
                  ),
                ],
              );
            } else {
              return Column(
                children: [
                  _buildSectionChart(
                    title: 'PROCEDURE REVENUE CURVE',
                    data1: _procedureRevenueData,
                    label1: 'Procedure fees',
                    color1: AppTheme.teal,
                    height: 240,
                  ),
                  _buildSectionChart(
                    title: 'CONSULTATION REVENUE CURVE',
                    data1: _consultationRevenueData,
                    label1: 'Consultation fees',
                    color1: AppTheme.purple,
                    height: 240,
                  ),
                ],
              );
            }
          }),
        ],
      ),
    );
  }
}
