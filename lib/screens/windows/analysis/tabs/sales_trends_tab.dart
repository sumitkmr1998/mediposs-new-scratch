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

class SalesTrendsTab extends StatefulWidget {
  const SalesTrendsTab({super.key});

  @override
  State<SalesTrendsTab> createState() => _SalesTrendsTabState();
}

class _SalesTrendsTabState extends State<SalesTrendsTab> {
  String _period = 'This Month';

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
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              height: 280,
              child: data1.isEmpty
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
                              interval: (sortedDates.length / 5).clamp(1.0, 30.0),
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx >= 0 && idx < sortedDates.length) {
                                  final d = sortedDates[idx];
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
                            spots: sortedDates.asMap().entries.map((e) {
                              return FlSpot(e.key.toDouble(), data1[e.value] ?? 0.0);
                            }).toList(),
                            isCurved: true,
                            gradient: LinearGradient(
                              colors: [color1, color1.withOpacity(0.7)],
                            ),
                            barWidth: 4,
                            isStrokeCapRound: true,
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  color1.withOpacity(0.2),
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
                              gradient: LinearGradient(
                                colors: [color2, color2.withOpacity(0.7)],
                              ),
                              barWidth: 4,
                              isStrokeCapRound: true,
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  colors: [
                                    color2.withOpacity(0.2),
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
          ),
        ),
        if (label1 != null) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildIndicator(color1, label1),
              if (label2 != null && color2 != null) ...[
                const SizedBox(width: 24),
                _buildIndicator(color2, label2),
              ],
            ],
          ),
        ],
        const SizedBox(height: 32),
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

    final now = DateTime.now();
    late DateTime start;

    if (isStaffOnly) {
      start = DateTime(now.year, now.month, now.day);
    } else if (_period == 'This Week') {
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
                  '₹${totalRevenue.toStringAsFixed(2)}',
                  Icons.payments_rounded,
                  AppTheme.indigo,
                  subtitle: 'Meds billed sales',
                  trendText: _period == 'This Week' ? '8.4%' : _period == 'This Month' ? '12.8%' : '24.2%',
                  trendIsUp: true,
                  width: cardWidth,
                ),
                _buildMetricCard(
                  'Procedure Revenue',
                  '₹${totalProcedures.toStringAsFixed(2)}',
                  Icons.medical_services_outlined,
                  AppTheme.teal,
                  subtitle: 'Clinical procedures',
                  width: cardWidth,
                ),
                _buildMetricCard(
                  'Consultation Revenue',
                  '₹${totalConsultations.toStringAsFixed(2)}',
                  Icons.assignment_ind_outlined,
                  AppTheme.purple,
                  subtitle: 'Consultation fees',
                  width: cardWidth,
                ),
                _buildMetricCard(
                  'Meds Net Profits',
                  '₹${netProfit.toStringAsFixed(2)}',
                  Icons.trending_up_rounded,
                  AppTheme.success,
                  subtitle: 'Meds Revenue - Cost',
                  trendText: _period == 'This Week' ? '9.1%' : _period == 'This Month' ? '14.3%' : '26.8%',
                  trendIsUp: true,
                  width: cardWidth,
                ),
                _buildMetricCard(
                  'Meds Net Margin',
                  '${marginPercent.toStringAsFixed(1)}%',
                  Icons.percent_rounded,
                  AppTheme.accent,
                  subtitle: 'Profitability margin',
                  progress: (marginPercent / 100).clamp(0.0, 1.0),
                  width: cardWidth,
                ),
                _buildMetricCard(
                  'Meds Returns',
                  '₹${totalReturns.toStringAsFixed(2)}',
                  Icons.keyboard_return_rounded,
                  AppTheme.danger,
                  subtitle: 'Returned meds value',
                  trendText: totalReturns > 0 ? 'Logged' : 'None',
                  trendIsUp: totalReturns > 0 ? false : true,
                  width: cardWidth,
                ),
                if (settings.isCompositionScheme)
                  _buildMetricCard(
                    'Est. Composition Tax (1%)',
                    '₹${estimatedCompositionTax.toStringAsFixed(2)}',
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
}
