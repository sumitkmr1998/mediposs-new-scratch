import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';

class AiChartWidget extends StatelessWidget {
  final String jsonString;

  const AiChartWidget({super.key, required this.jsonString});

  @override
  Widget build(BuildContext context) {
    try {
      final data = jsonDecode(jsonString);
      final type = data['type'] as String?;
      final title = data['title'] as String? ?? 'Data Chart';
      final rawData = data['data'] as List<dynamic>? ?? [];

      if (rawData.isEmpty) {
        return const Text('No data provided for chart.');
      }

      Widget chart;
      if (type == 'bar') {
        chart = _buildBarChart(rawData);
      } else if (type == 'pie') {
        chart = _buildPieChart(rawData);
      } else if (type == 'line') {
        chart = _buildLineChart(rawData);
      } else if (type == 'table') {
        chart = _buildTable(rawData);
      } else {
        return Text('Unsupported chart type: $type');
      }

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (type == 'table')
              chart
            else
              SizedBox(height: 200, width: double.infinity, child: chart),
          ],
        ),
      );
    } catch (e) {
      return Container(
        padding: const EdgeInsets.all(8),
        color: AppTheme.danger.withValues(alpha: 0.1),
        child: Text(
          'Error rendering AI chart: $e',
          style: const TextStyle(color: AppTheme.danger),
        ),
      );
    }
  }

  Widget _buildBarChart(List<dynamic> rawData) {
    final maxY = rawData
        .map((e) => (e['value'] as num).toDouble())
        .reduce((a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY * 1.2,
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value >= 0 && value < rawData.length) {
                  final label =
                      rawData[value.toInt()]['label']?.toString() ?? '';
                  // Truncate long labels
                  final displayLabel = label.length > 10
                      ? '${label.substring(0, 8)}...'
                      : label;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      displayLabel,
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(rawData.length, (index) {
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: (rawData[index]['value'] as num).toDouble(),
                color: AppTheme.primary,
                width: 16,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildPieChart(List<dynamic> rawData) {
    final colors = [
      AppTheme.primary,
      AppTheme.warning,
      AppTheme.success,
      AppTheme.danger,
      AppTheme.info,
      Colors.purple,
      Colors.teal,
      Colors.orange,
    ];

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: List.generate(rawData.length, (index) {
          final item = rawData[index];
          final value = (item['value'] as num).toDouble();
          final label = item['label']?.toString() ?? '';

          return PieChartSectionData(
            color: colors[index % colors.length],
            value: value,
            title: label,
            radius: 50,
            titleStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [Shadow(color: Colors.black, blurRadius: 2)],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLineChart(List<dynamic> rawData) {
    if (rawData.isEmpty) return const SizedBox.shrink();

    final maxY = rawData
        .map((e) => (e['value'] as num).toDouble())
        .reduce((a, b) => a > b ? a : b);

    final spots = List.generate(rawData.length, (index) {
      final value = (rawData[index]['value'] as num).toDouble();
      return FlSpot(index.toDouble(), value);
    });

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
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
              getTitlesWidget: (value, meta) {
                if (value >= 0 && value < rawData.length) {
                  final label =
                      rawData[value.toInt()]['label']?.toString() ?? '';
                  final displayLabel = label.length > 8
                      ? '${label.substring(0, 6)}..'
                      : label;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      displayLabel,
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                return Text(
                  value >= 1000
                      ? '${(value / 1000).toStringAsFixed(1)}k'
                      : value.toStringAsFixed(0),
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
        maxX: (rawData.length - 1).toDouble() < 0
            ? 0
            : (rawData.length - 1).toDouble(),
        minY: 0,
        maxY: maxY * 1.2,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppTheme.info,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.info.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<dynamic> rawData) {
    if (rawData.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(
          AppTheme.primary.withValues(alpha: 0.1),
        ),
        columns: const [
          DataColumn(
            label: Text('Label', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          DataColumn(
            label: Text('Value', style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true,
          ),
        ],
        rows: rawData.map((item) {
          final label = item['label']?.toString() ?? '';
          final valueStr = item['value']?.toString() ?? '';

          return DataRow(
            cells: [DataCell(Text(label)), DataCell(Text(valueStr))],
          );
        }).toList(),
      ),
    );
  }
}
