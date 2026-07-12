import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/models/medicine.dart';
import '../../../../shared/models/sale.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/providers/sales_provider.dart';
import '../../../../shared/services/objectbox_service.dart';
import '../../../../shared/utils/analytics_helper.dart';
import '../../../../theme/app_theme.dart';

class ClinicReconciliationTab extends StatefulWidget {
  const ClinicReconciliationTab({super.key});

  @override
  State<ClinicReconciliationTab> createState() => _ClinicReconciliationTabState();
}

class _ClinicReconciliationTabState extends State<ClinicReconciliationTab> {
  String _clinicSearchQuery = '';

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final salesProvider = context.watch<SalesProvider>();

    final medicines = inventory.rawMedicines;
    final sales = salesProvider.rawSales;

    final allTransfers = ObjectBoxService.instance.transferBox.getAll();
    final medMap = {for (var m in medicines) m.name.toLowerCase().trim(): m.id};

    // Map of local medicineId -> totalTransferred (to main)
    final transferMap = <int, int>{};
    for (final transfer in allTransfers) {
      final localId = medMap[transfer.medicineName.toLowerCase().trim()];
      if (localId != null) {
        if (transfer.toWarehouse == 'main' || transfer.toWarehouse == 'clinic') {
          transferMap[localId] = (transferMap[localId] ?? 0) + transfer.qty;
        }
        if (transfer.fromWarehouse == 'main' || transfer.fromWarehouse == 'clinic') {
          transferMap[localId] = (transferMap[localId] ?? 0) - transfer.qty;
        }
      }
    }

    // Map of local medicineId -> totalConsumed (clinical dispenses)
    final consumeMap = <int, int>{};
    for (final sale in sales) {
      if (sale.isClinicalDispense) {
        for (final item in AnalyticsHelper.getItems(sale)) {
          if (!item.isProcedure) {
            final localId = medMap[item.medicineName.toLowerCase().trim()];
            if (localId != null) {
              consumeMap[localId] = (consumeMap[localId] ?? 0) + item.qty;
            }
          }
        }
      }
    }

    final relevantMedicineIds = <int>{};
    for (final mId in transferMap.keys) {
      relevantMedicineIds.add(mId);
    }
    for (final mId in consumeMap.keys) {
      relevantMedicineIds.add(mId);
    }
    for (final med in medicines) {
      if (med.mainStock > 0) {
        relevantMedicineIds.add(med.id);
      }
    }

    final reconciliationRows = <ClinicReconciliationRow>[];
    for (final mId in relevantMedicineIds) {
      final med = medicines.firstWhere((m) => m.id == mId, orElse: () => Medicine(
        name: 'Unknown Medicine (ID: $mId)',
        purchasePrice: 0,
        sellingPrice: 0,
      )..id = mId);

      final totalTransferred = transferMap[mId] ?? 0;
      final totalConsumed = consumeMap[mId] ?? 0;
      final currentStock = med.mainStock;
      final expectedStock = totalTransferred - totalConsumed;
      final variance = currentStock - expectedStock;

      if (_clinicSearchQuery.isNotEmpty && !med.name.toLowerCase().contains(_clinicSearchQuery.toLowerCase())) {
        continue;
      }

      reconciliationRows.add(ClinicReconciliationRow(
        medicineId: mId,
        medicineName: med.name,
        totalTransferred: totalTransferred,
        totalConsumed: totalConsumed,
        currentStock: currentStock,
        variance: variance,
      ));
    }

    // Sort by largest absolute variance first, then alphabetically
    reconciliationRows.sort((a, b) {
      final vComp = b.variance.abs().compareTo(a.variance.abs());
      if (vComp != 0) return vComp;
      return a.medicineName.compareTo(b.medicineName);
    });

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clinic Stock Reconciliation',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tracks stock transferred from store warehouse vs clinical dispense internal consumption.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: 320,
                child: TextField(
                  onChanged: (val) {
                    setState(() {
                      _clinicSearchQuery = val;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search clinic medicine...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Expanded(flex: 3, child: Text('Medicine Name', style: TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(flex: 2, child: Text('Total Transferred (In)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text('Total Consumed (Out)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text('Current Clinic Stock', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text('Variance', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: reconciliationRows.isEmpty
                          ? const Center(child: Text('No clinic medicines or transaction data found.'))
                          : ListView.separated(
                              itemCount: reconciliationRows.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (context, index) {
                                final row = reconciliationRows[index];

                                Color varianceColor = Colors.grey;
                                IconData? varianceIcon;
                                if (row.variance < 0) {
                                  varianceColor = AppTheme.danger;
                                  varianceIcon = Icons.warning_amber_rounded;
                                } else if (row.variance > 0) {
                                  varianceColor = AppTheme.success;
                                  varianceIcon = Icons.add_circle_outline_rounded;
                                }

                                final varianceText = row.variance > 0 ? '+${row.variance}' : '${row.variance}';

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Text(row.medicineName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text('${row.totalTransferred}', textAlign: TextAlign.center),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text('${row.totalConsumed}', textAlign: TextAlign.center),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text('${row.currentStock}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            if (varianceIcon != null) ...[
                                              Icon(varianceIcon, size: 16, color: varianceColor),
                                              const SizedBox(width: 4),
                                            ],
                                            Text(
                                              varianceText,
                                              style: TextStyle(
                                                color: varianceColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
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
    );
  }
}

class ClinicReconciliationRow {
  final int medicineId;
  final String medicineName;
  final int totalTransferred;
  final int totalConsumed;
  final int currentStock;
  final int variance;

  ClinicReconciliationRow({
    required this.medicineId,
    required this.medicineName,
    required this.totalTransferred,
    required this.totalConsumed,
    required this.currentStock,
    required this.variance,
  });
}
