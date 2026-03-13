import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/hub_provider.dart';
import '../theme/app_theme.dart';

class CategoryAnalysisScreen extends StatelessWidget {
  const CategoryAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubProvider>();
    final catRevenue = hub.revenueByCategory();

    // Category profit
    final catProfit = <String, double>{};
    for (final sale in hub.sales) {
      if (sale.isReturn) continue;
      for (final item in sale.items) {
        final med = hub.medicines
            .where((m) => m.id == item.medicineId)
            .firstOrNull;
        if (med != null) {
          final cat = med.category;
          final profit = (item.unitPrice - med.purchasePrice) * item.qty;
          catProfit[cat] = (catProfit[cat] ?? 0) + profit;
        }
      }
    }

    // Top seller per category
    final catTopSeller = <String, MapEntry<String, int>>{};
    final catMedSales = <String, Map<String, int>>{};
    for (final sale in hub.sales) {
      if (sale.isReturn) continue;
      for (final item in sale.items) {
        final med = hub.medicines
            .where((m) => m.id == item.medicineId)
            .firstOrNull;
        if (med != null) {
          final cat = med.category;
          catMedSales.putIfAbsent(cat, () => {});
          catMedSales[cat]![item.medicineName] =
              (catMedSales[cat]![item.medicineName] ?? 0) + item.qty;
        }
      }
    }
    for (final entry in catMedSales.entries) {
      final sorted = entry.value.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (sorted.isNotEmpty) {
        catTopSeller[entry.key] = sorted.first;
      }
    }

    final categories = catRevenue.keys.toList()
      ..sort((a, b) => (catRevenue[b] ?? 0).compareTo(catRevenue[a] ?? 0));
    final colors = [
      AppTheme.primary,
      AppTheme.success,
      AppTheme.info,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      AppTheme.danger,
      Colors.indigo,
      Colors.pink,
      Colors.brown,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Category Analysis'),
        backgroundColor: Colors.purple.withValues(alpha: 0.1),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Revenue by category pie chart
            Text(
              'Revenue by Category',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Card(
              child: SizedBox(
                height: 280,
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: PieChart(
                        PieChartData(
                          sections: categories.asMap().entries.map((entry) {
                            final cat = entry.value;
                            final rev = catRevenue[cat] ?? 0;
                            return PieChartSectionData(
                              value: rev,
                              title: '₹${rev.toStringAsFixed(0)}',
                              color: colors[entry.key % colors.length],
                              radius: 70,
                              titleStyle: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            );
                          }).toList(),
                          sectionsSpace: 2,
                          centerSpaceRadius: 30,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: categories.asMap().entries.map((entry) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: colors[entry.key % colors.length],
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      entry.value,
                                      style: const TextStyle(fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Revenue vs Profit by category
            Text(
              'Revenue vs Profit by Category',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Card(
              child: Container(
                height: 250,
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
                          getTitlesWidget: (value, _) {
                            final idx = value.toInt();
                            if (idx < categories.length) {
                              final name = categories[idx];
                              return Text(
                                name.length > 6
                                    ? '${name.substring(0, 6)}..'
                                    : name,
                                style: const TextStyle(fontSize: 9),
                              );
                            }
                            return const Text('');
                          },
                        ),
                      ),
                    ),
                    barGroups: categories.asMap().entries.map((entry) {
                      final cat = entry.value;
                      return BarChartGroupData(
                        x: entry.key,
                        barRods: [
                          BarChartRodData(
                            toY: catRevenue[cat] ?? 0,
                            color: AppTheme.info,
                            width: 12,
                          ),
                          BarChartRodData(
                            toY: catProfit[cat] ?? 0,
                            color: AppTheme.success,
                            width: 12,
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Top seller per category
            Text(
              'Top Seller per Category',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(
                      label: Text(
                        'Category',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Top Medicine',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Units Sold',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text(
                        'Revenue',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      numeric: true,
                    ),
                  ],
                  rows: categories.map((cat) {
                    final top = catTopSeller[cat];
                    return DataRow(
                      cells: [
                        DataCell(Text(cat)),
                        DataCell(Text(top?.key ?? '-')),
                        DataCell(Text('${top?.value ?? 0}')),
                        DataCell(
                          Text('₹${(catRevenue[cat] ?? 0).toStringAsFixed(0)}'),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
