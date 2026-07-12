import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/warehouse_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/models/medicine.dart';
import '../../theme/app_theme.dart';
import '../../widgets/medicine_dialog.dart';
import 'warehouse/tabs/inventory_tab.dart';
import 'warehouse/tabs/stock_report_tab.dart';
import 'warehouse/tabs/transfers_tab.dart';
import 'warehouse/tabs/purchases_tab.dart';
import 'warehouse/dialogs/bulk_transfer_dialog.dart';
import 'warehouse/dialogs/bulk_stock_entry_dialog.dart';

class WarehouseWindows extends StatefulWidget {
  const WarehouseWindows({super.key});

  @override
  State<WarehouseWindows> createState() => _WarehouseWindowsState();
}

class _WarehouseWindowsState extends State<WarehouseWindows>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WarehouseProvider>().loadTransfers();
      context.read<InventoryProvider>().load();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _importExcel(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (!auth.hasInventoryWriteAccess && !auth.canAddStock) return;

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      var bytes = file.readAsBytesSync();
      var excel = excel_pkg.Excel.decodeBytes(bytes);

      if (excel.tables.keys.isEmpty) return;

      final String firstSheet = excel.tables.keys.first;
      final table = excel.tables[firstSheet];
      if (table == null) return;

      if (!context.mounted) return;

      final String? mode = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Excel Import Mode'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How would you like to handle stock updates?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text(
                '• Overwrite Stock (Clear Previous Batches):\n  Removes all existing batches and resets stock to 0 for the imported medicines before adding the new stock.',
              ),
              SizedBox(height: 8),
              Text(
                '• Add Stock (Incremental):\n  Keeps existing batches and adds the Excel stock as a new batch.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel Import'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'add'),
              child: const Text('Add Stock'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'overwrite'),
              child: const Text('Overwrite Stock'),
            ),
          ],
        ),
      );

      if (mode == null || mode == 'cancel') return;

      int added = 0;
      int updated = 0;
      if (!context.mounted) return;
      final inv = context.read<InventoryProvider>();

      bool isTally = false;
      // Scan rows to find "Particulars" to auto-detect Tally exports
      for (int i = 0; i < table.maxRows; i++) {
        final row = table.row(i);
        for (int j = 0; j < row.length; j++) {
          final cellValue =
              row[j]?.value?.toString().trim().toLowerCase() ?? '';
          if (cellValue == 'particulars') {
            isTally = true;
            break;
          }
        }
        if (isTally) break;
      }

      if (isTally) {
        // Overwrite pre-clear logic for Tally
        if (mode == 'overwrite') {
          final List<int> idsToClear = [];
          for (int i = 0; i < table.maxRows; i++) {
            final row = table.row(i);
            if (row.isEmpty) continue;
            final sNoStr = row[0]?.value?.toString().trim() ?? '';
            final isSerial = int.tryParse(sNoStr) != null;
            final nameCell = row[1]?.value?.toString().trim() ?? '';

            if (isSerial && nameCell.isNotEmpty) {
              final existing = inv.rawMedicines
                  .where((m) => m.name.toLowerCase() == nameCell.toLowerCase())
                  .firstOrNull;
              if (existing != null) {
                idsToClear.add(existing.id);
              }
            }
          }
          if (idsToClear.isNotEmpty) {
            inv.clearBatchesAndResetStock(idsToClear);
          }
        }

        for (int i = 0; i < table.maxRows; i++) {
          final row = table.row(i);
          if (row.isEmpty) continue;
          final sNoStr = row[0]?.value?.toString().trim() ?? '';
          final isSerial = int.tryParse(sNoStr) != null;
          final nameCell = row[1]?.value?.toString().trim() ?? '';

          if (isSerial && nameCell.isNotEmpty) {
            const barcode = '';
            const category = 'General';
            const unit = 'Pcs';

            final double qtyVal = row.length > 3
                ? (double.tryParse(row[3]?.value?.toString().trim() ?? '') ??
                    0.0)
                : 0.0;
            final double rateVal = row.length > 4
                ? (double.tryParse(row[4]?.value?.toString().trim() ?? '') ??
                    0.0)
                : 0.0;

            final mainStock = qtyVal.round();
            const storeStock = 0;
            final purchasePrice = rateVal;
            final sellingPrice = rateVal;

            final existing = inv.rawMedicines
                .where((m) => m.name.toLowerCase() == nameCell.toLowerCase())
                .firstOrNull;

            if (existing != null) {
              existing
                ..category = category
                ..unit = unit
                ..purchasePrice =
                    purchasePrice > 0 ? purchasePrice : existing.purchasePrice
                ..sellingPrice =
                    sellingPrice > 0 ? sellingPrice : existing.sellingPrice;

              inv.updateMedicine(existing, actor: auth.currentUser);

              if (mainStock > 0) {
                inv.addBatchStock(
                  {existing.id: mainStock},
                  storeUpdates: {existing.id: storeStock},
                  batchNo: 'IMPORT-${DateTime.now().millisecondsSinceEpoch}',
                  expiryDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  note: 'Imported from Excel (Tally)',
                  actor: auth.currentUser,
                );
              }
              updated++;
            } else {
              final newMed = Medicine(
                name: nameCell,
                barcode: barcode,
                category: category,
                unit: unit,
                purchasePrice: purchasePrice,
                sellingPrice: sellingPrice,
                mainStock: 0,
                storeStock: 0,
                lowStockThreshold: 10,
              );
              inv.addMedicine(newMed, actor: auth.currentUser);

              if (mainStock > 0) {
                inv.addBatchStock(
                  {newMed.id: mainStock},
                  storeUpdates: {newMed.id: storeStock},
                  batchNo: 'IMPORT-${DateTime.now().millisecondsSinceEpoch}',
                  expiryDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  note: 'Imported from Excel (Tally)',
                  actor: auth.currentUser,
                );
              }
              added++;
            }
          }
        }
      } else {
        int headerRowIndex = -1;
        Map<String, int> colMap = {};

        // 1. Find the header row
        for (int i = 0; i < table.maxRows; i++) {
          final row = table.row(i);
          for (int j = 0; j < row.length; j++) {
            final cellValue =
                row[j]?.value?.toString().trim().toLowerCase() ?? '';
            if (cellValue == 'medicine name' ||
                cellValue == 'item name' ||
                cellValue == 'product name' ||
                cellValue == 'itemname') {
              headerRowIndex = i;
              break;
            }
          }
          if (headerRowIndex != -1) break;
        }

        if (headerRowIndex == -1) {
          throw Exception(
              "Could not find a header row containing 'Medicine Name'.");
        }

        // 2. Map columns
        final headerRow = table.row(headerRowIndex);
        for (int j = 0; j < headerRow.length; j++) {
          final title =
              headerRow[j]?.value?.toString().trim().toLowerCase() ?? '';
          if (title.isNotEmpty) {
            colMap[title] = j;
          }
        }

        // Helper to get index matching a list of possible names
        int getColIdx(List<String> possibleNames) {
          for (final name in possibleNames) {
            if (colMap.containsKey(name)) return colMap[name]!;
          }
          return -1;
        }

        final nameIdx =
            getColIdx(['medicine name', 'item name', 'product name']);
        final barcodeIdx = getColIdx(['barcode']);
        final categoryIdx = getColIdx(['category']);
        final unitIdx = getColIdx(['unit']);
        final purchasePriceIdx = getColIdx(['purchase price', 'cost']);
        final sellingPriceIdx =
            getColIdx(['selling price', 'selling rate', 'rate', 'price']);
        final mainStockIdx = getColIdx(['main hub stock', 'main stock']);
        final storeStockIdx =
            getColIdx(['store front stock', 'store stock', 'quantity', 'qty']);
        final lowStockIdx = getColIdx(['low stock threshold', 'threshold']);

        // Overwrite pre-clear logic for standard Excel
        if (mode == 'overwrite' && nameIdx != -1) {
          final List<int> idsToClear = [];
          for (int i = headerRowIndex + 1; i < table.maxRows; i++) {
            final row = table.row(i);
            if (row.length > nameIdx) {
              final nameCell = row[nameIdx]?.value?.toString().trim() ?? '';
              if (nameCell.isNotEmpty) {
                final existing = inv.rawMedicines
                    .where((m) => m.name.toLowerCase() == nameCell.toLowerCase())
                    .firstOrNull;
                if (existing != null) {
                  idsToClear.add(existing.id);
                }
              }
            }
          }
          if (idsToClear.isNotEmpty) {
            inv.clearBatchesAndResetStock(idsToClear);
          }
        }

        // 3. Process rows
        for (int i = headerRowIndex + 1; i < table.maxRows; i++) {
          final row = table.row(i);

          String getCellStr(int idx, String def) =>
              (idx != -1 && idx < row.length)
                  ? (row[idx]?.value?.toString().trim() ?? def)
                  : def;
          double getCellDbl(int idx, double def) => (idx != -1 &&
                  idx < row.length)
              ? (double.tryParse(row[idx]?.value?.toString().trim() ?? '') ??
                  def)
              : def;
          int getCellInt(int idx, int def) => (idx != -1 && idx < row.length)
              ? (int.tryParse(row[idx]?.value?.toString().trim() ?? '') ?? def)
              : def;

          final nameCell = getCellStr(nameIdx, '');
          if (nameCell.isEmpty) continue; // Skip empty rows

          final barcode = getCellStr(barcodeIdx, '');
          final category = getCellStr(categoryIdx, 'General');
          final unit = getCellStr(unitIdx, 'Pcs');

          final purchasePrice = getCellDbl(purchasePriceIdx, 0.0);
          final sellingPrice = getCellDbl(sellingPriceIdx, 0.0);

          final mainStock = getCellInt(mainStockIdx, 0);
          final storeStock = getCellInt(storeStockIdx, 0);
          final lowStock = getCellInt(lowStockIdx, 10);

          // Check if medicine exists
          final existing = inv.rawMedicines
              .where((m) => m.name.toLowerCase() == nameCell.toLowerCase())
              .firstOrNull;

          if (existing != null) {
            // Update existing metadata
            existing
              ..barcode = barcode.isNotEmpty ? barcode : existing.barcode
              ..category = category
              ..unit = unit
              ..purchasePrice =
                  purchasePrice > 0 ? purchasePrice : existing.purchasePrice
              ..sellingPrice =
                  sellingPrice > 0 ? sellingPrice : existing.sellingPrice
              ..lowStockThreshold = lowStock;

            inv.updateMedicine(existing, actor: auth.currentUser);

            // If stock is provided in Excel, add it as a new batch to avoid total drift
            if (mainStock > 0 || storeStock > 0) {
              inv.addBatchStock(
                {existing.id: mainStock},
                storeUpdates: {existing.id: storeStock},
                batchNo: 'IMPORT-${DateTime.now().millisecondsSinceEpoch}',
                expiryDate: DateTime.now()
                    .add(const Duration(days: 365 * 2)), // 2 year default
                note: 'Imported from Excel',
                actor: auth.currentUser,
              );
            }
            updated++;
          } else {
            // Add new
            final newMed = Medicine(
              name: nameCell,
              barcode: barcode,
              category: category,
              unit: unit,
              purchasePrice: purchasePrice,
              sellingPrice: sellingPrice,
              mainStock: 0, // Will be updated by batch
              storeStock: 0,
              lowStockThreshold: lowStock,
            );
            inv.addMedicine(newMed, actor: auth.currentUser);

            if (mainStock > 0 || storeStock > 0) {
              inv.addBatchStock(
                {newMed.id: mainStock},
                storeUpdates: {newMed.id: storeStock},
                batchNo: 'IMPORT-${DateTime.now().millisecondsSinceEpoch}',
                expiryDate: DateTime.now().add(const Duration(days: 365 * 2)),
                note: 'Imported from Excel',
                actor: auth.currentUser,
              );
            }
            added++;
          }
        }
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Excel Import Complete: Added $added new, Updated $updated existing medicines.'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final wh = context.watch<WarehouseProvider>();
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        title: const Text('Stock Control'),
        elevation: 0,
        backgroundColor: context.surfaceColor,
        actions: [
          if (auth.hasInventoryWriteAccess || auth.canAddStock)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shadowColor: AppTheme.success.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _importExcel(context),
                icon: const Icon(Icons.file_upload, size: 18),
                label: const Text('Import Excel'),
              ),
            ),
          if (auth.hasWarehouseWriteAccess)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.indigo,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shadowColor: AppTheme.indigo.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => showDialog(
                  context: context,
                  builder: (ctx) => BulkTransferDialog(wh: wh),
                ),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Bulk Transfer'),
              ),
            ),
          if (auth.hasInventoryWriteAccess || auth.canAddStock)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shadowColor: AppTheme.primary.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => showDialog(
                  context: context,
                  builder: (ctx) => const BulkStockEntryDialog(),
                ),
                icon: const Icon(Icons.inventory_2, size: 18),
                label: const Text('Bulk Purchase Entry'),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.primary,
          unselectedLabelColor: context.textMutedColor,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_customize), text: 'Overview'),
            Tab(icon: Icon(Icons.list_alt), text: 'Stock Report'),
            Tab(icon: Icon(Icons.compare_arrows), text: 'Transfers'),
            Tab(icon: Icon(Icons.shopping_bag_outlined), text: 'Purchases'),
          ],
        ),
      ),
      floatingActionButton: (auth.hasInventoryWriteAccess || auth.canAddStock)
          ? FloatingActionButton.extended(
              onPressed: () {
                MedicineDialog.show(context, medicine: null);
              },
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Add Medicine / Stock',
                  style: TextStyle(color: Colors.white)),
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: const [
          StockLevelsTab(),
          StockReportTab(),
          TransferHistoryTab(),
          PurchaseHistoryTab(),
        ],
      ),
    );
  }
}
