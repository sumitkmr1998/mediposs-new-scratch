import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/hub_provider.dart';
import '../theme/app_theme.dart';

class CustomerAnalyticsScreen extends StatelessWidget {
  const CustomerAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubProvider>();
    final topCustomers = hub.topCustomers(limit: 20);

    // Customer visit frequency
    final visitCounts = <String, int>{};
    for (final sale in hub.sales) {
      if (sale.isReturn) continue;
      visitCounts[sale.patientName] = (visitCounts[sale.patientName] ?? 0) + 1;
    }

    // Frequently bought together (co-occurrence in same invoice)
    final coOccurrence = <String, int>{};
    for (final sale in hub.sales) {
      if (sale.isReturn || sale.items.length < 2) continue;
      final names = sale.items.map((i) => i.medicineName).toList();
      for (int i = 0; i < names.length; i++) {
        for (int j = i + 1; j < names.length; j++) {
          final pair = [names[i], names[j]]..sort();
          final key = '${pair[0]} + ${pair[1]}';
          coOccurrence[key] = (coOccurrence[key] ?? 0) + 1;
        }
      }
    }
    final topPairs = coOccurrence.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Analytics'),
        backgroundColor: Colors.teal.withValues(alpha: 0.1),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top customers by spend
            Text(
              'Top Customers by Spend',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(
                      label: Text(
                        '#',
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
                        'Total Spend',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text(
                        'Visits',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text(
                        'Avg/Visit',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      numeric: true,
                    ),
                  ],
                  rows: topCustomers.asMap().entries.map((entry) {
                    final c = entry.value;
                    final visits = visitCounts[c.key] ?? 1;
                    final avgVisit = c.value / visits;
                    return DataRow(
                      cells: [
                        DataCell(Text('${entry.key + 1}')),
                        DataCell(
                          Text(
                            c.key,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        DataCell(Text('₹${c.value.toStringAsFixed(0)}')),
                        DataCell(Text('$visits')),
                        DataCell(Text('₹${avgVisit.toStringAsFixed(0)}')),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Frequently bought together
            Text(
              'Frequently Bought Together',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(
              child: topPairs.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Not enough data to determine buying patterns.',
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: topPairs.take(15).length,
                      itemBuilder: (context, index) {
                        final pair = topPairs[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primary.withValues(
                              alpha: 0.1,
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            pair.key,
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${pair.value}×',
                              style: const TextStyle(
                                color: AppTheme.success,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
