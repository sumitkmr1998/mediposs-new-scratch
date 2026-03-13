import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/hub_provider.dart';
import '../theme/app_theme.dart';
import '../services/export_service.dart';

class ReorderScreen extends StatelessWidget {
  const ReorderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubProvider>();

    // Build reorder list sorted by urgency
    final reorderList =
        hub.medicines
            .map((m) {
              final dailyAvg = hub.dailyConsumption(m.id);
              final daysLeft = hub.daysOfStockRemaining(m.id);
              final suggestedQty = dailyAvg > 0
                  ? ((30 * dailyAvg) - m.totalStock).ceil()
                  : 0;
              return _ReorderItem(
                medicine: m,
                dailyAvg: dailyAvg,
                daysLeft: daysLeft,
                suggestedQty: suggestedQty > 0 ? suggestedQty : 0,
              );
            })
            .where((r) => r.daysLeft < 14 && r.daysLeft < 999)
            .toList()
          ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));

    final criticalCount = reorderList.where((r) => r.daysLeft < 3).length;
    final warningCount = reorderList
        .where((r) => r.daysLeft >= 3 && r.daysLeft < 7)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Reorder'),
        backgroundColor: Colors.orange.withValues(alpha: 0.1),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export PDF',
            onPressed: () async {
              final path = await ExportService.exportReorderPDF(
                hub.medicines,
                hub.dailyConsumption,
                hub.daysOfStockRemaining,
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('✅ Reorder PDF saved to: $path')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
            onPressed: () async {
              final path = await ExportService.exportReorderCSV(
                hub.medicines,
                hub.dailyConsumption,
                hub.daysOfStockRemaining,
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('✅ Reorder CSV saved to: $path')),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Summary banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: AppTheme.surface,
            child: Row(
              children: [
                _UrgencyBadge(
                  count: criticalCount,
                  label: 'Critical',
                  color: AppTheme.danger,
                ),
                const SizedBox(width: 16),
                _UrgencyBadge(
                  count: warningCount,
                  label: 'Warning',
                  color: Colors.orange,
                ),
                const SizedBox(width: 16),
                _UrgencyBadge(
                  count: reorderList.length - criticalCount - warningCount,
                  label: 'Monitor',
                  color: AppTheme.info,
                ),
                const Spacer(),
                Text(
                  '${reorderList.length} items need attention',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Reorder list
          Expanded(
            child: reorderList.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 64,
                          color: AppTheme.success,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'All stock levels are healthy!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'No items need reordering in the next 14 days.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: reorderList.length,
                    itemBuilder: (context, index) {
                      final r = reorderList[index];
                      final urgencyColor = r.daysLeft < 3
                          ? AppTheme.danger
                          : r.daysLeft < 7
                          ? Colors.orange
                          : AppTheme.info;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              // Urgency indicator
                              Container(
                                width: 6,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: urgencyColor,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 16),

                              // Medicine info
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.medicine.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${r.medicine.category} • ${r.medicine.unit}',
                                      style: TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Stats
                              Expanded(
                                flex: 4,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    _StatCol(
                                      label: 'Stock',
                                      value: '${r.medicine.totalStock}',
                                    ),
                                    _StatCol(
                                      label: 'Daily Avg',
                                      value: r.dailyAvg.toStringAsFixed(1),
                                    ),
                                    _StatCol(
                                      label: 'Days Left',
                                      value: r.daysLeft.toStringAsFixed(0),
                                      valueColor: urgencyColor,
                                    ),
                                    _StatCol(
                                      label: 'Order Qty',
                                      value: '${r.suggestedQty}',
                                      valueColor: AppTheme.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReorderItem {
  final dynamic medicine;
  final double dailyAvg;
  final double daysLeft;
  final int suggestedQty;

  _ReorderItem({
    required this.medicine,
    required this.dailyAvg,
    required this.daysLeft,
    required this.suggestedQty,
  });
}

class _UrgencyBadge extends StatelessWidget {
  final int count;
  final String label;
  final Color color;

  const _UrgencyBadge({
    required this.count,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontSize: 13)),
        ],
      ),
    );
  }
}

class _StatCol extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatCol({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppTheme.textDark,
          ),
        ),
      ],
    );
  }
}
