import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:excel/excel.dart' as excel_pkg;

import '../../../../shared/models/medicine.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/providers/sales_provider.dart';
import '../../../../shared/services/clinic_reconciliation_service.dart';
import '../../../../shared/services/objectbox_service.dart';
import '../../../../shared/utils/analytics_helper.dart';
import '../../../../theme/app_theme.dart';

enum ReconciliationScope {
  all,    // Clinic + Store combined
  clinic, // Clinic dispensary only
  store,  // Store warehouse only
}

class ClinicReconciliationTab extends StatefulWidget {
  const ClinicReconciliationTab({super.key});

  @override
  State<ClinicReconciliationTab> createState() => _ClinicReconciliationTabState();
}

class _ClinicReconciliationTabState extends State<ClinicReconciliationTab> {
  String _clinicSearchQuery = '';
  bool _viewSinceBaseline = true;
  ReconciliationScope _scope = ReconciliationScope.all;

  // Physical Stocktake Mode
  bool _isAuditMode = false;
  final Map<int, int> _physicalCounts = {};
  String _statusFilter = 'all'; // 'all', 'deficit', 'surplus', 'balanced'

  @override
  void initState() {
    super.initState();
    ClinicReconciliationService.instance.init().then((_) {
      if (mounted) setState(() {});
    });
    ClinicReconciliationService.instance.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    ClinicReconciliationService.instance.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _exportToExcel(List<ClinicReconciliationRow> rows) async {
    try {
      final excel = excel_pkg.Excel.createExcel();
      const sheetName = 'Stock Reconciliation';
      final sheet = excel[sheetName];
      excel.delete('Sheet1');

      final service = ClinicReconciliationService.instance;
      final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
      final exportDate = dateFormat.format(DateTime.now());
      final baselineInfo = service.hasActiveBaseline
          ? 'Active since: ${dateFormat.format(service.baselineDate!)} by ${service.performedBy ?? "Staff"}'
          : 'All-Time Cumulative History (No Baseline)';

      final scopeLabel = _scope == ReconciliationScope.all
          ? 'All Stock (Clinic + Store)'
          : (_scope == ReconciliationScope.clinic ? 'Clinic Dispensary Only' : 'Store Warehouse Only');

      // Title & Meta rows
      sheet.appendRow([excel_pkg.TextCellValue('MEDIPOSS STOCK RECONCILIATION & AUDIT REPORT')]);
      sheet.appendRow([excel_pkg.TextCellValue('Exported At: $exportDate')]);
      sheet.appendRow([excel_pkg.TextCellValue('Scope: $scopeLabel')]);
      sheet.appendRow([excel_pkg.TextCellValue('Baseline Status: $baselineInfo')]);
      sheet.appendRow([]); // empty row

      // Header row
      sheet.appendRow([
        excel_pkg.TextCellValue('Medicine Name'),
        excel_pkg.TextCellValue('Baseline Stock'),
        excel_pkg.TextCellValue('Transferred (Net)'),
        excel_pkg.TextCellValue('Dispensed (OPD)'),
        excel_pkg.TextCellValue('Retail Sold (Store)'),
        excel_pkg.TextCellValue('Total Outflow'),
        excel_pkg.TextCellValue('Expected Stock'),
        excel_pkg.TextCellValue('System Stock'),
        if (_isAuditMode) excel_pkg.TextCellValue('Physical Count (Shelf)'),
        if (_isAuditMode) excel_pkg.TextCellValue('Physical Discrepancy'),
        excel_pkg.TextCellValue('System Variance'),
        excel_pkg.TextCellValue('Status'),
      ]);

      for (final r in rows) {
        String status = 'Balanced';
        if (r.variance < 0) {
          status = 'Deficit (Shortage)';
        } else if (r.variance > 0) {
          status = 'Surplus';
        }

        final physCount = _physicalCounts[r.medicineId] ?? r.currentStock;
        final physDiscrepancy = physCount - r.currentStock;

        final rowCells = <excel_pkg.CellValue>[
          excel_pkg.TextCellValue(r.medicineName),
          excel_pkg.IntCellValue(r.baselineStock),
          excel_pkg.IntCellValue(r.totalTransferred),
          excel_pkg.IntCellValue(r.dispensedQty),
          excel_pkg.IntCellValue(r.retailSoldQty),
          excel_pkg.IntCellValue(r.totalConsumed),
          excel_pkg.IntCellValue(r.expectedStock),
          excel_pkg.IntCellValue(r.currentStock),
        ];

        if (_isAuditMode) {
          rowCells.add(excel_pkg.IntCellValue(physCount));
          rowCells.add(excel_pkg.IntCellValue(physDiscrepancy));
        }

        rowCells.add(excel_pkg.IntCellValue(r.variance));
        rowCells.add(excel_pkg.TextCellValue(status));

        sheet.appendRow(rowCells);
      }

      final dir = await getApplicationDocumentsDirectory();
      final dateStr = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
      final file = File(p.join(dir.path, 'Stock_Reconciliation_$dateStr.xlsx'));
      final bytes = excel.encode();

      if (bytes != null) {
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Reconciliation report exported successfully:\n${file.path}'),
              backgroundColor: AppTheme.success,
              action: SnackBarAction(
                label: 'Open Folder',
                textColor: Colors.white,
                onPressed: () {
                  final uri = Uri.directory(dir.path);
                  launchUrl(uri);
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export report: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _exportComparativeHistoryToExcel() async {
    try {
      final inv = context.read<InventoryProvider>();
      final salesProvider = context.read<SalesProvider>();
      final transfers = ObjectBoxService.instance.transferBox.getAll();
      final service = ClinicReconciliationService.instance;

      final file = await service.exportAuditHistoryComparisonToExcel(
        medicines: inv.rawMedicines,
        allTransfers: transfers,
        allSales: salesProvider.rawSales,
      );

      if (file != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Audit History comparison exported successfully:\n${file.path}'),
            backgroundColor: AppTheme.success,
            action: SnackBarAction(
              label: 'Open Folder',
              textColor: Colors.white,
              onPressed: () {
                final uri = Uri.directory(file.parent.path);
                launchUrl(uri);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export audit history comparison: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _showSingleMedicineAdjustDialog(Medicine med, int currentStock) async {
    final actor = context.read<AuthProvider>().currentUser;
    final inv = context.read<InventoryProvider>();
    final countCtrl = TextEditingController(text: currentStock.toString());
    final reasonCtrl = TextEditingController(text: 'Physical count adjustment');

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Adjust Stock: ${med.name}', style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current System Stock: $currentStock', style: const TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: countCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Actual Physical Count on Shelf',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason for Adjustment',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.comment_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save Count'),
          ),
        ],
      ),
    );

    if (updated == true) {
      final newCount = int.tryParse(countCtrl.text.trim()) ?? currentStock;
      if (_scope == ReconciliationScope.store) {
        if (newCount != med.storeStock) {
          await inv.adjustStockForPhysicalAudit(
            med,
            targetStoreStock: newCount,
            reason: reasonCtrl.text.trim(),
            actor: actor,
          );
        }
      } else if (_scope == ReconciliationScope.clinic) {
        if (newCount != med.mainStock) {
          await inv.adjustStockForPhysicalAudit(
            med,
            targetClinicStock: newCount,
            reason: reasonCtrl.text.trim(),
            actor: actor,
          );
        }
      } else {
        // ReconciliationScope.all: adjust difference on clinic stock
        final totalOld = med.mainStock + med.storeStock;
        final diff = newCount - totalOld;
        if (diff != 0) {
          final newClinic = (med.mainStock + diff).clamp(0, 999999);
          await inv.adjustStockForPhysicalAudit(
            med,
            targetClinicStock: newClinic,
            reason: reasonCtrl.text.trim(),
            actor: actor,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stock for ${med.name} updated to $newCount.'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
  }

  Future<void> _showApplyPhysicalAuditDialog(List<Medicine> medicines) async {
    final actor = context.read<AuthProvider>().currentUser;
    final inv = context.read<InventoryProvider>();

    int changedCount = 0;
    int netShrinkage = 0;

    for (final m in medicines) {
      final phys = _physicalCounts[m.id];
      if (phys != null) {
        final current = _scope == ReconciliationScope.store
            ? m.storeStock
            : (_scope == ReconciliationScope.all ? m.mainStock + m.storeStock : m.mainStock);
        if (phys != current) {
          changedCount++;
          netShrinkage += (phys - current);
        }
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.inventory_2_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Text('Apply Physical Stocktake & Reset'),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have counted ${medicines.length} medicines ($changedCount with physical discrepancies).',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              '• App inventory will be modified to match shelf counts directly.\n'
              '• Net discrepancy: ${netShrinkage >= 0 ? "+$netShrinkage" : "$netShrinkage"} units recorded.\n'
              '• Discrepancies (unbilled sales/losses) will be logged in the permanent audit trail.\n'
              '• The audit baseline will be set to right now with variance reset to 0.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.success,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.check_circle_rounded, size: 18),
          onPressed: () => Navigator.pop(ctx, true),
          label: const Text('Confirm & Apply Counts'),
        ),
      ],
    ),
  );

    if (confirmed == true) {
      for (final m in medicines) {
        final phys = _physicalCounts[m.id];
        if (phys != null) {
          if (_scope == ReconciliationScope.store) {
            if (phys != m.storeStock) {
              await inv.adjustStockForPhysicalAudit(
                m,
                targetStoreStock: phys,
                reason: 'Physical stocktake verification',
                actor: actor,
              );
            }
          } else if (_scope == ReconciliationScope.clinic) {
            if (phys != m.mainStock) {
              await inv.adjustStockForPhysicalAudit(
                m,
                targetClinicStock: phys,
                reason: 'Physical stocktake verification',
                actor: actor,
              );
            }
          } else {
            // Scope All: phys is total counted (clinic + store)
            final currentTotal = m.mainStock + m.storeStock;
            final diff = phys - currentTotal;
            if (diff != 0) {
              final newClinic = (m.mainStock + diff).clamp(0, 999999);
              await inv.adjustStockForPhysicalAudit(
                m,
                targetClinicStock: newClinic,
                reason: 'Physical stocktake verification (All scope)',
                actor: actor,
              );
            }
          }
        }
      }

      // Re-baseline with updated physical numbers
      await ClinicReconciliationService.instance.setBaseline(
        medicines: inv.rawMedicines,
        actor: actor,
      );

      if (mounted) {
        setState(() {
          _isAuditMode = false;
          _physicalCounts.clear();
          _viewSinceBaseline = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Physical counts applied! App stock synchronized with shelf and baseline reset to 0.'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
  }

  Future<void> _showResetBaselineDialog(List<Medicine> medicines) async {
    final actor = context.read<AuthProvider>().currentUser;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.fact_check_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Text('Reset Reconciliation Baseline'),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to snapshot current stock as the new audit baseline?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 12),
              const Text(
                '• Current on-hand stock (Clinic and Store) will be snapshotted as the verified starting baseline.\n'
                '• All previous discrepancies will be resolved to 0 as of right now.\n'
                '• Future clinic dispenses, retail counter sales, and transfers will track variance starting from this moment.\n'
                '• An immutable audit log entry will be saved and synced to all devices.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 20, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Total medicines to baseline: ${medicines.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.check_rounded, size: 18),
            onPressed: () => Navigator.pop(ctx, true),
            label: const Text('Confirm & Reset Baseline'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ClinicReconciliationService.instance.setBaseline(
        medicines: medicines,
        actor: actor,
      );
      if (mounted) {
        setState(() => _viewSinceBaseline = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audit baseline active! All stock variances reset to 0.'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
  }

  Future<void> _showClearBaselineDialog() async {
    final actor = context.read<AuthProvider>().currentUser;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.history_rounded, color: AppTheme.warning),
            SizedBox(width: 8),
            Text('Revert to All-Time Cumulative?'),
          ],
        ),
        content: const Text(
          'This will remove the active baseline snapshot and show cumulative variances from the very beginning of the database.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Clear Baseline'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ClinicReconciliationService.instance.clearBaseline(actor: actor);
      if (mounted) {
        setState(() => _viewSinceBaseline = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audit baseline cleared. Showing all-time history.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final salesProvider = context.watch<SalesProvider>();
    final service = ClinicReconciliationService.instance;

    final medicines = inventory.rawMedicines;
    final sales = salesProvider.rawSales;

    final allTransfers = ObjectBoxService.instance.transferBox.getAll();
    final medMap = {for (var m in medicines) m.name.toLowerCase().trim(): m.id};

    final isBaselineActive = service.hasActiveBaseline;
    final effectiveSinceBaseline = isBaselineActive && _viewSinceBaseline;
    final baselineDate = service.baselineDate;
    final baselineEndDate = effectiveSinceBaseline ? service.currentBaselineEndDate : null;
    final nextBaseline = effectiveSinceBaseline ? service.nextBaseline : null;
    final isHistoricalCycle = effectiveSinceBaseline && baselineEndDate != null;

    final transferMap = <int, int>{};
    for (final transfer in allTransfers) {
      if (effectiveSinceBaseline && baselineDate != null) {
        if (transfer.transferredAt.isBefore(baselineDate)) {
          continue;
        }
        if (baselineEndDate != null && transfer.transferredAt.isAfter(baselineEndDate)) {
          continue;
        }
      }

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

    final dispenseMap = <int, int>{};
    final retailMap = <int, int>{};

    for (final sale in sales) {
      if (effectiveSinceBaseline && baselineDate != null) {
        if (sale.createdAt.isBefore(baselineDate)) {
          continue;
        }
        if (baselineEndDate != null && sale.createdAt.isAfter(baselineEndDate)) {
          continue;
        }
      }

      final isClinical = sale.isClinicalDispense;
      for (final item in AnalyticsHelper.getItems(sale)) {
        if (!item.isProcedure) {
          final localId = medMap[item.medicineName.toLowerCase().trim()];
          if (localId != null) {
            if (isClinical) {
              dispenseMap[localId] = (dispenseMap[localId] ?? 0) + item.qty;
            } else {
              retailMap[localId] = (retailMap[localId] ?? 0) + item.qty;
            }
          }
        }
      }
    }

    final relevantMedicineIds = <int>{};
    for (final mId in transferMap.keys) {
      relevantMedicineIds.add(mId);
    }
    for (final mId in dispenseMap.keys) {
      relevantMedicineIds.add(mId);
    }
    for (final mId in retailMap.keys) {
      relevantMedicineIds.add(mId);
    }
    for (final med in medicines) {
      if (med.mainStock > 0 || med.storeStock > 0) {
        relevantMedicineIds.add(med.id);
      } else if (effectiveSinceBaseline && service.getBaselineTotalStock(med.id) > 0) {
        relevantMedicineIds.add(med.id);
      }
    }

    final reconciliationRows = <ClinicReconciliationRow>[];
    int balancedCount = 0;
    int deficitCount = 0;
    int surplusCount = 0;

    for (final mId in relevantMedicineIds) {
      final med = medicines.firstWhere((m) => m.id == mId, orElse: () => Medicine(
        name: 'Unknown Medicine (ID: $mId)',
        purchasePrice: 0,
        sellingPrice: 0,
      )..id = mId);

      final dispensed = dispenseMap[mId] ?? 0;
      final retailSold = retailMap[mId] ?? 0;
      final netTransfer = transferMap[mId] ?? 0;

      int startingBaselineStock = 0;
      int transferred = 0;
      int totalOut = 0;
      int currentStock = 0;
      int expectedStock = 0;

      switch (_scope) {
        case ReconciliationScope.all:
          startingBaselineStock = effectiveSinceBaseline ? service.getBaselineTotalStock(mId) : 0;
          transferred = 0;
          totalOut = dispensed + retailSold;
          currentStock = isHistoricalCycle && nextBaseline != null
              ? (nextBaseline.totalStocks[mId] ?? ((nextBaseline.clinicStocks[mId] ?? 0) + (nextBaseline.storeStocks[mId] ?? 0)))
              : (med.mainStock + med.storeStock);
          expectedStock = effectiveSinceBaseline
              ? (startingBaselineStock - totalOut)
              : -totalOut;
          break;

        case ReconciliationScope.clinic:
          startingBaselineStock = effectiveSinceBaseline ? service.getBaselineClinicStock(mId) : 0;
          transferred = netTransfer;
          totalOut = dispensed;
          currentStock = isHistoricalCycle && nextBaseline != null
              ? (nextBaseline.clinicStocks[mId] ?? 0)
              : med.mainStock;
          expectedStock = effectiveSinceBaseline
              ? (startingBaselineStock + transferred - totalOut)
              : (transferred - totalOut);
          break;

        case ReconciliationScope.store:
          startingBaselineStock = effectiveSinceBaseline ? service.getBaselineStoreStock(mId) : 0;
          transferred = -netTransfer;
          totalOut = retailSold;
          currentStock = isHistoricalCycle && nextBaseline != null
              ? (nextBaseline.storeStocks[mId] ?? 0)
              : med.storeStock;
          expectedStock = effectiveSinceBaseline
              ? (startingBaselineStock + transferred - totalOut)
              : (transferred - totalOut);
          break;
      }

      final variance = currentStock - expectedStock;

      if (variance == 0) {
        balancedCount++;
      } else if (variance < 0) {
        deficitCount++;
      } else {
        surplusCount++;
      }

      if (_clinicSearchQuery.isNotEmpty && !med.name.toLowerCase().contains(_clinicSearchQuery.toLowerCase())) {
        continue;
      }

      if (_statusFilter == 'deficit' && variance >= 0) continue;
      if (_statusFilter == 'surplus' && variance <= 0) continue;
      if (_statusFilter == 'balanced' && variance != 0) continue;

      reconciliationRows.add(ClinicReconciliationRow(
        medicineId: mId,
        medicineName: med.name,
        medicine: med,
        baselineStock: startingBaselineStock,
        totalTransferred: transferred,
        dispensedQty: dispensed,
        retailSoldQty: retailSold,
        totalConsumed: totalOut,
        expectedStock: expectedStock,
        currentStock: currentStock,
        variance: variance,
      ));
    }

    reconciliationRows.sort((a, b) {
      final vComp = b.variance.abs().compareTo(a.variance.abs());
      if (vComp != 0) return vComp;
      return a.medicineName.compareTo(b.medicineName);
    });

    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Modern Header Card: Title, Status, and Desktop Action Bar
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.sync_alt_rounded, color: AppTheme.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text(
                            'Stock Reconciliation & Physical Audit',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.3),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (isBaselineActive) ...[
                            if (isHistoricalCycle)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade900.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.history_toggle_off_rounded, size: 14, color: Colors.amber.shade900),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Historical Audit: ${dateFormat.format(service.baselineDate!)} ➔ ${dateFormat.format(baselineEndDate)} (${service.performedBy ?? "Staff"})',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => service.selectLatestBaseline(),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade800,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text('Back to Latest', style: TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppTheme.success.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.verified_rounded, size: 14, color: AppTheme.success),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Active Cycle: Since ${dateFormat.format(service.baselineDate!)} (${service.performedBy ?? "Staff"})',
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.success),
                                    ),
                                  ],
                                ),
                              ),
                          ] else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.history_rounded, size: 14, color: Colors.grey),
                                  SizedBox(width: 6),
                                  Text(
                                    'All-Time Cumulative Ledger (No baseline reset active)',
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(width: 10),
                          Text(
                            '• Tracks OPD dispenses, counter retail, and warehouse transfers',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Action Buttons Toolbar
                Row(
                  children: [
                    // Audit Snapshots History Menu
                    if (service.baselineHistory.isNotEmpty) ...[
                      PopupMenuButton<ClinicReconciliationBaseline>(
                        tooltip: 'Select Audit Snapshot to Compare',
                        onSelected: (b) {
                          service.selectBaseline(b);
                          setState(() => _viewSinceBaseline = true);
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem<ClinicReconciliationBaseline>(
                            enabled: false,
                            child: Text('PAST AUDIT SNAPSHOTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                          ),
                          ...service.baselineHistory.map((b) {
                            final isCurrent = service.activeBaseline?.id == b.id || service.activeBaseline?.timestamp == b.timestamp;
                            final isLatest = service.baselineHistory.first.id == b.id;
                            return PopupMenuItem<ClinicReconciliationBaseline>(
                              value: b,
                              child: Row(
                                children: [
                                  Icon(
                                    isCurrent ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                    size: 16,
                                    color: isCurrent ? AppTheme.primary : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${dateFormat.format(b.timestamp)} ${isLatest ? "(Latest/Active)" : ""}',
                                        style: TextStyle(
                                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                          fontSize: 12,
                                          color: isCurrent ? AppTheme.primary : null,
                                        ),
                                      ),
                                      Text(
                                        'By: ${b.performedBy} • ${b.medicineCount} items counted',
                                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: isHistoricalCycle ? Colors.amber.shade100 : Colors.blueGrey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isHistoricalCycle ? Colors.amber.shade800 : Colors.blueGrey.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.history_rounded,
                                size: 16,
                                color: isHistoricalCycle ? Colors.amber.shade900 : Colors.blueGrey.shade800,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isHistoricalCycle ? 'Past Audit' : 'Audit History (${service.baselineHistory.length})',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isHistoricalCycle ? Colors.amber.shade900 : Colors.blueGrey.shade800,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_drop_down_rounded,
                                size: 18,
                                color: isHistoricalCycle ? Colors.amber.shade900 : Colors.blueGrey.shade800,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    // Physical Count Toggle Button
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isAuditMode ? Colors.amber.shade800 : AppTheme.primary.withValues(alpha: 0.1),
                        foregroundColor: _isAuditMode ? Colors.white : AppTheme.primary,
                        elevation: _isAuditMode ? 2 : 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: Icon(_isAuditMode ? Icons.cancel_outlined : Icons.inventory_2_outlined, size: 16),
                      label: Text(
                        _isAuditMode ? 'Exit Shelf Audit' : 'Shelf Audit',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      onPressed: () {
                        setState(() {
                          _isAuditMode = !_isAuditMode;
                          if (_isAuditMode) {
                            for (final r in reconciliationRows) {
                              _physicalCounts[r.medicineId] = r.currentStock;
                            }
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 8),

                    // Export to Excel Button
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.teal.shade700,
                        side: BorderSide(color: Colors.teal.shade400),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.table_view_rounded, size: 16),
                      label: const Text('Export Excel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      onPressed: reconciliationRows.isEmpty ? null : () => _exportToExcel(reconciliationRows),
                    ),

                    if (service.baselineHistory.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Export multi-cycle comparative historical comparison to Excel',
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.indigo.shade700,
                            side: BorderSide(color: Colors.indigo.shade300),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.compare_arrows_rounded, size: 16),
                          label: const Text('Compare Audits', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          onPressed: _exportComparativeHistoryToExcel,
                        ),
                      ),
                    ],

                    const SizedBox(width: 8),
                    if (isBaselineActive) ...[
                      IconButton(
                        tooltip: _viewSinceBaseline ? 'Switch to All-Time Ledger' : 'Switch to Since-Audit View',
                        icon: Icon(
                          _viewSinceBaseline ? Icons.history_rounded : Icons.check_circle_outline_rounded,
                          size: 20,
                          color: Colors.blueGrey,
                        ),
                        onPressed: () {
                          setState(() => _viewSinceBaseline = !_viewSinceBaseline);
                        },
                      ),
                      IconButton(
                        tooltip: 'Clear Active Baseline',
                        icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                        onPressed: _showClearBaselineDialog,
                      ),
                      const SizedBox(width: 4),
                    ],

                    // Reset / New Baseline Button
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.restart_alt_rounded, size: 16),
                      label: const Text('Reset Baseline', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () => _showResetBaselineDialog(medicines),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Physical Shelf Stocktake Mode Banner
          if (_isAuditMode) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.amber.shade900.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_rounded, color: Colors.amber.shade800, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Physical Shelf Count Audit Mode Active',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          'Enter actual shelf quantities. The system compares physical counts with recorded stock to surface shrinkage and stock variations.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text('Apply Shelf Counts & Re-Baseline', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _showApplyPhysicalAuditDialog(medicines),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // 3. Scope Segmented Switch & Interactive KPI Summary Filter Bar
          Row(
            children: [
              // Segmented Scope Switch
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    _buildScopeButton('All Stock (Clinic + Store)', ReconciliationScope.all),
                    _buildScopeButton('Clinic Dispensary', ReconciliationScope.clinic),
                    _buildScopeButton('Store Warehouse', ReconciliationScope.store),
                  ],
                ),
              ),

              const Spacer(),

              // Interactive KPI Filter Badges
              _buildInteractiveKpiBadge(
                label: 'All Items',
                count: relevantMedicineIds.length,
                filterKey: 'all',
                color: AppTheme.primary,
                icon: Icons.list_alt_rounded,
              ),
              const SizedBox(width: 8),
              _buildInteractiveKpiBadge(
                label: 'Balanced (0 Diff)',
                count: balancedCount,
                filterKey: 'balanced',
                color: AppTheme.success,
                icon: Icons.check_circle_outline_rounded,
              ),
              const SizedBox(width: 8),
              _buildInteractiveKpiBadge(
                label: 'Shortage (Deficit)',
                count: deficitCount,
                filterKey: 'deficit',
                color: AppTheme.danger,
                icon: Icons.warning_amber_rounded,
              ),
              const SizedBox(width: 8),
              _buildInteractiveKpiBadge(
                label: 'Surplus',
                count: surplusCount,
                filterKey: 'surplus',
                color: Colors.blueAccent,
                icon: Icons.add_circle_outline_rounded,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 4. Search Filter Bar with Clear Button
          Row(
            children: [
              SizedBox(
                width: 380,
                child: TextField(
                  onChanged: (val) {
                    setState(() {
                      _clinicSearchQuery = val;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search medicine by name...',
                    hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _clinicSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () => setState(() => _clinicSearchQuery = ''),
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (_statusFilter != 'all')
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Chip(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => setState(() => _statusFilter = 'all'),
                    label: Text(
                      'Filtered by: $_statusFilter',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primary),
                    ),
                  ),
                ),
              Text(
                'Showing ${reconciliationRows.length} items • Scope: ${_scope == ReconciliationScope.all ? "All Combined" : (_scope == ReconciliationScope.clinic ? "Dispensary" : "Store")}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 5. Polished Reconciliation Data Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Table Header Row
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.05),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Expanded(flex: 3, child: Text('Medicine Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                        if (effectiveSinceBaseline)
                          const Expanded(flex: 2, child: Text('Baseline', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5), textAlign: TextAlign.center)),
                        if (_scope != ReconciliationScope.all)
                          const Expanded(flex: 2, child: Text('Transfers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5), textAlign: TextAlign.center)),
                        const Expanded(flex: 2, child: Text('Dispensed (OPD)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5), textAlign: TextAlign.center)),
                        const Expanded(flex: 2, child: Text('Retail Sold', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5), textAlign: TextAlign.center)),
                        const Expanded(flex: 2, child: Text('Total Out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5), textAlign: TextAlign.center)),
                        const Expanded(flex: 2, child: Text('Expected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5), textAlign: TextAlign.center)),
                        const Expanded(flex: 2, child: Text('Recorded Stock', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5), textAlign: TextAlign.center)),
                        if (_isAuditMode) ...[
                          const Expanded(flex: 2, child: Text('Shelf Count', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 12.5), textAlign: TextAlign.center)),
                          const Expanded(flex: 2, child: Text('Discrepancy', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 12.5), textAlign: TextAlign.center)),
                        ] else
                          const Expanded(flex: 2, child: Text('Variance / Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5), textAlign: TextAlign.center)),
                        const SizedBox(width: 44), // Quick action width
                      ],
                    ),
                  ),

                  // Table Body
                  Expanded(
                    child: reconciliationRows.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 10),
                                Text(
                                  _statusFilter != 'all'
                                      ? 'No medicines match the selected "$_statusFilter" filter.'
                                      : 'No medicines or transaction records found.',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: reconciliationRows.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.withValues(alpha: 0.12)),
                            itemBuilder: (context, index) {
                              final row = reconciliationRows[index];

                              Color varianceColor = AppTheme.success;
                              IconData varianceIcon = Icons.check_circle_outline_rounded;
                              String varianceBadgeText = 'Balanced';

                              if (row.variance < 0) {
                                varianceColor = AppTheme.danger;
                                varianceIcon = Icons.warning_amber_rounded;
                                varianceBadgeText = '${row.variance} Shortage';
                              } else if (row.variance > 0) {
                                varianceColor = Colors.blueAccent;
                                varianceIcon = Icons.add_circle_outline_rounded;
                                varianceBadgeText = '+${row.variance} Surplus';
                              }

                              // Physical count values for audit mode
                              final physCount = _physicalCounts[row.medicineId] ?? row.currentStock;
                              final physDiscrepancy = physCount - row.currentStock;

                              return Container(
                                color: row.variance < 0 ? AppTheme.danger.withValues(alpha: 0.02) : null,
                                padding: const EdgeInsets.symmetric(vertical: 7.0, horizontal: 16.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        row.medicineName,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                                      ),
                                    ),
                                    if (effectiveSinceBaseline)
                                      Expanded(
                                        flex: 2,
                                        child: Text('${row.baselineStock}', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                                      ),
                                    if (_scope != ReconciliationScope.all)
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          row.totalTransferred >= 0 ? '+${row.totalTransferred}' : '${row.totalTransferred}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: row.totalTransferred >= 0 ? AppTheme.success : AppTheme.danger,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    Expanded(
                                      flex: 2,
                                      child: Text('-${row.dispensedQty}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.cyan, fontSize: 12)),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text('-${row.retailSoldQty}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.orange, fontSize: 12)),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '-${row.totalConsumed}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 12),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text('${row.expectedStock}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '${row.currentStock}',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5,
                                          color: row.variance < 0 ? AppTheme.danger : null,
                                        ),
                                      ),
                                    ),

                                    // Physical Count or System Variance Column
                                    if (_isAuditMode) ...[
                                      Expanded(
                                        flex: 2,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle_outline, size: 16),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              onPressed: () {
                                                setState(() {
                                                  _physicalCounts[row.medicineId] = (physCount - 1).clamp(0, 999999);
                                                });
                                              },
                                            ),
                                            const SizedBox(width: 6),
                                            InkWell(
                                              borderRadius: BorderRadius.circular(6),
                                              onTap: () async {
                                                final ctrl = TextEditingController(text: '$physCount');
                                                final entered = await showDialog<int>(
                                                  context: context,
                                                  builder: (dCtx) => AlertDialog(
                                                    title: Text('Shelf Count: ${row.medicineName}', style: const TextStyle(fontSize: 15)),
                                                    content: SizedBox(
                                                      width: 320,
                                                      child: TextField(
                                                        controller: ctrl,
                                                        keyboardType: TextInputType.number,
                                                        autofocus: true,
                                                        decoration: InputDecoration(
                                                          labelText: 'Actual count on shelf',
                                                          helperText: 'System recorded: ${row.currentStock}',
                                                          border: const OutlineInputBorder(),
                                                        ),
                                                      ),
                                                    ),
                                                    actions: [
                                                      TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
                                                      ElevatedButton(
                                                        onPressed: () {
                                                          final val = int.tryParse(ctrl.text.trim());
                                                          Navigator.pop(dCtx, val);
                                                        },
                                                        child: const Text('Set Count'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (entered != null) {
                                                  setState(() {
                                                    _physicalCounts[row.medicineId] = entered.clamp(0, 999999);
                                                  });
                                                }
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: Colors.amber.shade800, width: 1.2),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      '$physCount',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Icon(Icons.edit_rounded, size: 12, color: Colors.amber.shade900),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            IconButton(
                                              icon: const Icon(Icons.add_circle_outline, size: 16),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              onPressed: () {
                                                setState(() {
                                                  _physicalCounts[row.medicineId] = physCount + 1;
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: (physDiscrepancy == 0
                                                      ? AppTheme.success
                                                      : (physDiscrepancy < 0 ? AppTheme.danger : Colors.blueAccent))
                                                  .withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              physDiscrepancy == 0
                                                  ? 'Matches'
                                                  : (physDiscrepancy < 0
                                                      ? '$physDiscrepancy Missing'
                                                      : '+$physDiscrepancy Surplus'),
                                              style: TextStyle(
                                                color: physDiscrepancy == 0
                                                    ? AppTheme.success
                                                    : (physDiscrepancy < 0 ? AppTheme.danger : Colors.blueAccent),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ] else
                                      Expanded(
                                        flex: 2,
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: varianceColor.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: varianceColor.withValues(alpha: 0.25)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(varianceIcon, size: 14, color: varianceColor),
                                                const SizedBox(width: 5),
                                                Text(
                                                  varianceBadgeText,
                                                  style: TextStyle(
                                                    color: varianceColor,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),

                                    // Quick Adjust Action Button
                                    SizedBox(
                                      width: 44,
                                      child: IconButton(
                                        tooltip: 'Quick Adjust Stock',
                                        icon: const Icon(Icons.tune_rounded, size: 17, color: Colors.grey),
                                        onPressed: () => _showSingleMedicineAdjustDialog(row.medicine, row.currentStock),
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
        ],
      ),
    );
  }

  Widget _buildScopeButton(String label, ReconciliationScope scope) {
    final isSelected = _scope == scope;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _scope = scope),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildInteractiveKpiBadge({
    required String label,
    required int count,
    required String filterKey,
    required Color color,
    required IconData icon,
  }) {
    final isSelected = _statusFilter == filterKey;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _statusFilter = filterKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : color),
            const SizedBox(width: 6),
            Text(
              '$label: $count',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ClinicReconciliationRow {
  final int medicineId;
  final String medicineName;
  final Medicine medicine;
  final int baselineStock;
  final int totalTransferred;
  final int dispensedQty;
  final int retailSoldQty;
  final int totalConsumed;
  final int expectedStock;
  final int currentStock;
  final int variance;

  ClinicReconciliationRow({
    required this.medicineId,
    required this.medicineName,
    required this.medicine,
    required this.baselineStock,
    required this.totalTransferred,
    required this.dispensedQty,
    required this.retailSoldQty,
    required this.totalConsumed,
    required this.expectedStock,
    required this.currentStock,
    required this.variance,
  });
}
