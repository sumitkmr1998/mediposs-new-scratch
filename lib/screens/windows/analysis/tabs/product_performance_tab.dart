import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../../shared/models/medicine.dart';
import '../../../../shared/models/procedure.dart';
import '../../../../shared/models/sale.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/providers/sales_provider.dart';
import '../../../../shared/providers/procedure_provider.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/utils/analytics_helper.dart';
import '../../../../shared/widgets/app_kpi_card.dart';
import '../../../../theme/app_theme.dart';

class ProductPerformanceTab extends StatefulWidget {
  const ProductPerformanceTab({super.key});

  @override
  State<ProductPerformanceTab> createState() => _ProductPerformanceTabState();
}

class _ProductPerformanceTabState extends State<ProductPerformanceTab> {
  Medicine? _selectedMedicine;
  Procedure? _selectedProcedure;
  bool _showProcedures = false;
  
  String _detailPeriod = 'Last 30 Days';
  DateTimeRange? _detailCustomRange;

  String _perfPeriod = 'This Month';
  DateTimeRange? _perfCustomRange;

  List<Sale> _getFilteredSalesForPerf(List<Sale> sales) {
    final authProvider = context.read<AuthProvider>();
    final isStaffOnly = !authProvider.isAdmin;

    final now = DateTime.now();
    DateTime start;
    DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    if (isStaffOnly || _perfPeriod == 'Today') {
      start = DateTime(now.year, now.month, now.day);
    } else if (_perfPeriod == 'Yesterday') {
      final yest = now.subtract(const Duration(days: 1));
      start = DateTime(yest.year, yest.month, yest.day);
      end = DateTime(yest.year, yest.month, yest.day, 23, 59, 59);
    } else if (_perfPeriod == 'This Week') {
      start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    } else if (_perfPeriod == 'This Month') {
      start = DateTime(now.year, now.month, 1);
    } else if (_perfPeriod == 'Custom Range' && _perfCustomRange != null) {
      start = _perfCustomRange!.start;
      end = DateTime(_perfCustomRange!.end.year, _perfCustomRange!.end.month, _perfCustomRange!.end.day, 23, 59, 59);
    } else {
      start = DateTime(now.year, now.month, 1);
    }

    return sales.where((s) {
      return s.createdAt.isAfter(start.subtract(const Duration(seconds: 1))) &&
             s.createdAt.isBefore(end.add(const Duration(seconds: 1)));
    }).toList();
  }

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

  Widget _buildMedicineAlerts(Medicine m, double daysLeft) {
    final alerts = <Widget>[];

    if (m.hasExpiredBatch) {
      alerts.add(_buildStatusWarningCard('Expired Batches Detected!', 'Some batches are past their expiry date. Remove them immediately.', AppTheme.danger));
    } else if (m.hasNearExpiryBatch) {
      alerts.add(_buildStatusWarningCard('Near Expiry Batch Present', 'Stock batches are expiring soon. Consider prioritizing sales.', Colors.orange));
    }

    if (daysLeft < 14 && daysLeft < 999.0) {
      alerts.add(_buildStatusWarningCard('Stock Out Depletion Alert!', 'Current stock level will deplete within approximately ${daysLeft.toStringAsFixed(0)} days.', AppTheme.danger));
    }

    if (alerts.isEmpty) return const SizedBox();
    return Column(children: alerts);
  }

  Widget _buildStatusWarningCard(String title, String desc, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 24),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
              Text(desc, style: TextStyle(color: color.withOpacity(0.8), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStockFieldRow(String label, String val, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primary),
          const SizedBox(width: 16),
          Text(label, style: TextStyle(fontWeight: FontWeight.w500, color: context.textMutedColor)),
          const Spacer(),
          Text(val, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildMiniBatchCard(MedicineBatch b) {
    final isExp = b.expiryDate.isBefore(DateTime.now());
    final isNear = b.expiryDate.isBefore(DateTime.now().add(const Duration(days: 90))) && !isExp;
    final color = isExp ? AppTheme.danger : isNear ? Colors.orange : AppTheme.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('Batch: ${b.batchNo}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(
                  isExp ? 'EXPIRED' : isNear ? 'NEAR EXP' : 'HEALTHY',
                  style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniBatchField('Store', '${b.storeStock}'),
              _buildMiniBatchField('Clinic', '${b.mainStock}'),
              _buildMiniBatchField('S.Bulk', '${b.bulkStoreStock}'),
              _buildMiniBatchField('C.Bulk', '${b.bulkClinicStock}'),
              _buildMiniBatchField('Expiry', DateFormat('dd/MM/yyyy').format(b.expiryDate)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBatchField(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.textMutedColor, fontSize: 10)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMiniSalesTrendChart(Map<DateTime, int> dailySales) {
    final sortedDates = dailySales.keys.toList()..sort();
    final spots = List.generate(sortedDates.length, (i) {
      final date = sortedDates[i];
      return FlSpot(i.toDouble(), dailySales[date]!.toDouble());
    });

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (spot) => const Color(0xFF1E293B).withOpacity(0.9),
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${spot.y.toInt()} qty',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 9,
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
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx >= 0 && idx < sortedDates.length) {
                  final d = sortedDates[idx];
                  return Text('${d.day}/${d.month}', style: const TextStyle(fontSize: 9));
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
            gradient: const LinearGradient(
              colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
            ),
            barWidth: 3,
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF3B82F6).withOpacity(0.2),
                  const Color(0xFF3B82F6).withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailView({
    required List<Sale> sales,
    Medicine? medicine,
    Procedure? procedure,
  }) {
    final String name = medicine?.name ?? procedure?.name ?? 'Unknown';
    final String category = medicine?.category ?? procedure?.category ?? 'General';
    final String unit = medicine?.unit ?? 'sessions';
    final double purchasePrice = medicine?.purchasePrice ?? 0.0;
    final double sellingPrice = medicine?.sellingPrice ?? procedure?.basePrice ?? 0.0;
    final int totalStock = medicine?.totalStock ?? 0;
    final double marginPercent = sellingPrice > 0 ? (((sellingPrice - purchasePrice) / sellingPrice) * 100) : 0.0;

    final now = DateTime.now();
    DateTime start = now.subtract(const Duration(days: 30));
    DateTime end = now;

    if (_detailPeriod == 'This Month') {
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else if (_detailPeriod == 'Last Month') {
      start = DateTime(now.year, now.month - 1, 1);
      end = DateTime(now.year, now.month, 0, 23, 59, 59);
    } else if (_detailPeriod == 'Last 3 Months') {
      start = DateTime(now.year, now.month - 3, 1);
      end = now;
    } else if (_detailPeriod == 'Custom Range' && _detailCustomRange != null) {
      start = _detailCustomRange!.start;
      end = _detailCustomRange!.end;
    }

    final filteredSales = sales.where((s) {
      if (s.isReturn) return false;
      return s.createdAt.isAfter(start.subtract(const Duration(seconds: 1))) &&
             s.createdAt.isBefore(end.add(const Duration(seconds: 1)));
    }).toList();

    int totalSold = 0;
    double revenue = 0.0;
    final dailySales = <DateTime, int>{};
    final List<SaleRow> invoiceDetails = [];
    final patientVisitCount = <String, int>{};

    for (final sale in filteredSales) {
      final items = AnalyticsHelper.getItems(sale);
      for (final item in items) {
        final isMatch = (medicine != null && !item.isProcedure && item.medicineName.toLowerCase().trim() == medicine.name.toLowerCase().trim()) ||
                        (procedure != null && item.isProcedure && item.procedureId == procedure.id);
        if (isMatch) {
          totalSold += item.qty;
          revenue += item.lineTotal;
          final day = DateTime(sale.createdAt.year, sale.createdAt.month, sale.createdAt.day);
          dailySales[day] = (dailySales[day] ?? 0) + item.qty;
          invoiceDetails.add(
            SaleRow(
              date: sale.createdAt,
              invoiceNo: sale.invoiceNo,
              customer: sale.patientName.isNotEmpty ? sale.patientName : 'Walk-in Customer',
              qty: item.qty,
              total: item.lineTotal,
            ),
          );

          if (procedure != null) {
            final patientName = sale.patientName.isNotEmpty ? sale.patientName : 'Walk-in Customer';
            patientVisitCount[patientName] = (patientVisitCount[patientName] ?? 0) + item.qty;
          }
        }
      }
    }

    final int daysCount = end.difference(start).inDays.clamp(1, 99999);
    final dailyAvg = totalSold / daysCount.toDouble();
    
    double daysLeft = 999.0;
    if (medicine != null) {
      final dailyConsumption = AnalyticsHelper.dailyConsumptionRate(medicine.id, sales);
      daysLeft = dailyConsumption <= 0 ? 999.0 : medicine.totalStock / dailyConsumption;
    }
    
    final profit = revenue - (purchasePrice * totalSold);
    final sortedPatients = patientVisitCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final DateFormat formatter = DateFormat('dd MMM yyyy');
    final String rangeText = _detailPeriod == 'Custom Range' && _detailCustomRange != null
        ? '${formatter.format(_detailCustomRange!.start)} - ${formatter.format(_detailCustomRange!.end)}'
        : '${formatter.format(start)} - ${formatter.format(end)}';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            setState(() {
              _selectedMedicine = null;
              _selectedProcedure = null;
              _detailPeriod = 'Last 30 Days';
              _detailCustomRange = null;
            });
          },
        ),
        title: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$name Performance Metrics', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(rangeText, style: TextStyle(color: context.textMutedColor, fontSize: 12, fontWeight: FontWeight.normal)),
              ],
            ),
            const Spacer(),
            Row(
              children: ['Last 30 Days', 'This Month', 'Last Month', 'Last 3 Months', 'Custom Range'].map((p) {
                final isSelected = p == _detailPeriod;
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text(p),
                    selected: isSelected,
                    onSelected: (selected) async {
                      if (selected) {
                        if (p == 'Custom Range') {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(now.year - 5),
                            lastDate: DateTime(now.year + 1),
                            initialDateRange: _detailCustomRange ?? DateTimeRange(
                              start: now.subtract(const Duration(days: 30)),
                              end: now,
                            ),
                            locale: const Locale('en', 'GB'),
                            initialEntryMode: DatePickerEntryMode.input,
                          );
                          if (picked != null) {
                            setState(() {
                              _detailPeriod = p;
                              _detailCustomRange = picked;
                            });
                          }
                        } else {
                          setState(() {
                            _detailPeriod = p;
                          });
                        }
                      }
                    },
                    selectedColor: AppTheme.primary.withOpacity(0.2),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (medicine != null) _buildMedicineAlerts(medicine, daysLeft),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 6,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.25,
                  children: [
                    _buildMetricCard('Revenue', '₹${revenue.toStringAsFixed(0)}', Icons.payments_rounded, AppTheme.indigo),
                    _buildMetricCard('Gross Profit', '₹${profit.toStringAsFixed(0)}', Icons.trending_up_rounded, AppTheme.success),
                    _buildMetricCard(medicine != null ? 'Units Sold' : 'Sessions Conducted', '$totalSold', Icons.shopping_bag_rounded, AppTheme.primary),
                    _buildMetricCard('Daily Avg', dailyAvg.toStringAsFixed(1), Icons.show_chart_rounded, Colors.orange),
                    _buildMetricCard(
                      medicine != null ? 'Total Stock' : 'Type',
                      medicine != null ? '$totalStock' : 'Clinical Service',
                      Icons.inventory_2_rounded,
                      AppTheme.teal,
                    ),
                    _buildMetricCard(
                      medicine != null ? 'Stock Life' : 'Profit Margin',
                      medicine != null ? (daysLeft >= 999.0 ? '∞' : '${daysLeft.toStringAsFixed(0)} Days') : '100%',
                      Icons.timer_rounded,
                      medicine != null ? (daysLeft < 14 ? AppTheme.danger : AppTheme.success) : AppTheme.success,
                    ),
                  ],
                ),
                
                const SizedBox(height: 32),
                
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(medicine != null ? 'Quantity Sold Trend' : 'Sessions Booked Trend', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 16),
                          Card(
                            child: Container(
                              height: 280,
                              padding: const EdgeInsets.fromLTRB(16, 24, 24, 16),
                              child: dailySales.isEmpty
                                  ? const Center(child: Text('No sales registered in selected period.'))
                                  : _buildMiniSalesTrendChart(dailySales),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(medicine != null ? 'Inventory Configuration' : 'Clinical Service Configuration', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: medicine != null
                                  ? Column(
                                      children: [
                                        _buildStockFieldRow('Store Stock', '${medicine.storeStock} ${medicine.unit}', Icons.storefront),
                                        const Divider(),
                                        _buildStockFieldRow('Clinic Stock', '${medicine.mainStock} ${medicine.unit}', Icons.medical_services),
                                        const Divider(),
                                        _buildStockFieldRow('Store Bulk Stock', '${medicine.bulkStoreStock} ${medicine.unit}', Icons.warehouse_outlined),
                                        const Divider(),
                                        _buildStockFieldRow('Clinic Bulk Stock', '${medicine.bulkClinicStock} ${medicine.unit}', Icons.warehouse),
                                        const Divider(),
                                        _buildStockFieldRow('Purchase Cost', '₹${medicine.purchasePrice.toStringAsFixed(2)}', Icons.shopping_cart),
                                        const Divider(),
                                        _buildStockFieldRow('Selling Price', '₹${medicine.sellingPrice.toStringAsFixed(2)}', Icons.sell),
                                        const Divider(),
                                        _buildStockFieldRow('Margin Percent', '${marginPercent.toStringAsFixed(1)}%', Icons.percent),
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildStockFieldRow('Service Category', category, Icons.category_rounded),
                                        const Divider(),
                                        _buildStockFieldRow('Standard Base Price', '₹${sellingPrice.toStringAsFixed(2)}', Icons.sell),
                                        const Divider(),
                                        _buildStockFieldRow('Net Profit Margin', '100% (No purchase cost)', Icons.percent_rounded),
                                        const Divider(),
                                        Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(Icons.description_rounded, size: 20, color: AppTheme.primary),
                                                  const SizedBox(width: 16),
                                                  Text('Description', style: TextStyle(fontWeight: FontWeight.w500, color: context.textMutedColor)),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                procedure!.description.isNotEmpty ? procedure.description : 'Professional clinical procedure service.',
                                                style: const TextStyle(fontSize: 13, height: 1.4),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 32),
                
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(medicine != null ? 'Batch Listings' : 'Top Patient Consumers', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 16),
                          if (medicine != null) ...[
                            if (medicine.batches.isEmpty)
                              const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No active batches defined.'))))
                            else
                              ...medicine.batches.map((b) => _buildMiniBatchCard(b)),
                          ] else ...[
                            Card(
                              child: sortedPatients.isEmpty
                                  ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No clinical history for this service in this period.')))
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: sortedPatients.length.clamp(0, 5),
                                      separatorBuilder: (_, __) => const Divider(),
                                      itemBuilder: (context, index) {
                                        final entry = sortedPatients[index];
                                        return ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor: AppTheme.primary.withOpacity(0.1),
                                            child: Text('${index + 1}', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                                          ),
                                          title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                                          subtitle: const Text('Recipient patient'),
                                          trailing: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(color: AppTheme.success.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                            child: Text('${entry.value} $unit', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 12)),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ]
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Recent Invoices', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 16),
                          Card(
                            child: invoiceDetails.isEmpty
                                ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No invoice registers in selected period.')))
                                : ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: invoiceDetails.length.clamp(0, 5),
                                    separatorBuilder: (_, __) => const Divider(),
                                    itemBuilder: (context, index) {
                                      final row = invoiceDetails[invoiceDetails.length - 1 - index];
                                      return ListTile(
                                        title: Text(row.customer, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        subtitle: Text('${row.invoiceNo} • ${DateFormat('dd MMM yyyy').format(row.date)}'),
                                        trailing: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text('₹${row.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                            Text('${row.qty} $unit', style: TextStyle(color: context.textMutedColor, fontSize: 11)),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final salesProvider = context.watch<SalesProvider>();
    final procedureProvider = context.watch<ProcedureProvider>();
    final authProvider = context.watch<AuthProvider>();

    final medicines = inventory.rawMedicines;
    final sales = salesProvider.rawSales;
    final procedures = procedureProvider.procedures;

    if (_selectedMedicine != null || _selectedProcedure != null) {
      return _buildDetailView(
        sales: sales,
        medicine: _selectedMedicine,
        procedure: _selectedProcedure,
      );
    }

    final filteredSales = _getFilteredSalesForPerf(sales);
    final performanceList = AnalyticsHelper.getMedicinePerformanceLeaderboard(medicines, filteredSales)
        .where((perf) => perf.unitsSold > 0)
        .toList();

    // Computing procedure performance list
    final procedurePerformanceList = <ProcedurePerformance>[];
    if (_showProcedures) {
      final performanceMap = <int, int>{};
      final revenueMap = <int, double>{};

      for (final sale in filteredSales) {
        if (sale.isReturn) continue;
        for (final item in AnalyticsHelper.getItems(sale)) {
          if (item.isProcedure) {
            performanceMap[item.procedureId] = (performanceMap[item.procedureId] ?? 0) + item.qty;
            revenueMap[item.procedureId] = (revenueMap[item.procedureId] ?? 0.0) + item.lineTotal;
          }
        }
      }

      for (final p in procedures) {
        final units = performanceMap[p.id] ?? 0;
        if (units == 0) continue;
        final rev = revenueMap[p.id] ?? 0.0;
        procedurePerformanceList.add(ProcedurePerformance(
          procedure: p,
          unitsSold: units,
          revenue: rev,
          profit: rev, // 100% margin on procedures
        ));
      }
      procedurePerformanceList.sort((a, b) => b.unitsSold.compareTo(a.unitsSold));
    }

    final isStaffOnly = !authProvider.isAdmin;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Segmented Button or Toggle between Medicines and Procedures
              ToggleButtons(
                borderRadius: BorderRadius.circular(12),
                selectedColor: Colors.white,
                fillColor: AppTheme.primary,
                color: context.textMutedColor,
                constraints: const BoxConstraints(minHeight: 40, minWidth: 150),
                isSelected: [!_showProcedures, _showProcedures],
                onPressed: (index) {
                  setState(() {
                    _showProcedures = index == 1;
                  });
                },
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Medicines', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Clinical Services', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const Spacer(),
              // Search autocomplete
              SizedBox(
                width: 400,
                child: _showProcedures
                    ? Autocomplete<Procedure>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Procedure>.empty();
                          }
                          return procedures.where((Procedure p) {
                            return p.name.toLowerCase().contains(textEditingValue.text.toLowerCase());
                          });
                        },
                        displayStringForOption: (Procedure option) => option.name,
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              hintText: 'Search clinical service...',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: controller.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded),
                                      onPressed: () {
                                        controller.clear();
                                      },
                                    )
                                  : null,
                            ),
                          );
                        },
                        onSelected: (Procedure p) {
                          setState(() {
                            _selectedProcedure = p;
                          });
                        },
                      )
                    : Autocomplete<Medicine>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Medicine>.empty();
                          }
                          return medicines.where((Medicine m) {
                            return m.name.toLowerCase().contains(textEditingValue.text.toLowerCase());
                          });
                        },
                        displayStringForOption: (Medicine option) => option.name,
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              hintText: 'Search medicine...',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: controller.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded),
                                      onPressed: () {
                                        controller.clear();
                                      },
                                    )
                                  : null,
                            ),
                          );
                        },
                        onSelected: (Medicine m) {
                          setState(() {
                            _selectedMedicine = m;
                          });
                        },
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!isStaffOnly) ...[
            Row(
              children: [
                const Text('Filter Period: ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                _buildPeriodSelector(
                  selectedPeriod: _perfPeriod,
                  periods: const ['Today', 'Yesterday', 'This Week', 'This Month', 'Custom Range'],
                  onPeriodSelected: (p) async {
                    if (p == 'Custom Range') {
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDateRange: _perfCustomRange,
                      );
                      if (range != null) {
                        setState(() {
                          _perfPeriod = p;
                          _perfCustomRange = range;
                        });
                      }
                    } else {
                      setState(() {
                        _perfPeriod = p;
                        _perfCustomRange = null;
                      });
                    }
                  },
                ),
                if (_perfPeriod == 'Custom Range' && _perfCustomRange != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    '(${DateFormat('dd/MM/yyyy').format(_perfCustomRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_perfCustomRange!.end)})',
                    style: TextStyle(color: context.textMutedColor, fontSize: 13),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
          ],
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _showProcedures
                    ? (procedurePerformanceList.isEmpty
                        ? const Center(child: Text('No clinical services sales logs detected.'))
                        : Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.15), width: 1)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        'SERVICE / PROCEDURE',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: context.textMutedColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'SESSIONS CONDUCTED',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: context.textMutedColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        'REVENUE',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: context.textMutedColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        'NET PROFIT',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: context.textMutedColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 48),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: procedurePerformanceList.length,
                                  itemBuilder: (context, index) {
                                    final perf = procedurePerformanceList[index];
                                    final maxProcUnits = procedurePerformanceList.isEmpty ? 1 : procedurePerformanceList.map((p) => p.unitsSold).reduce((a, b) => a > b ? a : b);
                                    final ratio = maxProcUnits > 0 ? (perf.unitsSold / maxProcUnits) : 0.0;
                                    return Container(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: context.surfaceColor,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.grey.withOpacity(0.08)),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(perf.procedure.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.primary.withOpacity(0.08),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(perf.procedure.category, style: const TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('${perf.unitsSold} sessions', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                                const SizedBox(height: 6),
                                                SizedBox(
                                                  width: 120,
                                                  child: LinearProgressIndicator(
                                                    value: ratio,
                                                    backgroundColor: Colors.grey.withOpacity(0.1),
                                                    color: AppTheme.primary,
                                                    minHeight: 5,
                                                    borderRadius: BorderRadius.circular(3),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text('₹${perf.revenue.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text('₹${perf.profit.toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 13)),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.insights_rounded, color: AppTheme.primary, size: 20),
                                            onPressed: () {
                                              setState(() {
                                                _selectedProcedure = perf.procedure;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ))
                    : (performanceList.isEmpty
                        ? const Center(child: Text('No product sales logs detected.'))
                        : Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.15), width: 1)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        'MEDICINE / PRODUCT',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: context.textMutedColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'UNITS SOLD',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: context.textMutedColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        'REVENUE',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: context.textMutedColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        'GROSS PROFIT',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: context.textMutedColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 48),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: performanceList.length,
                                  itemBuilder: (context, index) {
                                    final perf = performanceList[index];
                                    final maxMedUnits = performanceList.isEmpty ? 1 : performanceList.map((p) => p.unitsSold).reduce((a, b) => a > b ? a : b);
                                    final ratio = maxMedUnits > 0 ? (perf.unitsSold / maxMedUnits) : 0.0;
                                    return Container(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: context.surfaceColor,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.grey.withOpacity(0.08)),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(perf.medicine.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.indigo.withOpacity(0.08),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(perf.medicine.category, style: const TextStyle(fontSize: 10, color: AppTheme.indigo, fontWeight: FontWeight.bold)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('${perf.unitsSold} ${perf.medicine.unit}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                                const SizedBox(height: 6),
                                                SizedBox(
                                                  width: 120,
                                                  child: LinearProgressIndicator(
                                                    value: ratio,
                                                    backgroundColor: Colors.grey.withOpacity(0.1),
                                                    color: AppTheme.indigo,
                                                    minHeight: 5,
                                                    borderRadius: BorderRadius.circular(3),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text('₹${perf.revenue.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text('₹${perf.profit.toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 13)),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.insights_rounded, color: AppTheme.indigo, size: 20),
                                            onPressed: () {
                                              setState(() {
                                                _selectedMedicine = perf.medicine;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          )),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SaleRow {
  final DateTime date;
  final String invoiceNo;
  final String customer;
  final int qty;
  final double total;

  SaleRow({
    required this.date,
    required this.invoiceNo,
    required this.customer,
    required this.qty,
    required this.total,
  });
}

class ProcedurePerformance {
  final Procedure procedure;
  final int unitsSold;
  final double revenue;
  final double profit;

  ProcedurePerformance({
    required this.procedure,
    required this.unitsSold,
    required this.revenue,
    required this.profit,
  });
}
