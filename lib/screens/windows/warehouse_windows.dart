import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/warehouse_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/models/medicine.dart';
import '../../shared/models/purchase_record.dart';
import '../../shared/services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/medicine_dialog.dart';
import '../../shared/widgets/app_status_badge.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_filter_chip.dart';

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
            final barcode = '';
            final category = 'General';
            final unit = 'Pcs';

            final double qtyVal = row.length > 3
                ? (double.tryParse(row[3]?.value?.toString().trim() ?? '') ??
                    0.0)
                : 0.0;
            final double rateVal = row.length > 4
                ? (double.tryParse(row[4]?.value?.toString().trim() ?? '') ??
                    0.0)
                : 0.0;

            final mainStock = qtyVal.round();
            final storeStock = 0;
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
                  builder: (ctx) => _BulkTransferDialog(wh: wh),
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
                  builder: (ctx) => const _BulkStockEntryDialog(),
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
          _StockLevelsTab(),
          _StockReportTab(),
          _TransferHistoryTab(),
          _PurchaseHistoryTab(),
        ],
      ),
    );
  }
}

class _StockLevelsTab extends StatefulWidget {
  const _StockLevelsTab();

  @override
  State<_StockLevelsTab> createState() => _StockLevelsTabState();
}

class _StockLevelsTabState extends State<_StockLevelsTab> {
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final inv = context.read<InventoryProvider>();
        inv.setSearch('');
        inv.setFilter('all');
        inv.setSort('name');
      }
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final wh = context.read<WarehouseProvider>();
    final auth = context.watch<AuthProvider>();

    return Column(
      children: [
        // Search & Filter Header
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            border: Border(
                bottom: BorderSide(
                    color: context.borderColor.withValues(alpha: 0.5))),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      onChanged: inv.setSearch,
                      decoration: InputDecoration(
                        hintText: 'Search by name or barcode...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: context.bgColor.withValues(alpha: 0.5),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _HorizontalDropdown(
                      label: 'Sort By',
                      value: inv.sortBy,
                      items: const {
                        'name': 'Name (A-Z)',
                        'price': 'Price (High-Low)',
                        'stock': 'Stock (Low-High)',
                      },
                      onChanged: (v) => inv.setSort(v!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _HorizontalDropdown(
                      label: 'Filter',
                      value: inv.filterWarehouse,
                      items: const {
                        'all': 'All Stock',
                        'low-stock': 'Low Stock Alert',
                        'main-empty': 'Clinic Empty',
                        'expired': 'Expired',
                        'near-expiry': 'Near Expiry',
                      },
                      onChanged: (v) => inv.setFilter(v!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Reconcile Clinic Quantity with Batches',
                    icon:
                        const Icon(Icons.rebase_edit, color: AppTheme.primary),
                    onPressed: () {
                      inv.reconcileAllStock();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Stock reconciled with batches successfully')),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        // Medicines Grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 400,
              mainAxisSpacing: 24,
              crossAxisSpacing: 24,
              mainAxisExtent: 430, // Fixed height for consistency
            ),
            itemCount: inv.medicines.length,
            itemBuilder: (ctx, i) {
              final m = inv.medicines[i];
              return _ModernMedicineCardWindows(
                medicine: m,
                wh: wh,
                auth: auth,
                inv: inv,
                isSelected: _selectedIds.contains(m.id),
                onSelect: (selected) => _toggleSelection(m.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ModernMedicineCardWindows extends StatefulWidget {
  final Medicine medicine;
  final WarehouseProvider wh;
  final AuthProvider auth;
  final InventoryProvider inv;
  final bool isSelected;
  final ValueChanged<bool?>? onSelect;

  const _ModernMedicineCardWindows({
    required this.medicine,
    required this.wh,
    required this.auth,
    required this.inv,
    this.isSelected = false,
    this.onSelect,
  });

  @override
  State<_ModernMedicineCardWindows> createState() =>
      _ModernMedicineCardWindowsState();
}

class _ModernMedicineCardWindowsState
    extends State<_ModernMedicineCardWindows> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: InkWell(
        onTap: () => _showBatchDetails(context, widget.medicine),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.vaccines,
                        color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.medicine.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        Text(
                          widget.medicine.category.isEmpty
                              ? 'General'
                              : widget.medicine.category,
                          style: TextStyle(
                              color: context.textMutedColor, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${widget.medicine.sellingPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: AppTheme.success),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _MetricBlock(
                          label: 'Store Bulk',
                          value: widget.medicine.bulkStoreStock,
                          icon: Icons.warehouse_outlined,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(width: 58),
                      Expanded(
                        child: _MetricBlock(
                          label: 'Clinic Bulk',
                          value: widget.medicine.bulkClinicStock,
                          icon: Icons.warehouse,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Center(
                            child: Tooltip(
                              message: 'Transfer Store Bulk to POS',
                              child: InkWell(
                                onTap: () => _showTransferDialog(
                                    context,
                                    widget.medicine,
                                    'bulkStore',
                                    'store',
                                    widget.wh),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF14B8A6)
                                        .withValues(alpha: 0.1),
                                  ),
                                  child: const Icon(Icons.arrow_downward_rounded,
                                      size: 16, color: Color(0xFF14B8A6)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 58),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Center(
                            child: Tooltip(
                              message: 'Transfer Clinic Bulk to Dispensing',
                              child: InkWell(
                                onTap: () => _showTransferDialog(
                                    context,
                                    widget.medicine,
                                    'bulkClinic',
                                    'clinic',
                                    widget.wh),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppTheme.indigo.withValues(alpha: 0.1),
                                  ),
                                  child: const Icon(Icons.arrow_downward_rounded,
                                      size: 16, color: AppTheme.indigo),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricBlock(
                          label: 'Store',
                          value: widget.medicine.storeStock,
                          icon: Icons.storefront,
                          color: const Color(0xFF14B8A6),
                          isWarning: widget.medicine.isLowStock,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Tooltip(
                            message: 'Transfer Store to Clinic',
                            child: InkWell(
                              onTap: () => _showTransferDialog(
                                  context,
                                  widget.medicine,
                                  'store',
                                  'clinic',
                                  widget.wh),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 42,
                                height: 28,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: const Color(0xFF14B8A6)
                                      .withValues(alpha: 0.1),
                                ),
                                child: const Icon(Icons.arrow_forward_rounded,
                                    size: 16, color: Color(0xFF14B8A6)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Tooltip(
                            message: 'Transfer Clinic to Store',
                            child: InkWell(
                              onTap: () => _showTransferDialog(
                                  context,
                                  widget.medicine,
                                  'clinic',
                                  'store',
                                  widget.wh),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 42,
                                height: 28,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: AppTheme.indigo.withValues(alpha: 0.1),
                                ),
                                child: const Icon(Icons.arrow_back_rounded,
                                    size: 16, color: AppTheme.indigo),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MetricBlock(
                          label: 'Clinic',
                          value: widget.medicine.mainStock,
                          icon: Icons.medical_services,
                          color: AppTheme.indigo,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.medicine.isLowStock)
                    AppStatusBadge(
                        label: 'LOW STOCK',
                        color: AppTheme.warning,
                        style: AppStatusBadgeStyle.text),
                  if (widget.medicine.hasExpiredBatch)
                    AppStatusBadge(
                        label: 'EXPIRED',
                        color: AppTheme.danger,
                        style: AppStatusBadgeStyle.text)
                  else if (widget.medicine.hasNearExpiryBatch)
                    AppStatusBadge(
                        label: 'NEAR EXPIRY',
                        color: AppTheme.danger,
                        style: AppStatusBadgeStyle.text),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: context.textMutedColor),
                    onSelected: (val) {
                      if (val == 'edit') {
                        MedicineDialog.show(context, medicine: widget.medicine);
                      } else if (val == 'batches') {
                        _showBatchDetails(context, widget.medicine);
                      } else if (val == 'transfer') {
                        _showTransferDialog(context, widget.medicine,
                            'bulkClinic', 'clinic', widget.wh);
                      } else if (val == 'delete') {
                        _confirmDelete(context, widget.medicine);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                          value: 'edit',
                          child: Row(children: [
                            Icon(Icons.edit),
                            Text(' Edit Info')
                          ])),
                      const PopupMenuItem(
                          value: 'batches',
                          child: Row(children: [
                            Icon(Icons.layers_outlined),
                            Text(' Batch Details')
                          ])),
                      const PopupMenuItem(
                          value: 'transfer',
                          child: Row(children: [
                            Icon(Icons.swap_horiz),
                            Text(' Transfer Stock')
                          ])),
                      if (widget.auth.currentUser?.canDeleteInventory == true)
                        const PopupMenuItem(
                            value: 'delete',
                            child: Row(children: [
                              Icon(Icons.delete, color: AppTheme.danger),
                              Text(' Delete',
                                  style: TextStyle(color: AppTheme.danger))
                            ])),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Medicine m) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Medicine?'),
        content: Text('Are you sure you want to delete ${m.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              widget.inv.deleteMedicine(m.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showBatchDetails(BuildContext context, Medicine m) {
    showDialog(
      context: context,
      builder: (_) => _BatchDetailsDialog(
          medicine: m,
          wh: widget.wh,
          canTransfer: context.read<AuthProvider>().hasWarehouseWriteAccess),
    );
  }

  void _showTransferDialog(BuildContext context, Medicine m, String from,
      String to, WarehouseProvider wh) {
    showDialog(
      context: context,
      builder: (_) => _TransferDialog(medicine: m, from: from, to: to, wh: wh),
    );
  }
}

class _BatchDetailsDialog extends StatelessWidget {
  final Medicine medicine;
  final WarehouseProvider wh;
  final bool canTransfer;
  const _BatchDetailsDialog(
      {required this.medicine, required this.wh, required this.canTransfer});

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, inv, _) {
        // Refetch medicine to get latest batches
        final m = inv.medicines.where((m) => m.id == medicine.id).firstOrNull ??
            medicine;
        final sortedBatches = m.batches.toList()
          ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.layers_outlined, color: AppTheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Text('Batches: ${m.name}')),
              if (canTransfer)
                IconButton(
                  tooltip: 'Add New Batch',
                  icon: const Icon(Icons.add_circle_outline,
                      color: AppTheme.primary),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => _EditBatchDialog(
                        medicine: m,
                        batch: null,
                      ),
                    );
                  },
                ),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sortedBatches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No active batches found for this medicine.'),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 400),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: sortedBatches.length,
                      itemBuilder: (ctx, i) {
                        final b = sortedBatches[i];
                        final isExpired = b.expiryDate.isBefore(DateTime.now());
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.bgColor.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: isExpired
                                    ? AppTheme.danger.withValues(alpha: 0.2)
                                    : context.borderColor
                                        .withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Batch: ${b.batchNo}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Text(
                                      'Expiry: ${b.expiryDate.day}/${b.expiryDate.month}/${b.expiryDate.year}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: isExpired
                                              ? AppTheme.danger
                                              : context.textMutedColor),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text('STORE BULK',
                                        style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold)),
                                    Text('${b.bulkStoreStock}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text('CLINIC BULK',
                                        style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold)),
                                    Text('${b.bulkClinicStock}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text('STORE',
                                        style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold)),
                                    Text('${b.storeStock}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text('CLINIC',
                                        style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold)),
                                    Text('${b.mainStock}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14)),
                                  ],
                                ),
                              ),
                              if (canTransfer) ...[
                                IconButton(
                                  icon:
                                      const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => _EditBatchDialog(
                                          medicine: m, batch: b),
                                    );
                                  },
                                ),
                                if (context
                                            .read<AuthProvider>()
                                            .currentUser
                                            ?.role
                                            .toLowerCase() ==
                                        'admin' ||
                                    context
                                            .read<AuthProvider>()
                                            .currentUser
                                            ?.canDeleteInventory ==
                                        true)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: AppTheme.danger, size: 20),
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Delete Batch?'),
                                          content: Text(
                                              'Are you sure you want to permanently delete batch ${b.batchNo}? This will subtract its stock from the medicine totals.'),
                                          actions: [
                                            TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx),
                                                child: const Text('Cancel')),
                                            FilledButton(
                                              style: FilledButton.styleFrom(
                                                  backgroundColor:
                                                      AppTheme.danger),
                                              onPressed: () {
                                                final inv = context
                                                    .read<InventoryProvider>();
                                                final sync =
                                                    context.read<SyncService>();
                                                inv.deleteBatch(m, b,
                                                    syncService: sync);
                                                Navigator.pop(ctx);
                                              },
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (canTransfer) ...[
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                           _showTransfer(context, m, 'bulkClinic', 'clinic', wh);
                        },
                        icon: const Icon(Icons.swap_horiz, size: 16),
                        label: const Text('Transfer Stock'),
                      ),
                    ],
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
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

  void _showTransfer(BuildContext context, Medicine m, String from, String to,
      WarehouseProvider wh) {
    showDialog(
      context: context,
      builder: (_) => _TransferDialog(medicine: m, from: from, to: to, wh: wh),
    );
  }
}

class _EditBatchDialog extends StatefulWidget {
  final Medicine medicine;
  final MedicineBatch? batch;
  const _EditBatchDialog({required this.medicine, this.batch});

  @override
  State<_EditBatchDialog> createState() => _EditBatchDialogState();
}

class _EditBatchDialogState extends State<_EditBatchDialog> {
  late final _batchNoCtrl =
      TextEditingController(text: widget.batch?.batchNo ?? '');
  late final _hubStockCtrl = TextEditingController(
      text: widget.batch != null ? '${widget.batch!.mainStock}' : '0');
  late final _storeStockCtrl = TextEditingController(
      text: widget.batch != null ? '${widget.batch!.storeStock}' : '0');
  late final _bulkClinicCtrl = TextEditingController(
      text: widget.batch != null ? '${widget.batch!.bulkClinicStock}' : '0');
  late final _bulkStoreCtrl = TextEditingController(
      text: widget.batch != null ? '${widget.batch!.bulkStoreStock}' : '0');
  late DateTime _expiryDate =
      widget.batch?.expiryDate ?? DateTime.now().add(const Duration(days: 365));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(widget.batch != null ? 'Edit Batch Details' : 'Add New Batch'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _batchNoCtrl,
            decoration:
                const InputDecoration(labelText: 'Batch Number', isDense: true),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'Expiry Date', isDense: true),
              child: Text(
                  '${_expiryDate.day}/${_expiryDate.month}/${_expiryDate.year}'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _bulkStoreCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Store Bulk', isDense: true),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _bulkClinicCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Clinic Bulk', isDense: true),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _storeStockCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Store', isDense: true),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _hubStockCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Clinic', isDense: true),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (widget.batch != null &&
            (context.read<AuthProvider>().currentUser?.role.toLowerCase() ==
                    'admin' ||
                context.read<AuthProvider>().currentUser?.canDeleteInventory ==
                    true))
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            onPressed: () => _confirmDeleteBatch(context),
            child: const Text('Delete Batch'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _save,
          child: Text(widget.batch != null ? 'Save Changes' : 'Add Batch'),
        ),
      ],
    );
  }

  void _confirmDeleteBatch(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Batch?'),
        content: Text(
            'Are you sure you want to permanently delete batch ${widget.batch!.batchNo}? This will subtract its stock from the medicine totals.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              final inv = context.read<InventoryProvider>();
              final sync = context.read<SyncService>();
              inv.deleteBatch(widget.medicine, widget.batch!,
                  syncService: sync);
              Navigator.pop(ctx); // Close confirmation dialog
              Navigator.pop(context); // Close edit batch dialog
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _expiryDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
      locale: const Locale('en', 'GB'),
      initialEntryMode: DatePickerEntryMode.input,
    );
    if (d != null) setState(() => _expiryDate = d);
  }

  void _save() {
    final inv = context.read<InventoryProvider>();
    final sync = context.read<SyncService>();
    final batchNo = _batchNoCtrl.text.trim();
    if (batchNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a batch number')),
      );
      return;
    }

    final mainStock = int.tryParse(_hubStockCtrl.text) ?? 0;
    final storeStock = int.tryParse(_storeStockCtrl.text) ?? 0;
    final bulkClinicStock = int.tryParse(_bulkClinicCtrl.text) ?? 0;
    final bulkStoreStock = int.tryParse(_bulkStoreCtrl.text) ?? 0;

    if (widget.batch != null) {
      inv.updateBatchDetail(
        widget.medicine,
        widget.batch!,
        batchNo: batchNo,
        expiryDate: _expiryDate,
        mainStock: mainStock,
        storeStock: storeStock,
        bulkClinicStock: bulkClinicStock,
        bulkStoreStock: bulkStoreStock,
        syncService: sync,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Batch details updated')),
      );
    } else {
      inv.addBatchStock(
        {widget.medicine.id: mainStock},
        storeUpdates: {widget.medicine.id: storeStock},
        bulkClinicUpdates: {widget.medicine.id: bulkClinicStock},
        bulkStoreUpdates: {widget.medicine.id: bulkStoreStock},
        batchNo: batchNo,
        expiryDate: _expiryDate,
        syncService: sync,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New batch added successfully')),
      );
    }

    Navigator.pop(context);
  }
}

class _MetricBlock extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final bool isWarning;

  const _MetricBlock({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final finalColor = isWarning ? AppTheme.warning : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: finalColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: finalColor.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: finalColor.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: finalColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 10, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.5,
                  color: finalColor)),
          const SizedBox(height: 6),
          Text('$value',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                  color: finalColor)),
        ],
      ),
    );
  }
}

class _HorizontalDropdown extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String?> onChanged;

  const _HorizontalDropdown(
      {required this.label,
      required this.value,
      required this.items,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: context.textMutedColor)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.bgColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              items: items.entries.map((e) {
                return DropdownMenuItem(value: e.key, child: Text(e.value));
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _TransferHistoryTab extends StatelessWidget {
  const _TransferHistoryTab();

  @override
  Widget build(BuildContext context) {
    final wh = context.watch<WarehouseProvider>();

    return Column(
      children: [
        // Date Filter Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            border: Border(
                bottom: BorderSide(
                    color: context.borderColor.withValues(alpha: 0.5))),
          ),
          child: Row(
            children: [
              const Icon(Icons.filter_list, size: 20),
              const SizedBox(width: 16),
              AppFilterChip(
                label: 'Today',
                isSelected: wh.activeFilter == SalesFilter.today,
                onTap: () => wh.setFilter(SalesFilter.today),
                style: AppFilterChipStyle.filled,
              ),
              const SizedBox(width: 8),
              AppFilterChip(
                label: 'Yesterday',
                isSelected: wh.activeFilter == SalesFilter.yesterday,
                onTap: () => wh.setFilter(SalesFilter.yesterday),
                style: AppFilterChipStyle.filled,
              ),
              const SizedBox(width: 8),
              AppFilterChip(
                label: 'Last 7 Days',
                isSelected: wh.activeFilter == SalesFilter.last7Days,
                onTap: () => wh.setFilter(SalesFilter.last7Days),
                style: AppFilterChipStyle.filled,
              ),
              const SizedBox(width: 8),
              AppFilterChip(
                label: 'All Time',
                isSelected: wh.activeFilter == SalesFilter.allTime,
                onTap: () => wh.setFilter(SalesFilter.allTime),
                style: AppFilterChipStyle.filled,
              ),
              const SizedBox(width: 8),
              AppFilterChip(
                label: 'Custom Range',
                isSelected: wh.activeFilter == SalesFilter.custom,
                onTap: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    locale: const Locale('en', 'GB'),
                    initialEntryMode: DatePickerEntryMode.input,
                    builder: (ctx, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: Theme.of(context).colorScheme.copyWith(
                                primary: AppTheme.primary,
                                onPrimary: Colors.white,
                              ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (range != null) {
                    wh.setFilter(SalesFilter.custom, range: range);
                  }
                },
                style: AppFilterChipStyle.filled,
              ),
            ],
          ),
        ),
        Expanded(
          child: wh.transfers.isEmpty
              ? const AppEmptyState(
                  icon: Icons.history,
                  title: 'No transfers recorded in this period',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: wh.transfers.length,
                  itemBuilder: (ctx, i) {
                    final t = wh.transfers[i];
                    final isToStore = t.toWarehouse.toLowerCase() == 'store';
                    final accentColor =
                        isToStore ? const Color(0xFF14B8A6) : AppTheme.indigo;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: context.borderColor.withValues(alpha: 0.5)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isToStore
                                ? Icons.arrow_forward_rounded
                                : Icons.arrow_back_rounded,
                            color: accentColor,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(t.medicineName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 16)),
                            const Spacer(),
                            Text(
                              '${t.qty} Units',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: accentColor),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Text('${t.fromWarehouse} → ${t.toWarehouse}',
                                  style: TextStyle(
                                      color: context.textColor,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(width: 12),
                              Text('|',
                                  style:
                                      TextStyle(color: context.textMutedColor)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  t.note.isNotEmpty ? t.note : "No note added",
                                  style: TextStyle(
                                      color: context.textMutedColor,
                                      fontStyle: t.note.isEmpty
                                          ? FontStyle.italic
                                          : null),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${t.transferredAt.day}/${t.transferredAt.month}/${t.transferredAt.year}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: context.textMutedColor),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TransferDialog extends StatefulWidget {
  final Medicine medicine;
  final String from;
  final String to;
  final WarehouseProvider wh;

  const _TransferDialog(
      {required this.medicine,
      required this.from,
      required this.to,
      required this.wh});

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  final _qtyCtrl = TextEditingController(text: '1');
  final _noteCtrl = TextEditingController();
  MedicineBatch? _selectedBatch;
  late String _fromLoc;
  late String _toLoc;

  int _getStock(MedicineBatch b, String loc) {
    if (loc == 'main' || loc == 'clinic') return b.mainStock;
    if (loc == 'store') return b.storeStock;
    if (loc == 'bulkClinic') return b.bulkClinicStock;
    if (loc == 'bulkStore') return b.bulkStoreStock;
    return 0;
  }

  void _updateSelectedBatch() {
    final availableBatches = widget.medicine.batches
        .where((b) => _getStock(b, _fromLoc) > 0)
        .toList();
    if (availableBatches.isNotEmpty) {
      availableBatches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
      _selectedBatch = availableBatches.first;
    } else {
      _selectedBatch = widget.medicine.batches.isNotEmpty
          ? widget.medicine.batches.first
          : null;
    }
  }

  @override
  void initState() {
    super.initState();
    _fromLoc = widget.from;
    _toLoc = widget.to;
    _updateSelectedBatch();
  }

  @override
  Widget build(BuildContext context) {
    final locations = const {
      'bulkClinic': 'Clinic Bulk',
      'clinic': 'Clinic',
      'bulkStore': 'Store Bulk',
      'store': 'Store',
    };

    // Calculate available stock based on selected batch or total
    final available = _selectedBatch != null
        ? _getStock(_selectedBatch!, _fromLoc)
        : (_fromLoc == 'main' || _fromLoc == 'clinic'
            ? widget.medicine.mainStock
            : (_fromLoc == 'store'
                ? widget.medicine.storeStock
                : (_fromLoc == 'bulkClinic'
                    ? widget.medicine.bulkClinicStock
                    : widget.medicine.bulkStoreStock)));

    final primaryColor = _toLoc == 'store' || _toLoc == 'bulkStore'
        ? const Color(0xFF14B8A6)
        : const Color(0xFF6366F1);

    final availableBatches = widget.medicine.batches
        .where((b) => _getStock(b, _fromLoc) > 0)
        .toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.swap_horiz, color: primaryColor),
          const SizedBox(width: 12),
          Expanded(child: Text('Transfer ${widget.medicine.name}')),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: _fromLoc,
              decoration: InputDecoration(
                labelText: 'From Location',
                prefixIcon: const Icon(Icons.warehouse_outlined),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: locations.entries.map((e) {
                return DropdownMenuItem(value: e.key, child: Text(e.value));
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _fromLoc = val;
                    _updateSelectedBatch();
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _toLoc,
              decoration: InputDecoration(
                labelText: 'To Location',
                prefixIcon: const Icon(Icons.warehouse),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: locations.entries.map((e) {
                return DropdownMenuItem(value: e.key, child: Text(e.value));
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _toLoc = val;
                  });
                }
              },
            ),
            const SizedBox(height: 24),
            if (availableBatches.isNotEmpty) ...[
              DropdownButtonFormField<MedicineBatch>(
                value: _selectedBatch,
                decoration: InputDecoration(
                  labelText: 'Select Batch',
                  prefixIcon: const Icon(Icons.layers),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                items: availableBatches.map((b) {
                  final qty = _getStock(b, _fromLoc);
                  final date =
                      '${b.expiryDate.day}/${b.expiryDate.month}/${b.expiryDate.year}';
                  return DropdownMenuItem(
                    value: b,
                    child: Text('Batch: ${b.batchNo} (Qty: $qty, Exp: $date)'),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _selectedBatch = val);
                },
              ),
              const SizedBox(height: 16),
            ],
            Text('Available to transfer: $available ${widget.medicine.unit}',
                style: TextStyle(
                    color: context.textMutedColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: _qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Quantity to Transfer',
                prefixIcon: const Icon(Icons.numbers),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteCtrl,
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                prefixIcon: const Icon(Icons.note_alt_outlined),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: context.textMutedColor))),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () async {
            final qty = int.tryParse(_qtyCtrl.text) ?? 0;
            final sync = context.read<SyncService>();

            // Re-validate against selected batch
            final maxAvail = _selectedBatch != null
                ? _getStock(_selectedBatch!, _fromLoc)
                : (_fromLoc == 'main' || _fromLoc == 'clinic'
                    ? widget.medicine.mainStock
                    : (_fromLoc == 'store'
                        ? widget.medicine.storeStock
                        : (_fromLoc == 'bulkClinic'
                            ? widget.medicine.bulkClinicStock
                            : widget.medicine.bulkStoreStock)));

            if (qty > maxAvail) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    'Insufficient stock in selected batch (Available: $maxAvail)'),
                backgroundColor: AppTheme.danger,
                behavior: SnackBarBehavior.floating,
              ));
              return;
            }

            final err = await widget.wh.transfer(
              medicine: widget.medicine,
              qty: qty,
              from: _fromLoc,
              to: _toLoc,
              batchNo: _selectedBatch?.batchNo,
              expiryDate: _selectedBatch?.expiryDate,
              note: _noteCtrl.text,
              syncService: sync,
              actor: context.read<AuthProvider>().currentUser,
            );
            if (!context.mounted) return;
            if (err != null) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(err),
                backgroundColor: AppTheme.danger,
                behavior: SnackBarBehavior.floating,
              ));
            } else {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('Stock transferred successfully'),
                backgroundColor: AppTheme.success,
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(20),
              ));
            }
          },
          child: const Text('Confirm Transfer'),
        ),
      ],
    );
  }
}

class _BulkStockEntryDialog extends StatefulWidget {
  const _BulkStockEntryDialog();

  @override
  State<_BulkStockEntryDialog> createState() => _BulkStockEntryDialogState();
}

class _BulkItem {
  int clinicQty;
  int storeQty;
  int bulkClinicQty;
  int bulkStoreQty;
  String batchNo;
  DateTime expiryDate;
  
  _BulkItem({
    this.clinicQty = 0,
    this.storeQty = 0,
    this.bulkClinicQty = 0,
    this.bulkStoreQty = 0,
    this.batchNo = '',
    required this.expiryDate,
  });

  int get totalQty => clinicQty + storeQty + bulkClinicQty + bulkStoreQty;
}

class _BulkStockEntryDialogState extends State<_BulkStockEntryDialog> {
  final Map<int, _BulkItem> _selectedItems = {}; // medicineId -> item
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _supplierCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  int _highlightedIndex = 0;
  List<Medicine> _searchResults = [];

  void _onSearch(String q, List<Medicine> all) {
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _highlightedIndex = 0;
      });
      return;
    }
    setState(() {
      _highlightedIndex = 0;
      _searchResults = all.where((m) {
        return m.name.toLowerCase().contains(q.toLowerCase()) ||
            m.barcode.contains(q);
      }).toList();
    });
  }

  void _selectMedicine(Medicine m) {
    setState(() {
      final activeBatch = m.batches.isNotEmpty ? m.batches.last : null;
      _selectedItems[m.id] = _BulkItem(
        bulkClinicQty: 1,
        batchNo: activeBatch?.batchNo ?? '',
        expiryDate: activeBatch?.expiryDate ?? DateTime.now().add(const Duration(days: 365)),
      );
      _searchCtrl.clear();
      _searchResults.clear();
      _highlightedIndex = 0;
    });
    _searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();

    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.1),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Row(
          children: [
            const Icon(Icons.inventory_2, color: AppTheme.primary),
            const SizedBox(width: 12),
            const Text('Bulk Purchase Receipt'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 1000,
        height: 700,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                // Top Search Bar
                Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        setState(() => _highlightedIndex = (_highlightedIndex + 1).clamp(0, _searchResults.length - 1));
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        setState(() => _highlightedIndex = (_highlightedIndex - 1).clamp(0, _searchResults.length - 1));
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                        if (_searchResults.isNotEmpty && _highlightedIndex < _searchResults.length) {
                          _selectMedicine(_searchResults[_highlightedIndex]);
                          return KeyEventResult.handled;
                        }
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocusNode,
                    autofocus: true,
                    onChanged: (q) => _onSearch(q, inv.medicines),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search medicine to add (Arrows to navigate, Enter to choose)...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Selected Items list
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selected Items (${_selectedItems.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _selectedItems.isEmpty
                            ? Center(
                                child: Text('Search and add medicines above to start', style: TextStyle(color: context.textMutedColor)),
                              )
                              : ListView.builder(
                                  itemCount: _selectedItems.length,
                                  itemBuilder: (ctx, i) {
                                    final id = _selectedItems.keys.elementAt(i);
                                    final m = inv.medicines
                                        .firstWhere((e) => e.id == id);
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: context.bgColor
                                            .withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                              Expanded(
                                                flex: 2,
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(m.name,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600)),
                                                    Text(
                                                        'Current Hub: ${m.mainStock}',
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            color: context
                                                                .textMutedColor)),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                                  child: TextField(
                                                    style: const TextStyle(fontSize: 13),
                                                    decoration: const InputDecoration(labelText: 'Batch No', labelStyle: TextStyle(fontSize: 12), isDense: true, contentPadding: EdgeInsets.all(12), border: OutlineInputBorder()),
                                                    onChanged: (v) => _selectedItems[id]!.batchNo = v,
                                                    controller: TextEditingController(text: _selectedItems[id]!.batchNo),
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                                  child: InkWell(
                                                    onTap: () async {
                                                      final picked = await showDatePicker(
                                                        context: context,
                                                        initialDate: _selectedItems[id]!.expiryDate,
                                                        firstDate: DateTime.now(),
                                                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                                                      );
                                                      if (picked != null) {
                                                        setState(() => _selectedItems[id]!.expiryDate = picked);
                                                      }
                                                    },
                                                    child: InputDecorator(
                                                      decoration: const InputDecoration(labelText: 'Expiry', labelStyle: TextStyle(fontSize: 12), isDense: true, contentPadding: EdgeInsets.all(12), border: OutlineInputBorder()),
                                                      child: Text('${_selectedItems[id]!.expiryDate.day}/${_selectedItems[id]!.expiryDate.month}/${_selectedItems[id]!.expiryDate.year}', style: const TextStyle(fontSize: 13)),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  child: Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Expanded(child: _buildQtyField('B.Store', _selectedItems[id]!.bulkStoreQty, (v) => _selectedItems[id]!.bulkStoreQty = v)),
                                                          const SizedBox(width: 4),
                                                          Expanded(child: _buildQtyField('B.Clinic', _selectedItems[id]!.bulkClinicQty, (v) => _selectedItems[id]!.bulkClinicQty = v)),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Row(
                                                        children: [
                                                          Expanded(child: _buildQtyField('Store', _selectedItems[id]!.storeQty, (v) => _selectedItems[id]!.storeQty = v)),
                                                          const SizedBox(width: 4),
                                                          Expanded(child: _buildQtyField('Clinic', _selectedItems[id]!.clinicQty, (v) => _selectedItems[id]!.clinicQty = v)),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                          IconButton(
                                            icon: const Icon(
                                                Icons.remove_circle_outline,
                                                color: AppTheme.danger,
                                                size: 20),
                                            onPressed: () {
                                              setState(() =>
                                                  _selectedItems.remove(id));
                                            },
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
                const Divider(height: 40),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _supplierCtrl,
                        decoration: InputDecoration(
                          labelText: 'Supplier Name',
                          prefixIcon: const Icon(Icons.business),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _noteCtrl,
                        decoration: InputDecoration(
                          labelText: 'Order Notes / Reference',
                          prefixIcon: const Icon(Icons.note_alt_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            // Dropdown overlay results
            if (_searchCtrl.text.isNotEmpty && _searchResults.isNotEmpty)
              Positioned(
                top: 65, // Positioned under the search input
                left: 0,
                right: 0, 
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.borderColor, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      )
                    ],
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    itemBuilder: (context, idx) {
                      final m = _searchResults[idx];
                      final isHighlighted = _highlightedIndex == idx;
                      final isAdded = _selectedItems.containsKey(m.id);

                      return InkWell(
                        onTap: () => _selectMedicine(m),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          color: isHighlighted
                              ? AppTheme.primaryLight.withValues(alpha: 0.08)
                              : null,
                          child: Row(
                            children: [
                              const Icon(Icons.vaccines, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    Text(m.barcode, style: TextStyle(fontSize: 11, color: context.textMutedColor)),
                                  ],
                                ),
                              ),
                              Text('Hub Stock: ${m.mainStock}', style: TextStyle(color: context.textMutedColor)),
                              const SizedBox(width: 16),
                              if (isAdded)
                                const Icon(Icons.check_circle, color: AppTheme.success, size: 20)
                              else
                                const Icon(Icons.add_circle_outline, color: AppTheme.primaryLight, size: 20),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              Text('Cancel', style: TextStyle(color: context.textMutedColor)),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _selectedItems.isEmpty
              ? null
              : () {
                  final actor = context.read<AuthProvider>().currentUser;
                  for (final entry in _selectedItems.entries) {
                    final mId = entry.key;
                    final item = entry.value;
                    if (item.totalQty <= 0) continue;
                    inv.addBatchStock(
                      {mId: item.clinicQty},
                      storeUpdates: {mId: item.storeQty},
                      bulkClinicUpdates: {mId: item.bulkClinicQty},
                      bulkStoreUpdates: {mId: item.bulkStoreQty},
                      note: _noteCtrl.text,
                      supplier: _supplierCtrl.text,
                      batchNo: item.batchNo.trim(),
                      expiryDate: item.expiryDate,
                      actor: actor,
                    );
                  }
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Purchase record created successfully'),
                    backgroundColor: AppTheme.success,
                    behavior: SnackBarBehavior.floating,
                  ));
                },
          icon: const Icon(Icons.check),
          label: const Text('Confirm Receipt'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildQtyField(String label, int val, Function(int) onChanged) {
    return TextField(
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true, 
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12), 
        labelText: label, 
        labelStyle: const TextStyle(fontSize: 11), 
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onChanged: (v) {
        final qty = int.tryParse(v) ?? 0;
        onChanged(qty);
      },
      controller: TextEditingController(text: val == 0 ? '' : '$val'),
    );
  }
}

class _PurchaseHistoryTab extends StatefulWidget {
  const _PurchaseHistoryTab();

  @override
  State<_PurchaseHistoryTab> createState() => _PurchaseHistoryTabState();
}

class _PurchaseHistoryTabState extends State<_PurchaseHistoryTab> {
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    
    var history = inv.purchaseHistory;
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      history = history.where((p) => p.medicineName.toLowerCase().contains(q) || p.supplier.toLowerCase().contains(q)).toList();
    }
    
    // Apply date filter
    if (_startDate != null) {
      history = history.where((p) => p.purchasedAt.isAfter(_startDate!) || p.purchasedAt.isAtSameMomentAs(_startDate!)).toList();
    }
    if (_endDate != null) {
      // add 1 day to include the entire end date
      final end = _endDate!.add(const Duration(days: 1));
      history = history.where((p) => p.purchasedAt.isBefore(end)).toList();
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.cardColor,
            border: Border(bottom: BorderSide(color: context.borderColor)),
          ),
          child: Row(
            children: [
              const Icon(Icons.history, color: AppTheme.primary),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Inventory Purchase History',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  Text('${history.length} records found',
                      style: TextStyle(color: context.textMutedColor)),
                ],
              ),
              const Spacer(),
              
              // Date Filter
              Container(
                decoration: BoxDecoration(
                  color: context.bgColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: _startDate == null ? context.textMutedColor : AppTheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      icon: const Icon(Icons.calendar_month, size: 20),
                      label: Text(
                        _startDate == null 
                            ? 'Filter by Date' 
                            : '${_startDate!.day}/${_startDate!.month}/${_startDate!.year} - ${_endDate?.day ?? ''}/${_endDate?.month ?? ''}/${_endDate?.year ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: _startDate != null && _endDate != null ? DateTimeRange(start: _startDate!, end: _endDate!) : null,
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: AppTheme.primary,
                                  onPrimary: Colors.white,
                                  onSurface: Colors.black,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setState(() {
                            _startDate = picked.start;
                            _endDate = picked.end;
                          });
                        }
                      },
                    ),
                    if (_startDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        color: AppTheme.danger,
                        tooltip: 'Clear Date Filter',
                        onPressed: () => setState(() { _startDate = null; _endDate = null; }),
                      ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.arrow_drop_down, size: 20, color: AppTheme.primary),
                      tooltip: 'Date Presets',
                      onSelected: (value) {
                        final now = DateTime.now();
                        setState(() {
                          if (value == 'today') {
                            _startDate = DateTime(now.year, now.month, now.day);
                            _endDate = _startDate;
                          } else if (value == 'yesterday') {
                            _startDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
                            _endDate = _startDate;
                          } else if (value == 'this_week') {
                            _startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
                            _endDate = _startDate!.add(const Duration(days: 6));
                          } else if (value == 'this_month') {
                            _startDate = DateTime(now.year, now.month, 1);
                            // Set to last day of month
                            _endDate = DateTime(now.year, now.month + 1, 0);
                          }
                        });
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'today', child: Text('Today')),
                        const PopupMenuItem(value: 'yesterday', child: Text('Yesterday')),
                        const PopupMenuItem(value: 'this_week', child: Text('This Week')),
                        const PopupMenuItem(value: 'this_month', child: Text('This Month')),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              
              // Search Bar
              SizedBox(
                width: 280,
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search medicine or supplier...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: context.bgColor.withValues(alpha: 0.5),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 64, color: context.textMutedColor),
                      const SizedBox(height: 24),
                      Text('No purchase records found', style: TextStyle(color: context.textMutedColor, fontSize: 16)),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 300),
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(context.bgColor.withValues(alpha: 0.5)),
                            headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
                            dataRowMinHeight: 60,
                            dataRowMaxHeight: 60,
                            dividerThickness: 1,
                            columns: const [
                              DataColumn(label: Text('Date & Time')),
                              DataColumn(label: Text('Medicine Name')),
                              DataColumn(label: Text('Supplier')),
                              DataColumn(label: Text('Purchase Price'), numeric: true),
                              DataColumn(label: Text('Qty'), numeric: true),
                              DataColumn(label: Text('Notes')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: history.map((p) {
                              final dateStr = '${p.purchasedAt.day.toString().padLeft(2,'0')}/${p.purchasedAt.month.toString().padLeft(2,'0')}/${p.purchasedAt.year} ${p.purchasedAt.hour.toString().padLeft(2,'0')}:${p.purchasedAt.minute.toString().padLeft(2,'0')}';
                              return DataRow(
                                cells: [
                                  DataCell(Text(dateStr, style: const TextStyle(fontSize: 13))),
                                  DataCell(Text(p.medicineName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                                  DataCell(
                                    p.supplier.isEmpty 
                                        ? Text('-', style: TextStyle(color: context.textMutedColor))
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.business, size: 14, color: context.textMutedColor),
                                              const SizedBox(width: 6),
                                              Text(p.supplier, style: const TextStyle(fontWeight: FontWeight.w600)),
                                            ],
                                          )
                                  ),
                                  DataCell(Text('₹${p.purchasePrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.success))),
                                  DataCell(Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: AppTheme.indigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                    child: Text('+${p.qty}', style: const TextStyle(color: AppTheme.indigo, fontWeight: FontWeight.bold)),
                                  )),
                                  DataCell(SizedBox(
                                    width: 150,
                                    child: Text(p.note.isEmpty ? '-' : p.note, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.textMutedColor, fontStyle: FontStyle.italic)),
                                  )),
                                  DataCell(Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                        color: AppTheme.primary,
                                        tooltip: 'Edit Record',
                                        onPressed: () => showDialog(context: context, builder: (ctx) => _EditPurchaseDialog(purchase: p)),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 18),
                                        color: AppTheme.danger,
                                        tooltip: 'Delete Record',
                                        onPressed: () => _showDeleteConfirm(context, inv, p),
                                      ),
                                    ],
                                  )),
                                ]
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

void _showDeleteConfirm(
    BuildContext context, InventoryProvider inv, PurchaseRecord p) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Purchase Record?'),
      content: Text(
          'This will also deduct ${p.qty} from the Hub stock for ${p.medicineName}. Are you sure?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          onPressed: () {
            inv.deletePurchase(p, syncService: context.read<SyncService>());
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Record deleted and stock reverted'),
              backgroundColor: AppTheme.success,
              behavior: SnackBarBehavior.floating,
            ));
          },
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

class _EditPurchaseDialog extends StatefulWidget {
  final PurchaseRecord purchase;
  const _EditPurchaseDialog({required this.purchase});

  @override
  State<_EditPurchaseDialog> createState() => _EditPurchaseDialogState();
}

class _EditPurchaseDialogState extends State<_EditPurchaseDialog> {
  late TextEditingController _qtyCtrl;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '${widget.purchase.qty}');
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    return AlertDialog(
      title: Text('Edit Purchase: ${widget.purchase.medicineName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
              'Updating the quantity will automatically adjust the Hub stock level by the difference.'),
          const SizedBox(height: 20),
          TextField(
            controller: _qtyCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Quantity Received',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final qty = int.tryParse(_qtyCtrl.text) ?? 0;
            if (qty > 0) {
              inv.updatePurchase(widget.purchase, qty,
                  syncService: context.read<SyncService>());
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Record updated and stock adjusted'),
                backgroundColor: AppTheme.success,
                behavior: SnackBarBehavior.floating,
              ));
            }
          },
          child: const Text('Update'),
        ),
      ],
    );
  }
}

class _BulkTransferDialog extends StatefulWidget {
  final WarehouseProvider wh;
  const _BulkTransferDialog({required this.wh});

  @override
  State<_BulkTransferDialog> createState() => _BulkTransferDialogState();
}

class _BulkTransferDialogState extends State<_BulkTransferDialog> {
  final Map<int, int> _transferQtys = {}; // medicineId -> qty to transfer
  final Set<int> _selectedIds = {};
  String _searchQuery = '';
  bool _isProcessing = false;
  String _fromLoc = 'bulkClinic';
  String _toLoc = 'clinic';

  final FocusNode _searchFocusNode = FocusNode();
  int _highlightedIndex = 0;
  final Map<int, FocusNode> _qtyFocusNodes = {};

  FocusNode _getQtyFocusNode(int id) {
    return _qtyFocusNodes.putIfAbsent(id, () => FocusNode());
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    for (var fn in _qtyFocusNodes.values) {
      fn.dispose();
    }
    super.dispose();
  }

  void _selectMedicine(Medicine m) {
    setState(() {
      _selectedIds.add(m.id);
      _transferQtys[m.id] = 0;
      _searchQuery = '';
      _highlightedIndex = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getQtyFocusNode(m.id).requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final syncService = context.read<SyncService>();

    final locations = const {
      'bulkClinic': 'Clinic Bulk',
      'clinic': 'Clinic',
      'bulkStore': 'Store Bulk',
      'store': 'Store',
    };

    // Get all medicines that have stock in the source location
    final eligibleMeds = inv.rawMedicines.where((m) {
      int stock = 0;
      if (_fromLoc == 'bulkClinic') stock = m.bulkClinicStock;
      if (_fromLoc == 'main' || _fromLoc == 'clinic') stock = m.mainStock;
      if (_fromLoc == 'bulkStore') stock = m.bulkStoreStock;
      if (_fromLoc == 'store') stock = m.storeStock;
      return stock > 0;
    }).toList();

    // Filter by search query
    final filtered = eligibleMeds
        .where((m) =>
            m.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            m.barcode.contains(_searchQuery))
        .toList();

    final selectedMedicines =
        inv.rawMedicines.where((m) => _selectedIds.contains(m.id)).toList();

    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.primaryLight.withValues(alpha: 0.1),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Row(
          children: [
            const Icon(Icons.swap_horiz, color: AppTheme.primaryLight),
            const SizedBox(width: 12),
            const Text('Bulk Stock Transfer',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 800,
        height: 650,
        child: _isProcessing
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Processing bulk transfer, please wait...',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    children: [
                      // Colour-coded transfer configuration rows
                      Row(
                        children: [
                          // Source Card (Orange/Amber theme)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: Colors.amber.withValues(alpha: 0.25),
                                    width: 1.5),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.unarchive_outlined,
                                          size: 16, color: Colors.orange),
                                      SizedBox(width: 6),
                                      Text('FROM (SOURCE LOCATION)',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.orange,
                                              letterSpacing: 0.5)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    value: _fromLoc,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                    ),
                                    dropdownColor: context.surfaceColor,
                                    items: locations.entries
                                        .map((e) => DropdownMenuItem(
                                            value: e.key, child: Text(e.value)))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _fromLoc = val;
                                          _selectedIds.clear();
                                          _transferQtys.clear();
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(Icons.arrow_forward_rounded,
                                size: 24, color: AppTheme.primaryLight),
                          ),
                          // Destination Card (Indigo/Success theme)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: AppTheme.success
                                        .withValues(alpha: 0.25),
                                    width: 1.5),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.archive_outlined,
                                          size: 16, color: AppTheme.success),
                                      SizedBox(width: 6),
                                      Text('TO (DESTINATION LOCATION)',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.success,
                                              letterSpacing: 0.5)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    value: _toLoc,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                    ),
                                    dropdownColor: context.surfaceColor,
                                    items: locations.entries
                                        .map((e) => DropdownMenuItem(
                                            value: e.key, child: Text(e.value)))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _toLoc = val;
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Search & Select All row
                      Row(
                        children: [
                          Expanded(
                            child: Focus(
                              onKeyEvent: (node, event) {
                                if (event is KeyDownEvent) {
                                  if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowDown) {
                                    setState(() {
                                      _highlightedIndex =
                                          (_highlightedIndex + 1)
                                              .clamp(0, filtered.length - 1);
                                    });
                                    return KeyEventResult.handled;
                                  } else if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowUp) {
                                    setState(() {
                                      _highlightedIndex =
                                          (_highlightedIndex - 1)
                                              .clamp(0, filtered.length - 1);
                                    });
                                    return KeyEventResult.handled;
                                  } else if (event.logicalKey ==
                                      LogicalKeyboardKey.enter) {
                                    if (filtered.isNotEmpty &&
                                        _highlightedIndex < filtered.length) {
                                      final m = filtered[_highlightedIndex];
                                      _selectMedicine(m);
                                      return KeyEventResult.handled;
                                    }
                                  }
                                }
                                return KeyEventResult.ignored;
                              },
                              child: TextField(
                                focusNode: _searchFocusNode,
                                autofocus: true,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.search),
                                  hintText:
                                      'Search & Select medicines (Arrows to navigate, Enter to choose)...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onChanged: (v) => setState(() {
                                  _searchQuery = v;
                                  _highlightedIndex = 0;
                                }),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.select_all),
                            label: const Text('Select All'),
                            onPressed: () {
                              setState(() {
                                for (var m in filtered) {
                                  _selectedIds.add(m.id);
                                  _transferQtys[m.id] = 0;
                                }
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.percent),
                            label: const Text('50%'),
                            onPressed: () {
                              setState(() {
                                for (var id in _selectedIds) {
                                  final m = inv.rawMedicines
                                      .where((med) => med.id == id)
                                      .firstOrNull;
                                  if (m != null) {
                                    final maxQty = _fromLoc == 'bulkClinic'
                                        ? m.bulkClinicStock
                                        : (_fromLoc == 'main' || _fromLoc == 'clinic'
                                            ? m.mainStock
                                            : (_fromLoc == 'bulkStore'
                                                ? m.bulkStoreStock
                                                : m.storeStock));
                                    _transferQtys[id] = (maxQty * 0.5).round();
                                  }
                                }
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            child: const Text('Deselect All'),
                            onPressed: () {
                              setState(() {
                                _selectedIds.clear();
                                _transferQtys.clear();
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Selected list section
                      Expanded(
                        child: selectedMedicines.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.playlist_add_rounded,
                                        size: 48,
                                        color: context.textMutedColor),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No items added to transfer list.\nSearch and select medicines above to add them.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: context.textMutedColor,
                                          fontSize: 14),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: selectedMedicines.length,
                                itemBuilder: (ctx, idx) {
                                  final m = selectedMedicines[idx];
                                  final qty = _transferQtys[m.id] ?? 0;

                                  return _BulkTransferRow(
                                    key: ValueKey('${m.id}_$_fromLoc'),
                                    medicine: m,
                                    isSelected: true,
                                    isHighlighted: false,
                                    fromLoc: _fromLoc,
                                    toLoc: _toLoc,
                                    initialQty: qty,
                                    focusNode: _getQtyFocusNode(m.id),
                                    onSelectedChanged: (val) {
                                      setState(() {
                                        if (val == false) {
                                          _selectedIds.remove(m.id);
                                          _transferQtys.remove(m.id);
                                        }
                                      });
                                    },
                                    onQtyChanged: (val) {
                                      _transferQtys[m.id] = val;
                                    },
                                    onSubmitted: () {
                                      setState(() {
                                        _searchQuery = '';
                                        _highlightedIndex = 0;
                                      });
                                      _searchFocusNode.requestFocus();
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                  // Dropdown overlay results
                  if (_searchQuery.isNotEmpty && filtered.isNotEmpty)
                    Positioned(
                      top: 195, // Positioned right under the search input
                      left: 0,
                      right:
                          180, // Adjust alignment to match search field width
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 250),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: context.borderColor, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            )
                          ],
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (context, idx) {
                            final m = filtered[idx];
                            final isHighlighted = _highlightedIndex == idx;
                            final maxQty = _fromLoc == 'bulkClinic'
                                ? m.bulkClinicStock
                                : (_fromLoc == 'main' || _fromLoc == 'clinic'
                                    ? m.mainStock
                                    : (_fromLoc == 'bulkStore'
                                        ? m.bulkStoreStock
                                        : m.storeStock));

                            return InkWell(
                              onTap: () {
                                _selectMedicine(m);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                color: isHighlighted
                                    ? AppTheme.primaryLight
                                        .withValues(alpha: 0.08)
                                    : null,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(m.name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                    Text('Stock: $maxQty',
                                        style: TextStyle(
                                            color: context.textMutedColor,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
      ),
      actions: _isProcessing
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style:
                    FilledButton.styleFrom(backgroundColor: AppTheme.success),
                icon: const Icon(Icons.send),
                label: Text('Transfer Selected (${_selectedIds.length})'),
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () async {
                        setState(() => _isProcessing = true);
                        int successCount = 0;
                        final failures = <String>[];
                        for (final id in _selectedIds) {
                          final m = inv.rawMedicines
                              .where((med) => med.id == id)
                              .firstOrNull;
                          final qty = _transferQtys[id] ?? 0;
                          if (m != null && qty > 0) {
                            final err = await widget.wh.transfer(
                              medicine: m,
                              qty: qty,
                              from: _fromLoc,
                              to: _toLoc,
                              note: 'Bulk Transfer',
                              syncService: syncService,
                              actor: context.read<AuthProvider>().currentUser,
                            );
                            if (err == null) {
                              successCount++;
                            } else {
                              failures.add('${m.name}: $err');
                            }
                          }
                        }
                        if (mounted) {
                          Navigator.pop(context);
                          if (failures.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Successfully transferred stock for $successCount medicines.'),
                                backgroundColor: AppTheme.success,
                              ),
                            );
                          } else {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Bulk Transfer Results'),
                                content: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('Successfully transferred: $successCount items.\n'),
                                      const Text('Failed transfers:', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.danger)),
                                      const SizedBox(height: 8),
                                      ...failures.map((f) => Text('• $f', style: const TextStyle(fontSize: 12))),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          }
                        }
                      },
              ),
            ],
    );
  }
}

class _BulkTransferRow extends StatefulWidget {
  final Medicine medicine;
  final bool isSelected;
  final bool isHighlighted;
  final String fromLoc;
  final String toLoc;
  final int initialQty;
  final FocusNode focusNode;
  final ValueChanged<bool?> onSelectedChanged;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback onSubmitted;

  const _BulkTransferRow({
    super.key,
    required this.medicine,
    required this.isSelected,
    required this.isHighlighted,
    required this.fromLoc,
    required this.toLoc,
    required this.initialQty,
    required this.focusNode,
    required this.onSelectedChanged,
    required this.onQtyChanged,
    required this.onSubmitted,
  });

  @override
  State<_BulkTransferRow> createState() => _BulkTransferRowState();
}

class _BulkTransferRowState extends State<_BulkTransferRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialQty}');
  }

  @override
  void didUpdateWidget(covariant _BulkTransferRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQty != widget.initialQty) {
      _controller.text = '${widget.initialQty}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxQty = widget.fromLoc == 'bulkClinic'
        ? widget.medicine.bulkClinicStock
        : (widget.fromLoc == 'main' || widget.fromLoc == 'clinic'
            ? widget.medicine.mainStock
            : (widget.fromLoc == 'bulkStore'
                ? widget.medicine.bulkStoreStock
                : widget.medicine.storeStock));

    final destQty = widget.toLoc == 'bulkClinic'
        ? widget.medicine.bulkClinicStock
        : (widget.toLoc == 'main' || widget.toLoc == 'clinic'
            ? widget.medicine.mainStock
            : (widget.toLoc == 'bulkStore'
                ? widget.medicine.bulkStoreStock
                : widget.medicine.storeStock));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.isHighlighted
              ? AppTheme.primaryLight
              : (widget.isSelected
                  ? AppTheme.primaryLight.withValues(alpha: 0.5)
                  : context.borderColor.withValues(alpha: 0.3)),
          width: widget.isHighlighted || widget.isSelected ? 1.5 : 1,
        ),
      ),
      color: widget.isHighlighted
          ? AppTheme.primaryLight.withValues(alpha: 0.05)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Checkbox(
              value: widget.isSelected,
              onChanged: widget.onSelectedChanged,
              activeColor: AppTheme.primaryLight,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.medicine.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    'Available Stock: $maxQty | Dest Stock: $destQty',
                    style:
                        TextStyle(color: context.textMutedColor, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            if (widget.isSelected) ...[
              const Text('Qty:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(width: 8),
              SizedBox(
                width: 75,
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.tab)) {
                      widget.onSubmitted();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: widget.focusNode,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                    onTap: () => _controller.selection = TextSelection(
                        baseOffset: 0, extentOffset: _controller.text.length),
                    onChanged: (val) {
                      final parsed = int.tryParse(val) ?? 0;
                      final clamped = parsed.clamp(0, maxQty);
                      widget.onQtyChanged(clamped);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('/ $maxQty',
                  style:
                      TextStyle(color: context.textMutedColor, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StockReportTab extends StatefulWidget {
  const _StockReportTab();

  @override
  State<_StockReportTab> createState() => _StockReportTabState();
}

class _StockReportTabState extends State<_StockReportTab> {
  String _search = '';
  String _sortBy = 'name'; // 'name', 'bulk', 'counter', 'total'
  bool _sortAscending = true;

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final meds = inv.rawMedicines.where((m) {
      return m.name.toLowerCase().contains(_search.toLowerCase()) ||
          m.barcode.contains(_search);
    }).toList();

    // Sort medicines
    meds.sort((a, b) {
      int compare;
      if (_sortBy == 'bulk') {
        final bulkA = a.bulkClinicStock + a.bulkStoreStock;
        final bulkB = b.bulkClinicStock + b.bulkStoreStock;
        compare = bulkA.compareTo(bulkB);
      } else if (_sortBy == 'counter') {
        final counterA = a.mainStock + a.storeStock;
        final counterB = b.mainStock + b.storeStock;
        compare = counterA.compareTo(counterB);
      } else if (_sortBy == 'total') {
        compare = a.totalStock.compareTo(b.totalStock);
      } else {
        compare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _sortAscending ? compare : -compare;
    });

    return Column(
      children: [
        // Search & Filter Header
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            border: Border(
                bottom: BorderSide(
                    color: context.borderColor.withValues(alpha: 0.5))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search medicine...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: context.bgColor.withValues(alpha: 0.5),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              DropdownButton<String>(
                value: _sortBy,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'name', child: Text('Sort by Name')),
                  DropdownMenuItem(value: 'bulk', child: Text('Sort by Bulk Stock')),
                  DropdownMenuItem(value: 'counter', child: Text('Sort by Counter Stock')),
                  DropdownMenuItem(value: 'total', child: Text('Sort by Total Stock')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      if (_sortBy == v) {
                        _sortAscending = !_sortAscending;
                      } else {
                        _sortBy = v;
                        _sortAscending = true;
                      }
                    });
                  }
                },
              ),
              IconButton(
                icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
                onPressed: () => setState(() => _sortAscending = !_sortAscending),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: meds.isEmpty
              ? const AppEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No medicines found',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: meds.length,
                  itemBuilder: (ctx, i) {
                    final m = meds[i];
                    final bulkTotal = m.bulkClinicStock + m.bulkStoreStock;
                    final counterTotal = m.mainStock + m.storeStock;
                    
                    return _StockReportRow(
                      medicine: m,
                      bulkTotal: bulkTotal,
                      counterTotal: counterTotal,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _StockReportRow extends StatefulWidget {
  final Medicine medicine;
  final int bulkTotal;
  final int counterTotal;

  const _StockReportRow({
    required this.medicine,
    required this.bulkTotal,
    required this.counterTotal,
  });

  @override
  State<_StockReportRow> createState() => _StockReportRowState();
}

class _StockReportRowState extends State<_StockReportRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.medicine;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _isHovered
              ? AppTheme.primary.withValues(alpha: 0.04)
              : context.surfaceColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isHovered
                ? AppTheme.primary.withValues(alpha: 0.3)
                : context.borderColor.withValues(alpha: 0.5),
            width: _isHovered ? 1.5 : 1,
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.vaccines, color: AppTheme.primary, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    m.category.isEmpty ? 'General' : m.category,
                    style: TextStyle(color: context.textMutedColor, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Bulk Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'BULK STOCK',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: context.textMutedColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.bulkTotal} ${m.unit}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.indigo,
                    ),
                  ),
                  Text(
                    'Store: ${m.bulkStoreStock} | Clinic: ${m.bulkClinicStock}',
                    style: TextStyle(fontSize: 9, color: context.textMutedColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Counter Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'COUNTER STOCK',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: context.textMutedColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.counterTotal} ${m.unit}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF14B8A6),
                    ),
                  ),
                  Text(
                    'Store: ${m.storeStock} | Clinic: ${m.mainStock}',
                    style: TextStyle(fontSize: 9, color: context.textMutedColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
