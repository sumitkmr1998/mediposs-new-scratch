import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/hub_provider.dart';
import '../theme/app_theme.dart';

class SalesAnalyticsScreen extends StatefulWidget {
  const SalesAnalyticsScreen({super.key});

  @override
  State<SalesAnalyticsScreen> createState() => _SalesAnalyticsScreenState();
}

class _SalesAnalyticsScreenState extends State<SalesAnalyticsScreen> {
  String _period = 'This Month';

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubProvider>();
    final now = DateTime.now();

    // Calculate period boundaries
    late DateTime periodStart, prevStart, prevEnd;
    if (_period == 'This Week') {
      periodStart = now.subtract(Duration(days: now.weekday - 1));
      prevEnd = periodStart.subtract(const Duration(days: 1));
      prevStart = prevEnd.subtract(const Duration(days: 6));
    } else if (_period == 'This Month') {
      periodStart = DateTime(now.year, now.month, 1);
      prevEnd = periodStart.subtract(const Duration(days: 1));
      prevStart = DateTime(prevEnd.year, prevEnd.month, 1);
    } else {
      periodStart = DateTime(now.year, now.month - 3, 1);
      prevEnd = periodStart.subtract(const Duration(days: 1));
      prevStart = DateTime(prevEnd.year, prevEnd.month - 3, 1);
    }

    final periodSales = hub.sales
        .where((s) => s.createdAt.isAfter(periodStart) && !s.isReturn)
        .toList();
    final prevSales = hub.sales
        .where(
          (s) =>
              s.createdAt.isAfter(prevStart) &&
              s.createdAt.isBefore(periodStart) &&
              !s.isReturn,
        )
        .toList();

    final periodRevenue = periodSales.fold(0.0, (sum, s) => sum + s.total);
    final prevRevenue = prevSales.fold(0.0, (sum, s) => sum + s.total);
    final revChange = prevRevenue > 0
        ? ((periodRevenue - prevRevenue) / prevRevenue) * 100
        : 0;

    final periodTx = periodSales.length;
    final prevTx = prevSales.length;
    final txChange = prevTx > 0 ? ((periodTx - prevTx) / prevTx * 100) : 0;

    final avgBasket = periodTx > 0 ? periodRevenue / periodTx : 0;
    final prevAvgBasket = prevTx > 0 ? prevRevenue / prevTx : 0;
    final basketChange = prevAvgBasket > 0
        ? ((avgBasket - prevAvgBasket) / prevAvgBasket * 100)
        : 0;

    // Day-of-week analysis
    final dowCounts = List.filled(7, 0);
    final dowRevenue = List.filled(7, 0.0);
    for (final s in periodSales) {
      final dow = s.createdAt.weekday - 1; // 0=Mon
      dowCounts[dow]++;
      dowRevenue[dow] += s.total;
    }
    final dowLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    // Hourly analysis
    final hourCounts = List.filled(24, 0);
    for (final s in periodSales) {
      hourCounts[s.createdAt.hour]++;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Analytics'),
        backgroundColor: AppTheme.info.withValues(alpha: 0.1),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Period selector
            Row(
              children: ['This Week', 'This Month', 'Last 3 Months'].map((p) {
                final isSelected = p == _period;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(p),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _period = p),
                    selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // Comparison cards
            Row(
              children: [
                Expanded(
                  child: _ComparisonCard(
                    title: 'Revenue',
                    current: '₹${periodRevenue.toStringAsFixed(0)}',
                    change: revChange.toDouble(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ComparisonCard(
                    title: 'Transactions',
                    current: '$periodTx',
                    change: txChange.toDouble(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ComparisonCard(
                    title: 'Avg Basket',
                    current: '₹${avgBasket.toStringAsFixed(0)}',
                    change: basketChange.toDouble(),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Day-of-week chart
            Text(
              'Sales by Day of Week',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Card(
              child: Container(
                height: 220,
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    gridData: const FlGridData(
                      show: true,
                      drawVerticalLine: false,
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, _) => Text(
                            dowLabels[value.toInt()],
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ),
                    barGroups: List.generate(7, (i) {
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: dowRevenue[i],
                            color: AppTheme.primary,
                            width: 20,
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

            const SizedBox(height: 32),

            // Hourly distribution
            Text(
              'Hourly Distribution',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Card(
              child: Container(
                height: 200,
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    gridData: const FlGridData(
                      show: true,
                      drawVerticalLine: false,
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 3,
                          getTitlesWidget: (value, _) {
                            final h = value.toInt();
                            return Text(
                              '${h}h',
                              style: const TextStyle(fontSize: 10),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: List.generate(24, (i) {
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: hourCounts[i].toDouble(),
                            color: AppTheme.info,
                            width: 8,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(2),
                              topRight: Radius.circular(2),
                            ),
                          ),
                        ],
                      );
                    }),
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

class _ComparisonCard extends StatelessWidget {
  final String title;
  final String current;
  final double change;

  const _ComparisonCard({
    required this.title,
    required this.current,
    required this.change,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = change >= 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              current,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  color: isPositive ? AppTheme.success : AppTheme.danger,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  '${change.toStringAsFixed(1)}% vs prev',
                  style: TextStyle(
                    color: isPositive ? AppTheme.success : AppTheme.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
