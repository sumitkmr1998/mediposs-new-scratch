import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/hub_provider.dart';
import '../theme/app_theme.dart';

class DeadStockScreen extends StatefulWidget {
  const DeadStockScreen({super.key});

  @override
  State<DeadStockScreen> createState() => _DeadStockScreenState();
}

class _DeadStockScreenState extends State<DeadStockScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubProvider>();
    final deadItems = hub.deadStock(daysSinceLastSale: _days);

    // Calculate total capital locked
    final totalCapital = deadItems.fold(
      0.0,
      (sum, m) => sum + (m.storeStock * m.purchasePrice),
    );

    // Sort by capital locked descending
    deadItems.sort(
      (a, b) => (b.storeStock * b.purchasePrice).compareTo(
        a.storeStock * a.purchasePrice,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dead Stock'),
        backgroundColor: AppTheme.danger.withValues(alpha: 0.1),
      ),
      body: Column(
        children: [
          // Summary header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            color: AppTheme.surface,
            child: Row(
              children: [
                // Period toggle
                Row(
                  children: [30, 60, 90].map((d) {
                    final isSelected = d == _days;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('$d days'),
                        selected: isSelected,
                        onSelected: (_) => setState(() => _days = d),
                        selectedColor: AppTheme.danger.withValues(alpha: 0.2),
                      ),
                    );
                  }).toList(),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Capital Locked',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                    Text(
                      '₹${totalCapital.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.danger,
                      ),
                    ),
                    Text(
                      '${deadItems.length} items',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Dead stock list
          Expanded(
            child: deadItems.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.thumb_up, size: 64, color: AppTheme.success),
                        SizedBox(height: 16),
                        Text(
                          'No dead stock!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'All your items have been selling.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: deadItems.length,
                    itemBuilder: (context, index) {
                      final m = deadItems[index];
                      final capitalLocked = m.storeStock * m.purchasePrice;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.inventory_2,
                              color: AppTheme.danger,
                            ),
                          ),
                          title: Text(
                            m.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${m.category} • Stock: ${m.storeStock} ${m.unit}',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₹${capitalLocked.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.danger,
                                  fontSize: 16,
                                ),
                              ),
                              const Text(
                                'locked',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
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
