import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../shared/models/medicine.dart';
import '../../shared/models/sale.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/utils/analytics_helper.dart';
import '../../theme/app_theme.dart';
import '../../shared/widgets/app_status_badge.dart';

class AndroidMedicineDetailScreen extends StatelessWidget {
  final Medicine medicine;

  const AndroidMedicineDetailScreen({super.key, required this.medicine});

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesProvider>().rawSales;
    
    // Consumption rates
    final velocity7 = AnalyticsHelper.dailyConsumptionRate(medicine.id, sales, trendDays: 7);
    final velocity30 = AnalyticsHelper.dailyConsumptionRate(medicine.id, sales, trendDays: 30);
    final velocity90 = AnalyticsHelper.dailyConsumptionRate(medicine.id, sales, trendDays: 90);
    
    // Deletion/Depletion Timeline based on recent 30-day trend
    final daysLeft = AnalyticsHelper.daysOfStockRemaining(medicine, sales, trendDays: 30);
    
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        title: Text(medicine.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: context.surfaceColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Medicine Header Card
            _buildHeaderCard(context),
            const SizedBox(height: 16),
            
            // Stock Status Timeline
            _buildTimelineCard(context, daysLeft, velocity30),
            const SizedBox(height: 16),
            
            // Stock Breakdown Section
            _buildStockBreakdownCard(context),
            const SizedBox(height: 16),
            
            // Pricing & Margins Section
            _buildFinancialsCard(context),
            const SizedBox(height: 16),
            
            // Consumption Trends Section
            _buildTrendsCard(context, velocity7, velocity30, velocity90),
            const SizedBox(height: 16),
            
            // Batches Section
            _buildBatchesCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.medication_rounded, color: AppTheme.primary, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medicine.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.borderColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          medicine.category.isEmpty ? 'General' : medicine.category,
                          style: TextStyle(fontSize: 11, color: context.textColor.withValues(alpha: 0.8)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Unit: ${medicine.unit}',
                        style: TextStyle(fontSize: 12, color: context.textMutedColor),
                      ),
                    ],
                  ),
                  if (medicine.barcode.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Barcode: ${medicine.barcode}',
                      style: TextStyle(fontSize: 11, color: context.textMutedColor, fontFamily: 'monospace'),
                    ),
                  ],
                ],
              ),
            ),
            if (medicine.isScheduleH1)
              const AppStatusBadge(
                label: 'H1',
                color: AppTheme.danger,
                style: AppStatusBadgeStyle.text,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineCard(BuildContext context, double daysLeft, double velocity30) {
    final bool hasSales = velocity30 > 0;
    String timelineText = 'No recent sales activity';
    Color timelineColor = Colors.grey;
    double progress = 0.0;
    
    if (hasSales) {
      if (daysLeft == 999.0) {
        timelineText = 'Infinite Stock Left';
        timelineColor = AppTheme.success;
        progress = 1.0;
      } else if (daysLeft < 7) {
        timelineText = '${daysLeft.toStringAsFixed(1)} days of stock left (Critical)';
        timelineColor = AppTheme.danger;
        progress = (daysLeft / 30).clamp(0.0, 1.0);
      } else if (daysLeft < 15) {
        timelineText = '${daysLeft.toStringAsFixed(1)} days of stock left (Urgent)';
        timelineColor = AppTheme.orange;
        progress = (daysLeft / 30).clamp(0.0, 1.0);
      } else if (daysLeft < 30) {
        timelineText = '${daysLeft.toStringAsFixed(1)} days of stock left (Depleting)';
        timelineColor = AppTheme.warning;
        progress = (daysLeft / 30).clamp(0.0, 1.0);
      } else {
        timelineText = '${(daysLeft / 30).toStringAsFixed(1)} months of stock left';
        timelineColor = AppTheme.success;
        progress = 1.0;
      }
    }

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'DEPLETION TIMELINE',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 0.5),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    timelineText,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: timelineColor),
                  ),
                ),
                if (hasSales && daysLeft < 999.0)
                  Text(
                    '${(velocity30 * 30).toStringAsFixed(0)} sold/mo',
                    style: TextStyle(fontSize: 12, color: context.textMutedColor),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (hasSales)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: timelineColor.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(timelineColor),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockBreakdownCard(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'STOCK DISTRIBUTION',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 0.5),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStockInfoCol('CLINIC', medicine.mainStock, 'BULK: ${medicine.bulkClinicStock}', AppTheme.indigo),
                Container(height: 40, width: 1, color: context.borderColor.withValues(alpha: 0.3)),
                _buildStockInfoCol('STORE', medicine.storeStock, 'BULK: ${medicine.bulkStoreStock}', const Color(0xFF14B8A6)),
                Container(height: 40, width: 1, color: context.borderColor.withValues(alpha: 0.3)),
                _buildStockInfoCol('TOTAL', medicine.totalStock, 'Thresh: ${medicine.lowStockThreshold}', AppTheme.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockInfoCol(String label, int value, String subText, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          value.toString(),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          subText,
          style: const TextStyle(fontSize: 9, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildFinancialsCard(BuildContext context) {
    final markup = medicine.purchasePrice > 0
        ? ((medicine.sellingPrice - medicine.purchasePrice) / medicine.purchasePrice * 100)
        : 0.0;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FINANCIAL METRICS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 0.5),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildFinancialTile('Cost Price', '₹${medicine.purchasePrice.toStringAsFixed(2)}', Colors.orange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildFinancialTile('Selling Price', '₹${medicine.sellingPrice.toStringAsFixed(2)}', Colors.teal),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildFinancialTile('Margin', '₹${medicine.profitMargin.toStringAsFixed(2)}', AppTheme.primaryLight),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildFinancialTile('Markup %', '${markup.toStringAsFixed(1)}%', AppTheme.success),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildTrendsCard(BuildContext context, double v7, double v30, double v90) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CONSUMPTION RATE (DAILY VELOCITY)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 0.5),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildTrendItem('7 Days (Recent)', v7, AppTheme.orange)),
                Expanded(child: _buildTrendItem('30 Days (Mid)', v30, AppTheme.primary)),
                Expanded(child: _buildTrendItem('90 Days (Long)', v90, Colors.teal)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendItem(String range, double rate, Color color) {
    return Column(
      children: [
        Text(range, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(
          rate.toStringAsFixed(2),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        const Text('units / day', style: TextStyle(fontSize: 9, color: Colors.grey)),
      ],
    );
  }

  Widget _buildBatchesCard(BuildContext context) {
    final now = DateTime.now();
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'REGISTERED BATCHES',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 0.5),
            ),
            const SizedBox(height: 12),
            if (medicine.batches.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('No batches registered.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: medicine.batches.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, idx) {
                  final b = medicine.batches[idx];
                  final totalBatch = b.mainStock + b.storeStock + b.bulkClinicStock + b.bulkStoreStock;
                  final isExpired = b.expiryDate.isBefore(now);
                  final isNearExpiry = !isExpired && b.expiryDate.isBefore(now.add(const Duration(days: 90)));
                  
                  Color statusColor = Colors.green;
                  String statusLabel = 'ACTIVE';
                  if (isExpired) {
                    statusColor = AppTheme.danger;
                    statusLabel = 'EXPIRED';
                  } else if (isNearExpiry) {
                    statusColor = AppTheme.orange;
                    statusLabel = 'NEAR EXPIRY';
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Batch: ${b.batchNo}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Expiry: ${DateFormat('dd/MM/yyyy').format(b.expiryDate)}',
                              style: TextStyle(fontSize: 11, color: context.textMutedColor),
                            ),
                            Text(
                              'Qty: $totalBatch ${medicine.unit}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Clinic: ${b.mainStock} (Bulk: ${b.bulkClinicStock}) | Store: ${b.storeStock} (Bulk: ${b.bulkStoreStock})',
                          style: TextStyle(fontSize: 10, color: context.textMutedColor),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
