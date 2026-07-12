import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../shared/providers/patient_provider.dart';
import '../../../../shared/providers/sales_provider.dart';
import '../../../../shared/utils/analytics_helper.dart';
import '../../../../shared/widgets/app_kpi_card.dart';
import '../../../../theme/app_theme.dart';

class PatientAnalyticsTab extends StatefulWidget {
  const PatientAnalyticsTab({super.key});

  @override
  State<PatientAnalyticsTab> createState() => _PatientAnalyticsTabState();
}

class _PatientAnalyticsTabState extends State<PatientAnalyticsTab> {
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

  @override
  Widget build(BuildContext context) {
    final salesProvider = context.watch<SalesProvider>();
    final patientProvider = context.watch<PatientProvider>();

    final sales = salesProvider.rawSales;
    final patients = patientProvider.patients;

    final stats = AnalyticsHelper.getPatientAnalytics(sales, patients);

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
}
