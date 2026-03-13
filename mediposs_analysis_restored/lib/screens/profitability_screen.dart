import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/hub_provider.dart';
import '../theme/app_theme.dart';

class ProfitabilityScreen extends StatelessWidget {
  const ProfitabilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubProvider>();
    final medicines = hub.medicines;
    final totalRevenue = hub.totalRevenue;
    final totalCost = hub.totalCost;
    final totalProfit = hub.totalProfit;
    final avgMargin = totalRevenue > 0 ? (totalProfit / totalRevenue) * 100 : 0;

    // Calculate per-medicine profitability
    final profitData = medicines
        .map((m) {
          final unitsSold = hub.totalUnitsSold(m.id);
          final revenue = hub.revenueForMedicine(m.id);
          final cost = m.purchasePrice * unitsSold;
          final profit = revenue - cost;
          return _MedProfit(
            m.name,
            revenue,
            profit,
            m.marginPercent,
            unitsSold,
          );
        })
        .where((p) => p.unitsSold > 0)
        .toList();

    profitData.sort((a, b) => b.profit.compareTo(a.profit));
    final topProfitable = profitData.take(10).toList();
    final leastProfitable = profitData.reversed.take(10).toList();

    // Margin distribution
    final marginBuckets = <String, int>{
      '<10%': 0,
      '10-25%': 0,
      '25-50%': 0,
      '>50%': 0,
    };
    for (final m in medicines) {
      if (m.marginPercent < 10) {
        marginBuckets['<10%'] = marginBuckets['<10%']! + 1;
      } else if (m.marginPercent < 25) {
        marginBuckets['10-25%'] = marginBuckets['10-25%']! + 1;
      } else if (m.marginPercent < 50) {
        marginBuckets['25-50%'] = marginBuckets['25-50%']! + 1;
      } else {
        marginBuckets['>50%'] = marginBuckets['>50%']! + 1;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profitability'),
        backgroundColor: AppTheme.success.withValues(alpha: 0.1),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary KPIs
            Row(
              children: [
                Expanded(
                  child: _SummaryTile(
                    title: 'Revenue',
                    value: '₹${totalRevenue.toStringAsFixed(0)}',
                    color: AppTheme.info,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryTile(
                    title: 'Cost',
                    value: '₹${totalCost.toStringAsFixed(0)}',
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryTile(
                    title: 'Profit',
                    value: '₹${totalProfit.toStringAsFixed(0)}',
                    color: AppTheme.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryTile(
                    title: 'Avg Margin',
                    value: '${avgMargin.toStringAsFixed(1)}%',
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Margin distribution pie chart
            Text(
              'Margin Distribution',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Card(
              child: SizedBox(
                height: 220,
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: PieChart(
                        PieChartData(
                          sections: [
                            PieChartSectionData(
                              value: marginBuckets['<10%']!.toDouble(),
                              title: '<10%\n${marginBuckets['<10%']}',
                              color: AppTheme.danger,
                              radius: 60,
                              titleStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            PieChartSectionData(
                              value: marginBuckets['10-25%']!.toDouble(),
                              title: '10-25%\n${marginBuckets['10-25%']}',
                              color: Colors.orange,
                              radius: 60,
                              titleStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            PieChartSectionData(
                              value: marginBuckets['25-50%']!.toDouble(),
                              title: '25-50%\n${marginBuckets['25-50%']}',
                              color: AppTheme.info,
                              radius: 60,
                              titleStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            PieChartSectionData(
                              value: marginBuckets['>50%']!.toDouble(),
                              title: '>50%\n${marginBuckets['>50%']}',
                              color: AppTheme.success,
                              radius: 60,
                              titleStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                          sectionsSpace: 2,
                          centerSpaceRadius: 30,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _LegendItem(
                            color: AppTheme.danger,
                            label: 'Low (<10%)',
                          ),
                          _LegendItem(
                            color: Colors.orange,
                            label: 'Fair (10-25%)',
                          ),
                          _LegendItem(
                            color: AppTheme.info,
                            label: 'Good (25-50%)',
                          ),
                          _LegendItem(
                            color: AppTheme.success,
                            label: 'Great (>50%)',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Top 10 most profitable
            Text(
              '🏆 Top 10 Most Profitable',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(child: _ProfitTable(data: topProfitable, isTop: true)),

            const SizedBox(height: 32),

            // Top 10 least profitable
            Text(
              '⚠️ Top 10 Least Profitable',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(child: _ProfitTable(data: leastProfitable, isTop: false)),
          ],
        ),
      ),
    );
  }
}

class _MedProfit {
  final String name;
  final double revenue;
  final double profit;
  final double marginPercent;
  final int unitsSold;

  _MedProfit(
    this.name,
    this.revenue,
    this.profit,
    this.marginPercent,
    this.unitsSold,
  );
}

class _SummaryTile extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _SummaryTile({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _ProfitTable extends StatelessWidget {
  final List<_MedProfit> data;
  final bool isTop;

  const _ProfitTable({required this.data, required this.isTop});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No data available'),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(
            label: Text(
              'Medicine',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          DataColumn(
            label: Text('Sold', style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true,
          ),
          DataColumn(
            label: Text(
              'Revenue',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            numeric: true,
          ),
          DataColumn(
            label: Text(
              'Profit',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            numeric: true,
          ),
          DataColumn(
            label: Text(
              'Margin',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            numeric: true,
          ),
        ],
        rows: data.map((d) {
          return DataRow(
            cells: [
              DataCell(Text(d.name, overflow: TextOverflow.ellipsis)),
              DataCell(Text('${d.unitsSold}')),
              DataCell(Text('₹${d.revenue.toStringAsFixed(0)}')),
              DataCell(
                Text(
                  '₹${d.profit.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: d.profit > 0 ? AppTheme.success : AppTheme.danger,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              DataCell(Text('${d.marginPercent.toStringAsFixed(0)}%')),
            ],
          );
        }).toList(),
      ),
    );
  }
}
