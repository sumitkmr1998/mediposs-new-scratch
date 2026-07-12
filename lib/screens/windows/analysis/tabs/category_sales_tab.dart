import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../shared/models/medicine.dart';
import '../../../../shared/models/sale.dart';
import '../../../../shared/providers/sales_provider.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/utils/analytics_helper.dart';
import '../../../../theme/app_theme.dart';

class CategorySalesTab extends StatefulWidget {
  const CategorySalesTab({super.key});

  @override
  State<CategorySalesTab> createState() => _CategorySalesTabState();
}

class _CategorySalesTabState extends State<CategorySalesTab> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final salesProvider = context.watch<SalesProvider>();

    final medicines = inventory.rawMedicines;
    final sales = salesProvider.rawSales;

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
}
