import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/hub_provider.dart';
import '../theme/app_theme.dart';

class TopMedicinesList extends StatelessWidget {
  const TopMedicinesList({super.key});

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubProvider>();

    // Sort medicines by storeStock as a simple "consumption" proxy for now.
    // In a real app, we'd iterate through Sale items to find the most sold.
    // For this dashboard, we'll sort by lowest stock relative to a baseline,
    // or just show a subset of the catalog. Let's do lowest stock first.
    final List<dynamic> sortedMeds = List.from(hub.medicines)
      ..sort((a, b) => a.storeStock.compareTo(b.storeStock));

    final topMeds = sortedMeds.take(5).toList();

    if (topMeds.isEmpty) {
      return const Center(child: Text('No medicines found.'));
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: topMeds.length,
      itemBuilder: (ctx, i) {
        final med = topMeds[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.medication, color: AppTheme.primary),
          ),
          title: Text(
            med.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text('Category: ${med.category}'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Stock: ${med.storeStock}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: med.storeStock < 10
                      ? AppTheme.danger
                      : AppTheme.textDark,
                ),
              ),
               Text(
                 '₹${med.sellingPrice}',
                 style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
               ),
            ],
          ),
        );
      },
    );
  }
}
