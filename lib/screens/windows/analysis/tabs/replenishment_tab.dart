import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/models/medicine.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/providers/warehouse_provider.dart';
import '../../../../shared/providers/sales_provider.dart';
import '../../../../shared/utils/consumption_aggregator.dart';
import '../../../../theme/app_theme.dart';
import '../../warehouse/dialogs/transfer_dialog.dart';

class ReplenishmentTab extends StatefulWidget {
  const ReplenishmentTab({super.key});

  @override
  State<ReplenishmentTab> createState() => _ReplenishmentTabState();
}

class _ReplenishmentTabState extends State<ReplenishmentTab> {
  int _targetDays = 15;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final salesProvider = context.watch<SalesProvider>();

    final allMedicines = inventory.rawMedicines;
    final salesFor30Days = salesProvider.salesForAnalytics(days: 30);
    final consumptionResult = ConsumptionAggregator.build(salesFor30Days);

    final List<Map<String, dynamic>> replenishmentItems = [];

    for (final med in allMedicines) {
      final dispensingStock = inventory.getDispensingStock(med);
      final daily = consumptionResult.dailyRateForMedicine(
        medicineId: med.id,
        medicineName: med.name,
        trendDays: 30,
      );

      final int requiredStock = (daily > 0 ? (daily * _targetDays).ceil() : med.lowStockThreshold).toInt();
      final int deficit = requiredStock > dispensingStock ? (requiredStock - dispensingStock) : 0;
      final bool isLow = dispensingStock < requiredStock;

      final int totalBulkStock = med.bulkStoreStock + med.bulkClinicStock;

      if (isLow) {
        replenishmentItems.add({
          'medicine': med,
          'dispensingStock': dispensingStock,
          'daily': daily,
          'requiredStock': requiredStock,
          'deficit': deficit,
          'bulkStock': totalBulkStock,
        });
      }
    }

    replenishmentItems.sort((a, b) => (b['deficit'] as int).compareTo(a['deficit'] as int));

    final filteredItems = replenishmentItems.where((item) {
      if (_searchQuery.isEmpty) return true;
      final Medicine med = item['medicine'];
      return med.name.toLowerCase().contains(_searchQuery.toLowerCase().trim()) ||
          med.category.toLowerCase().contains(_searchQuery.toLowerCase().trim());
    }).toList();

    int totalDeficit = 0;
    int availableInBulkCount = 0;
    for (final item in replenishmentItems) {
      totalDeficit += (item['deficit'] as int);
      if ((item['bulkStock'] as int) >= (item['deficit'] as int)) {
        availableInBulkCount++;
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Controls & Target Selector Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderColor.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.swap_horiz_rounded, color: AppTheme.primary, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Store & Clinic Replenishment Planner',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Identifies stock shortages in Store + Clinic dispensing stock (Excludes Bulk/Main Warehouse stock).',
                          style: TextStyle(fontSize: 12, color: context.textMutedColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Target Days Selector
                  Row(
                    children: [
                      Text(
                        'Target Buffer:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.textColor),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: context.bgColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: context.borderColor.withValues(alpha: 0.2)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _targetDays,
                            dropdownColor: context.surfaceColor,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: context.textColor),
                            items: const [
                              DropdownMenuItem(value: 7, child: Text('7 Days Buffer')),
                              DropdownMenuItem(value: 15, child: Text('15 Days Buffer')),
                              DropdownMenuItem(value: 30, child: Text('30 Days Buffer')),
                              DropdownMenuItem(value: 45, child: Text('45 Days Buffer')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _targetDays = val);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Summary KPI Row
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Replenishment Needed',
                    value: '${replenishmentItems.length} Medicines',
                    subtitle: 'Dispensing stock below $_targetDays-day buffer',
                    icon: Icons.error_outline_rounded,
                    color: AppTheme.orange,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Total Transfer Deficit',
                    value: '$totalDeficit Units',
                    subtitle: 'Total units needed in Store & Clinic',
                    icon: Icons.inventory_2_rounded,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Covered by Bulk Stock',
                    value: '$availableInBulkCount / ${replenishmentItems.length}',
                    subtitle: 'Medicines with sufficient Bulk stock',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppTheme.emerald,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search Bar & Table Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: 320,
                  height: 40,
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search medicine name or category...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      filled: true,
                      fillColor: context.surfaceColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: context.borderColor.withValues(alpha: 0.2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: context.borderColor.withValues(alpha: 0.2)),
                      ),
                    ),
                  ),
                ),
                Text(
                  'Showing ${filteredItems.length} of ${replenishmentItems.length} items',
                  style: TextStyle(fontSize: 12, color: context.textMutedColor),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Main Data Table / List View
            Expanded(
              child: filteredItems.isEmpty
                  ? Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.borderColor.withValues(alpha: 0.15)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.task_alt_rounded,
                            size: 56,
                            color: AppTheme.emerald.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Dispensing Stock is Fully Replenished!',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'All store and clinic stocks meet or exceed the $_targetDays-day consumption buffer.',
                            style: TextStyle(fontSize: 13, color: context.textMutedColor),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.borderColor.withValues(alpha: 0.15)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SizedBox(
                            width: double.infinity,
                            child: DataTable(
                              headingRowHeight: 48,
                              dataRowMinHeight: 52,
                              dataRowMaxHeight: 52,
                              horizontalMargin: 20,
                              columnSpacing: 24,
                              headingRowColor: WidgetStateProperty.all(
                                context.bgColor.withValues(alpha: 0.5),
                              ),
                              columns: const [
                                DataColumn(label: Text('Medicine Name', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Store', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Clinic', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Dispensing Total', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('30d Daily Avg', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Req. Buffer', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Deficit', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Bulk Warehouse', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                              ],
                              rows: filteredItems.map((item) {
                                final Medicine med = item['medicine'];
                                final int dispensingStock = item['dispensingStock'];
                                final double daily = item['daily'];
                                final int requiredStock = item['requiredStock'];
                                final int deficit = item['deficit'];
                                 final int bulkStock = item['bulkStock'];
                                final bool canFulfillFromBulk = bulkStock >= deficit;

                                return DataRow(
                                  onSelectChanged: (_) => _showStockDetailsDialog(context, med, item),
                                  cells: [
                                    DataCell(
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            med.name,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          Text(
                                            med.category.isEmpty ? 'General' : med.category,
                                            style: TextStyle(fontSize: 11, color: context.textMutedColor),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DataCell(Text('${med.storeStock}')),
                                    DataCell(Text('${med.mainStock}')),
                                    DataCell(
                                      Text(
                                        '$dispensingStock',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    DataCell(Text('${daily.toStringAsFixed(1)} /day')),
                                    DataCell(Text('$requiredStock units')),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppTheme.danger.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '-$deficit',
                                          style: const TextStyle(
                                            color: AppTheme.danger,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '$bulkStock',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: canFulfillFromBulk ? AppTheme.emerald : AppTheme.orange,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: (canFulfillFromBulk ? AppTheme.emerald : AppTheme.orange).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              canFulfillFromBulk ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                              size: 14,
                                              color: canFulfillFromBulk ? AppTheme.emerald : AppTheme.orange,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              canFulfillFromBulk ? 'Ready in Bulk' : 'Order Bulk',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: canFulfillFromBulk ? AppTheme.emerald : AppTheme.orange,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textMutedColor),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: context.textMutedColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showStockDetailsDialog(BuildContext context, Medicine med, Map<String, dynamic> item) {
    final int dispensingStock = item['dispensingStock'];
    final double daily = item['daily'];
    final int requiredStock = item['requiredStock'];
    final int deficit = item['deficit'];

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: ctx.surfaceColor,
          child: Container(
            width: 520,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.inventory_2_rounded, color: AppTheme.primary, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            med.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Category: ${med.category.isEmpty ? "General" : med.category}${med.barcode.isNotEmpty ? " | Barcode: ${med.barcode}" : ""}',
                            style: TextStyle(fontSize: 12, color: ctx.textMutedColor),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Stock Breakdown Cards Row
                Row(
                  children: [
                    Expanded(
                      child: _buildDialogMetricBox(
                        ctx,
                        label: 'Store Stock',
                        value: '${med.storeStock}',
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDialogMetricBox(
                        ctx,
                        label: 'Clinic Stock',
                        value: '${med.mainStock}',
                        color: AppTheme.indigo,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDialogMetricBox(
                        ctx,
                        label: 'Dispensing Total',
                        value: '$dispensingStock',
                        color: AppTheme.warning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Secondary Details Container
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: ctx.bgColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ctx.borderColor.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('30-Day Daily Consumption (ADC):', style: TextStyle(fontSize: 13, color: ctx.textMutedColor)),
                          Text('${daily.toStringAsFixed(1)} units/day', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Target Buffer Requirement ($_targetDays Days):', style: TextStyle(fontSize: 13, color: ctx.textMutedColor)),
                          Text('$requiredStock units', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Replenishment Deficit:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('-$deficit units', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.danger)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total Bulk Warehouse Stock:', style: TextStyle(fontSize: 13, color: ctx.textMutedColor)),
                          Text(
                            '${med.bulkStoreStock + med.bulkClinicStock} units (${(med.bulkStoreStock + med.bulkClinicStock) >= deficit ? "Available" : "Shortage"})',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: (med.bulkStoreStock + med.bulkClinicStock) >= deficit ? AppTheme.emerald : AppTheme.orange,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.storefront_rounded, size: 18),
                      label: const Text('Transfer to Store'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        final fullQty = deficit > 0 ? deficit : 1;
                        showDialog(
                          context: context,
                          builder: (dialogCtx) => TransferDialog(
                            medicine: med,
                            from: 'bulkStore',
                            to: 'store',
                            initialQty: fullQty,
                            wh: context.read<WarehouseProvider>(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.local_hospital_rounded, size: 18),
                      label: const Text('Transfer to Clinic'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        final fullQty = deficit > 0 ? deficit : 1;
                        showDialog(
                          context: context,
                          builder: (dialogCtx) => TransferDialog(
                            medicine: med,
                            from: 'bulkClinic',
                            to: 'clinic',
                            initialQty: fullQty,
                            wh: context.read<WarehouseProvider>(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDialogMetricBox(BuildContext context, {required String label, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.textMutedColor)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
