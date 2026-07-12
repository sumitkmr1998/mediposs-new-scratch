import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/providers/sales_provider.dart';
import '../../../../shared/utils/analytics_helper.dart';
import '../../../../theme/app_theme.dart';

class ReorderAndDeadStockTab extends StatefulWidget {
  const ReorderAndDeadStockTab({super.key});

  @override
  State<ReorderAndDeadStockTab> createState() => _ReorderAndDeadStockTabState();
}

class _ReorderAndDeadStockTabState extends State<ReorderAndDeadStockTab> {
  int _reorderTrendDays = 30;
  int _reorderDepletionDays = 90;
  int _reorderTargetDays = 365;

  Widget _buildConfigDropdown<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: context.textMutedColor),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.bgColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.borderColor.withValues(alpha: 0.15)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              onChanged: onChanged,
              dropdownColor: context.surfaceColor,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textColor),
              icon: Icon(Icons.arrow_drop_down, size: 18, color: context.textMutedColor),
              items: items.entries.map((e) {
                return DropdownMenuItem<T>(
                  value: e.key,
                  child: Text(e.value),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final salesProvider = context.watch<SalesProvider>();

    final medicines = inventory.rawMedicines;
    final sales = salesProvider.rawSales;

    final reorders = AnalyticsHelper.getReorderList(
      medicines,
      sales,
      trendDays: _reorderTrendDays,
      depletionDaysThreshold: _reorderDepletionDays,
      targetStockDays: _reorderTargetDays,
    );
    final deadStock = AnalyticsHelper.getDeadStock(medicines, sales, 60); // 60 days dead stock default

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Configuration Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.borderColor.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.settings_suggest_rounded, color: AppTheme.primary, size: 22),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reorder Calculation Settings',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      'Adjust ranges to update log dynamically based on consumption speed.',
                      style: TextStyle(fontSize: 11, color: context.textMutedColor),
                    ),
                  ],
                ),
                const Spacer(),
                
                // 1. Trend Window Selector
                _buildConfigDropdown<int>(
                  label: 'TREND ANALYSIS WINDOW',
                  value: _reorderTrendDays,
                  items: {
                    15: 'Last 15 Days',
                    30: 'Last 30 Days (Default)',
                    90: 'Last 90 Days',
                    180: 'Last 180 Days',
                  },
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _reorderTrendDays = val);
                    }
                  },
                ),
                const SizedBox(width: 16),

                // 2. Depletion Alert Threshold
                _buildConfigDropdown<int>(
                  label: 'DEPLETION TRIGGER HORIZON',
                  value: _reorderDepletionDays,
                  items: {
                    30: '30 Days (1 Month)',
                    60: '60 Days (2 Months)',
                    90: '90 Days (3 Months)',
                    180: '180 Days (6 Months)',
                  },
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _reorderDepletionDays = val);
                    }
                  },
                ),
                const SizedBox(width: 16),

                // 3. Target Restock Duration
                _buildConfigDropdown<int>(
                  label: 'SUGGESTED STOCK TARGET',
                  value: _reorderTargetDays,
                  items: {
                    90: '90 Days (3 Months)',
                    180: '180 Days (6 Months)',
                    365: '365 Days (1 Year)',
                    730: '730 Days (2 Years)',
                  },
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _reorderTargetDays = val);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('🚨 Urgent Reorder Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: AppTheme.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                              child: Text('${reorders.length} Items', style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: reorders.isEmpty
                              ? const Center(child: Text('All stock levels are completely healthy.'))
                              : ListView.builder(
                                  itemCount: reorders.length,
                                  itemBuilder: (context, idx) {
                                    final rec = reorders[idx];
                                    final isCritical = rec.medicine.totalStock <= (rec.medicine.lowStockThreshold / 2);
                                    return Container(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: context.surfaceColor,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: (isCritical ? AppTheme.danger : Colors.orange).withValues(alpha: 0.15)),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: (isCritical ? AppTheme.danger : Colors.orange).withValues(alpha: 0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              isCritical ? Icons.gpp_bad_rounded : Icons.warning_amber_rounded,
                                              color: isCritical ? AppTheme.danger : Colors.orange,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(rec.medicine.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Stock: ${rec.medicine.totalStock} ${rec.medicine.unit} (Daily consumption: ${rec.dailyVelocity.toStringAsFixed(2)}/d)',
                                                  style: TextStyle(color: context.textMutedColor, fontSize: 11),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text('Suggest: +${rec.suggestedReorderQty}', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                                              const SizedBox(height: 2),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: (rec.daysLeft < 7 ? AppTheme.danger : Colors.grey).withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  rec.daysLeft >= 999.0 ? 'Life: ∞' : 'Life: ${rec.daysLeft.toStringAsFixed(0)}d',
                                                  style: TextStyle(
                                                    color: rec.daysLeft < 7 ? AppTheme.danger : context.textMutedColor,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
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
              Expanded(
                flex: 1,
                child: Card(
                  margin: const EdgeInsets.fromLTRB(0, 24, 24, 24),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('⚠️ Sluggish / Dead Stock (60 Days)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                              child: Text('${deadStock.length} Items', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: deadStock.isEmpty
                              ? const Center(child: Text('No slow-moving stocks detected.'))
                              : ListView.builder(
                                  itemCount: deadStock.length,
                                  itemBuilder: (context, idx) {
                                    final med = deadStock[idx];
                                    final lockedValue = med.totalStock * med.purchasePrice;
                                    return Container(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: context.surfaceColor,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.grey.withValues(alpha: 0.08)),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.withValues(alpha: 0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.inventory_2_outlined, color: Colors.grey, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(med.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                const SizedBox(height: 2),
                                                Text('Category: ${med.category}', style: TextStyle(color: context.textMutedColor, fontSize: 11)),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text('${med.totalStock} ${med.unit} left', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                              const SizedBox(height: 2),
                                              Text('Value: ₹${lockedValue.toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 11)),
                                            ],
                                          ),
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
          ),
        ),
      ],
    );
  }
}
