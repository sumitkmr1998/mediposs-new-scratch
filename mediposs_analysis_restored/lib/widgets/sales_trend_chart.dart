import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../theme/app_theme.dart';

class SalesTrendChart extends StatelessWidget {
  final List<Sale> sales;

  const SalesTrendChart({super.key, required this.sales});

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return const Center(child: Text('No sales data available.'));
    }

    // Group sales by trailing 7 days
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final Map<int, double> dailyTotals = {};

    for (int i = 0; i < 7; i++) {
      dailyTotals[i] = 0.0; // Initialize 7 days
    }

    double maxTotal = 0;

    for (final sale in sales) {
      final saleDate = DateTime(
        sale.createdAt.year,
        sale.createdAt.month,
        sale.createdAt.day,
      );
      final difference = today.difference(saleDate).inDays;

      if (difference >= 0 && difference < 7) {
        final amount = sale.isReturn ? -sale.total : sale.total;
        final dayIndex = 6 - difference; // 0 is 6 days ago, 6 is today
        dailyTotals[dayIndex] = (dailyTotals[dayIndex] ?? 0) + amount;

        if (dailyTotals[dayIndex]! > maxTotal) {
          maxTotal = dailyTotals[dayIndex]!;
        }
      }
    }

    final spots = List.generate(7, (index) {
      return FlSpot(index.toDouble(), dailyTotals[index]!);
    });

    final maxY = maxTotal > 0 ? maxTotal * 1.2 : 1000.0; // 20% headroom

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 5 > 0 ? maxY / 5 : 1,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.withValues(alpha: 0.2),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final daysAgo = 6 - value.toInt();
                final date = today.subtract(Duration(days: daysAgo));
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    DateFormat('E').format(date), // Mon, Tue...
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: maxY / 5 > 0 ? maxY / 5 : 1,
              reservedSize: 42,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                return Text(
                  '₹${(value / 1000).toStringAsFixed(1)}k',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.right,
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: 6,
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppTheme.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.primaryLight.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}
