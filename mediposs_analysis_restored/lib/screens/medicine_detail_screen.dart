import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../models/medicine.dart';
import '../providers/hub_provider.dart';
import '../theme/app_theme.dart';

class MedicineDetailScreen extends StatefulWidget {
  final Medicine medicine;

  const MedicineDetailScreen({super.key, required this.medicine});

  @override
  State<MedicineDetailScreen> createState() => _MedicineDetailScreenState();
}

class _MedicineDetailScreenState extends State<MedicineDetailScreen> {
  DateTimeRange? _dateRange;

  Medicine get medicine => widget.medicine;

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubProvider>();
    // Use the latest medicine data from the provider (stock/price might have changed)
    final medicine = hub.medicines.firstWhere(
      (item) => item.id == widget.medicine.id,
      orElse: () => widget.medicine,
    );

    final dataRange = hub.dateRangeForMedicine(medicine.id);
    final now = DateTime.now();

    // Default range: If medicine has data, show it all. If not, show last 30 days.
    final defaultStart =
        dataRange?.start ?? now.subtract(const Duration(days: 30));
    final defaultEnd = dataRange?.end ?? now;

    final start = _dateRange?.start ?? defaultStart;
    final end = _dateRange?.end ?? defaultEnd;

    // Filter sales by date range
    final filteredSales = hub.sales.where((s) {
      if (s.isReturn) return false;
      return s.createdAt.isAfter(start.subtract(const Duration(days: 1))) &&
          s.createdAt.isBefore(end.add(const Duration(days: 1)));
    }).toList();

    // Compute filtered stats
    int totalSold = 0;
    double revenue = 0;
    final dailySales = <DateTime, int>{};
    final invoiceDetails = <_InvoiceRow>[];

    for (final sale in filteredSales) {
      for (final item in sale.items) {
        if (item.medicineId == medicine.id) {
          totalSold += item.qty;
          revenue += item.lineTotal;
          final day = DateTime(
            sale.createdAt.year,
            sale.createdAt.month,
            sale.createdAt.day,
          );
          dailySales[day] = (dailySales[day] ?? 0) + item.qty;
          invoiceDetails.add(
            _InvoiceRow(
              date: sale.createdAt,
              invoiceNo: sale.invoiceNo,
              customer: sale.patientName,
              qty: item.qty,
              unitPrice: item.unitPrice,
              total: item.lineTotal,
            ),
          );
        }
      }
    }

    final days = end.difference(start).inDays;
    final dailyAvg = days > 0 ? totalSold / days : totalSold.toDouble();
    final daysLeft = hub.daysOfStockRemaining(medicine.id);
    final profit = revenue - (medicine.purchasePrice * totalSold);

    return Scaffold(
      appBar: AppBar(
        title: Text(medicine.name),
        backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reorder alert banner
            if (daysLeft < 7 && daysLeft < 999)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.danger.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber,
                      color: AppTheme.danger,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '⚠️ Stock will run out in ${daysLeft.toStringAsFixed(0)} days! Consider reordering now.',
                        style: const TextStyle(
                          color: AppTheme.danger,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Medicine info header
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.medication,
                        color: AppTheme.primary,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medicine.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${medicine.category} • ${medicine.unit} • ${medicine.barcode.isNotEmpty ? medicine.barcode : "No barcode"}',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // DATE FILTER
            Card(
              color: AppTheme.info.withValues(alpha: 0.05),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month, color: AppTheme.info),
                    const SizedBox(width: 12),
                    Text(
                      _dateRange != null
                          ? '${_formatDate(start)} — ${_formatDate(end)}'
                          : 'Last 30 days (default)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.tonal(
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange:
                              _dateRange ??
                              DateTimeRange(start: start, end: end),
                        );
                        if (picked != null) {
                          setState(() => _dateRange = picked);
                        }
                      },
                      child: const Text('Change'),
                    ),
                    if (_dateRange != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        tooltip: 'Reset to 30 days',
                        onPressed: () => setState(() => _dateRange = null),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // KPI Cards
            Row(
              children: [
                Expanded(
                  child: _KpiCard(
                    title: 'Store Stock',
                    value: '${medicine.storeStock}',
                    icon: Icons.store,
                    color: AppTheme.info,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KpiCard(
                    title: 'Main Stock',
                    value: '${medicine.mainStock}',
                    icon: Icons.warehouse,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KpiCard(
                    title: 'Units Sold',
                    value: '$totalSold',
                    icon: Icons.shopping_cart,
                    color: AppTheme.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _KpiCard(
                    title: 'Daily Avg',
                    value: dailyAvg.toStringAsFixed(1),
                    icon: Icons.trending_up,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KpiCard(
                    title: 'Days Left',
                    value: daysLeft >= 999 ? '∞' : daysLeft.toStringAsFixed(0),
                    icon: Icons.timer,
                    color: daysLeft < 7 ? AppTheme.danger : AppTheme.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KpiCard(
                    title: 'Margin',
                    value:
                        '₹${medicine.profitMargin.toStringAsFixed(2)} (${medicine.marginPercent.toStringAsFixed(0)}%)',
                    icon: Icons.attach_money,
                    color: medicine.profitMargin > 0
                        ? AppTheme.success
                        : AppTheme.danger,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Pricing + Period Revenue
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: _PriceCol(
                        label: 'Purchase',
                        value: '₹${medicine.purchasePrice.toStringAsFixed(2)}',
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey.shade300,
                    ),
                    Expanded(
                      child: _PriceCol(
                        label: 'Selling',
                        value: '₹${medicine.sellingPrice.toStringAsFixed(2)}',
                        color: AppTheme.success,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey.shade300,
                    ),
                    Expanded(
                      child: _PriceCol(
                        label: 'Revenue',
                        value: '₹${revenue.toStringAsFixed(0)}',
                        color: AppTheme.primary,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey.shade300,
                    ),
                    Expanded(
                      child: _PriceCol(
                        label: 'Profit',
                        value: '₹${profit.toStringAsFixed(0)}',
                        color: profit > 0 ? AppTheme.success : AppTheme.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Sales trend chart
            Text('Sales Trend', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Card(
              child: Container(
                height: 250,
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 24, 24, 16),
                child: _buildSalesChart(dailySales, start, end),
              ),
            ),

            const SizedBox(height: 24),

            // Granular invoice table
            Text(
              'Sale Transactions (${invoiceDetails.length})',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(
              child: invoiceDetails.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No transactions found in this period.'),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(
                            label: Text(
                              'Date',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Invoice',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Customer',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Qty',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            numeric: true,
                          ),
                          DataColumn(
                            label: Text(
                              'Price',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            numeric: true,
                          ),
                          DataColumn(
                            label: Text(
                              'Total',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            numeric: true,
                          ),
                        ],
                        rows: invoiceDetails
                            .map(
                              (r) => DataRow(
                                cells: [
                                  DataCell(Text(_formatDate(r.date))),
                                  DataCell(Text(r.invoiceNo)),
                                  DataCell(Text(r.customer)),
                                  DataCell(Text('${r.qty}')),
                                  DataCell(
                                    Text('₹${r.unitPrice.toStringAsFixed(2)}'),
                                  ),
                                  DataCell(
                                    Text(
                                      '₹${r.total.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Widget _buildSalesChart(
    Map<DateTime, int> dailySales,
    DateTime start,
    DateTime end,
  ) {
    final totalDays = end.difference(start).inDays + 1;
    if (totalDays <= 0) return const Center(child: Text('Invalid date range'));

    final daysList = List.generate(
      totalDays,
      (i) => DateTime(start.year, start.month, start.day + i),
    );
    final spots = daysList.asMap().entries.map((e) {
      final qty = dailySales[e.value] ?? 0;
      return FlSpot(e.key.toDouble(), qty.toDouble());
    }).toList();

    final interval = (totalDays / 6).ceil().toDouble();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true, drawVerticalLine: false),
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
              interval: interval,
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx >= 0 && idx < daysList.length) {
                  final d = daysList[idx];
                  return Text(
                    '${d.day}/${d.month}',
                    style: const TextStyle(fontSize: 10),
                  );
                }
                return const Text('');
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppTheme.primary,
            barWidth: 3,
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.primary.withValues(alpha: 0.15),
            ),
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

class _InvoiceRow {
  final DateTime date;
  final String invoiceNo;
  final String customer;
  final int qty;
  final double unitPrice;
  final double total;
  _InvoiceRow({
    required this.date,
    required this.invoiceNo,
    required this.customer,
    required this.qty,
    required this.unitPrice,
    required this.total,
  });
}

class _PriceCol extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _PriceCol({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
