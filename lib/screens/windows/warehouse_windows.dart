import 'dart:io';
import 'package:flutter/material.dart';
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
    _tabs = TabController(length: 3, vsync: this);
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
    if (!auth.hasInventoryWriteAccess) return;

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

      int added = 0;
      int updated = 0;
      if (!context.mounted) return;
      final inv = context.read<InventoryProvider>();

      bool isTally = false;
      // Scan rows to find "Particulars" to auto-detect Tally exports
      for (int i = 0; i < table.maxRows; i++) {
        final row = table.row(i);
        for (int j = 0; j < row.length; j++) {
          final cellValue = row[j]?.value?.toString().trim().toLowerCase() ?? '';
          if (cellValue == 'particulars') {
            isTally = true;
            break;
          }
        }
        if (isTally) break;
      }

      if (isTally) {
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
                ? (double.tryParse(row[3]?.value?.toString().trim() ?? '') ?? 0.0)
                : 0.0;
            final double rateVal = row.length > 4
                ? (double.tryParse(row[4]?.value?.toString().trim() ?? '') ?? 0.0)
                : 0.0;

            final mainStock = qtyVal.round();
            final storeStock = 0;
            final purchasePrice = rateVal;
            final sellingPrice = rateVal;

            final existing = inv.medicines
                .where((m) => m.name.toLowerCase() == nameCell.toLowerCase())
                .firstOrNull;

            if (existing != null) {
              existing
                ..category = category
                ..unit = unit
                ..purchasePrice = purchasePrice > 0 ? purchasePrice : existing.purchasePrice
                ..sellingPrice = sellingPrice > 0 ? sellingPrice : existing.sellingPrice;

              inv.updateMedicine(existing);

              if (mainStock > 0) {
                inv.addBatchStock(
                  {existing.id: mainStock},
                  storeUpdates: {existing.id: storeStock},
                  batchNo: 'IMPORT-${DateTime.now().millisecondsSinceEpoch}',
                  expiryDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  note: 'Imported from Excel (Tally)',
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
              inv.addMedicine(newMed);

              if (mainStock > 0) {
                inv.addBatchStock(
                  {newMed.id: mainStock},
                  storeUpdates: {newMed.id: storeStock},
                  batchNo: 'IMPORT-${DateTime.now().millisecondsSinceEpoch}',
                  expiryDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  note: 'Imported from Excel (Tally)',
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

        final nameIdx = getColIdx(['medicine name', 'item name', 'product name']);
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

        // 3. Process rows
        for (int i = headerRowIndex + 1; i < table.maxRows; i++) {
          final row = table.row(i);

          String getCellStr(int idx, String def) =>
              (idx != -1 && idx < row.length)
                  ? (row[idx]?.value?.toString().trim() ?? def)
                  : def;
          double getCellDbl(int idx, double def) => (idx != -1 &&
                  idx < row.length)
              ? (double.tryParse(row[idx]?.value?.toString().trim() ?? '') ?? def)
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
          final existing = inv.medicines
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

            inv.updateMedicine(existing);

            // If stock is provided in Excel, add it as a new batch to avoid total drift
            if (mainStock > 0 || storeStock > 0) {
              inv.addBatchStock(
                {existing.id: mainStock},
                storeUpdates: {existing.id: storeStock},
                batchNo: 'IMPORT-${DateTime.now().millisecondsSinceEpoch}',
                expiryDate: DateTime.now()
                    .add(const Duration(days: 365 * 2)), // 2 year default
                note: 'Imported from Excel',
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
            inv.addMedicine(newMed);

            if (mainStock > 0 || storeStock > 0) {
              inv.addBatchStock(
                {newMed.id: mainStock},
                storeUpdates: {newMed.id: storeStock},
                batchNo: 'IMPORT-${DateTime.now().millisecondsSinceEpoch}',
                expiryDate: DateTime.now().add(const Duration(days: 365 * 2)),
                note: 'Imported from Excel',
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
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        title: const Text('Stock Control'),
        elevation: 0,
        backgroundColor: context.surfaceColor,
        actions: [
          if (auth.hasInventoryWriteAccess) ...[
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
          ]
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.primary,
          unselectedLabelColor: context.textMutedColor,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_customize), text: 'Overview'),
            Tab(icon: Icon(Icons.compare_arrows), text: 'Transfers'),
            Tab(icon: Icon(Icons.shopping_bag_outlined), text: 'Purchases'),
          ],
        ),
      ),
      floatingActionButton: auth.hasInventoryWriteAccess
          ? FloatingActionButton.extended(
              onPressed: () {
                MedicineDialog.show(context, medicine: null);
              },
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('New Medicine',
                  style: TextStyle(color: Colors.white)),
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: const [
          _StockLevelsTab(),
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
                  if (auth.hasWarehouseWriteAccess) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Bulk Transfer Clinic Stock to Store',
                      icon: const Icon(Icons.swap_horiz, color: AppTheme.success),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (ctx) => _BulkTransferDialog(wh: wh),
                      ),
                    ),
                  ],
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
              mainAxisExtent: 260, // Fixed height for consistency
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
              Row(
                children: [
                  Expanded(
                    child: _MetricBlock(
                      label: 'Clinic',
                      value: widget.medicine.mainStock,
                      icon: Icons.medical_services,
                      color: AppTheme.indigo,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricBlock(
                      label: 'Store',
                      value: widget.medicine.storeStock,
                      icon: Icons.storefront,
                      color: const Color(0xFF14B8A6),
                      isWarning: widget.medicine.isLowStock,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
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
                      } else if (val == 'send') {
                        _showTransferDialog(context, widget.medicine, 'main',
                            'store', widget.wh);
                      } else if (val == 'return') {
                        _showTransferDialog(context, widget.medicine, 'store',
                            'main', widget.wh);
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
                          value: 'send',
                          child: Row(children: [
                            Icon(Icons.arrow_forward),
                            Text(' Send to Store')
                          ])),
                      const PopupMenuItem(
                          value: 'return',
                          child: Row(children: [
                            Icon(Icons.arrow_back),
                            Text(' Return to Clinic')
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
                    Navigator.pop(context);
                    MedicineDialog.show(context, medicine: m);
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
                                    const Text('CLINIC',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold)),
                                    Text('${b.mainStock}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text('STORE',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold)),
                                    Text('${b.storeStock}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16)),
                                  ],
                                ),
                              ),
                              if (canTransfer)
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
                          backgroundColor: const Color(0xFF14B8A6), // Teal
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _showTransfer(context, m, 'main', 'store', wh);
                        },
                        icon: const Icon(Icons.arrow_forward, size: 16),
                        label: const Text('Send to Store'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.indigo, // Indigo
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _showTransfer(context, m, 'store', 'main', wh);
                        },
                        icon: const Icon(Icons.arrow_back, size: 16),
                        label: const Text('Return to Clinic'),
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
  final MedicineBatch batch;
  const _EditBatchDialog({required this.medicine, required this.batch});

  @override
  State<_EditBatchDialog> createState() => _EditBatchDialogState();
}

class _EditBatchDialogState extends State<_EditBatchDialog> {
  late final _batchNoCtrl = TextEditingController(text: widget.batch.batchNo);
  late final _hubStockCtrl =
      TextEditingController(text: '${widget.batch.mainStock}');
  late final _storeStockCtrl =
      TextEditingController(text: '${widget.batch.storeStock}');
  late DateTime _expiryDate = widget.batch.expiryDate;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Batch Details'),
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
                  controller: _hubStockCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Clinic Stock', isDense: true),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _storeStockCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Store Stock', isDense: true),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save Changes'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _expiryDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (d != null) setState(() => _expiryDate = d);
  }

  void _save() {
    final inv = context.read<InventoryProvider>();
    final sync = context.read<SyncService>();

    inv.updateBatchDetail(
      widget.medicine,
      widget.batch,
      batchNo: _batchNoCtrl.text.trim(),
      expiryDate: _expiryDate,
      mainStock: int.tryParse(_hubStockCtrl.text) ?? widget.batch.mainStock,
      storeStock: int.tryParse(_storeStockCtrl.text) ?? widget.batch.storeStock,
      syncService: sync,
    );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Batch details updated')),
    );
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

  @override
  void initState() {
    super.initState();
    // Default to the first available batch in the 'from' warehouse if any exist
    final availableBatches = widget.medicine.batches.where((b) =>
        widget.from == 'main' ? b.mainStock > 0 : b.storeStock > 0).toList();
    if (availableBatches.isNotEmpty) {
      // Sort by soonest expiry
      availableBatches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
      _selectedBatch = availableBatches.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fromLabel = widget.from == 'main' ? 'Clinic' : 'Store';
    final toLabel = widget.to == 'main' ? 'Clinic' : 'Store';
    
    // Calculate available stock based on selected batch or total
    final available = _selectedBatch != null
        ? (widget.from == 'main' ? _selectedBatch!.mainStock : _selectedBatch!.storeStock)
        : (widget.from == 'main' ? widget.medicine.mainStock : widget.medicine.storeStock);
        
    final primaryColor = widget.to == 'store'
        ? const Color(0xFF14B8A6)
        : const Color(0xFF6366F1);

    final availableBatches = widget.medicine.batches.where((b) =>
        widget.from == 'main' ? b.mainStock > 0 : b.storeStock > 0).toList();

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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('From',
                            style: TextStyle(
                                fontSize: 11, color: context.textMutedColor)),
                        const SizedBox(height: 4),
                        Text(fromLabel,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded,
                      size: 16, color: primaryColor.withValues(alpha: 0.5)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('To',
                            style: TextStyle(
                                fontSize: 11, color: context.textMutedColor)),
                        const SizedBox(height: 4),
                        Text(toLabel,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: primaryColor)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            if (availableBatches.isNotEmpty) ...[
              DropdownButtonFormField<MedicineBatch>(
                value: _selectedBatch,
                decoration: InputDecoration(
                  labelText: 'Select Batch',
                  prefixIcon: const Icon(Icons.layers),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: availableBatches.map((b) {
                  final qty = widget.from == 'main' ? b.mainStock : b.storeStock;
                  final date = '${b.expiryDate.day}/${b.expiryDate.month}/${b.expiryDate.year}';
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
              ? (widget.from == 'main' ? _selectedBatch!.mainStock : _selectedBatch!.storeStock)
              : (widget.from == 'main' ? widget.medicine.mainStock : widget.medicine.storeStock);
              
            if (qty > maxAvail) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Insufficient stock in selected batch (Available: $maxAvail)'),
                backgroundColor: AppTheme.danger,
                behavior: SnackBarBehavior.floating,
              ));
              return;
            }

            final err = await widget.wh.transfer(
              medicine: widget.medicine,
              qty: qty,
              from: widget.from,
              to: widget.to,
              batchNo: _selectedBatch?.batchNo,
              expiryDate: _selectedBatch?.expiryDate,
              note: _noteCtrl.text,
              syncService: sync,
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

class _BulkStockEntryDialogState extends State<_BulkStockEntryDialog> {
  final Map<int, int> _selectedItems = {}; // medicineId -> qty
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _supplierCtrl = TextEditingController();
  final TextEditingController _batchNoCtrl = TextEditingController();
  DateTime _expiryDate = DateTime.now().add(const Duration(days: 365));
  List<Medicine> _searchResults = [];

  void _onSearch(String q, List<Medicine> all) {
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() {
      _searchResults = all.where((m) {
        return m.name.toLowerCase().contains(q.toLowerCase()) ||
            m.barcode.contains(q);
      }).toList();
    });
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
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Side: Search & Add
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchCtrl,
                          onChanged: (q) => _onSearch(q, inv.medicines),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'Search medicine to add...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _searchResults.isEmpty &&
                                  _searchCtrl.text.isNotEmpty
                              ? const Center(child: Text('No medicines found'))
                              : ListView.builder(
                                  itemCount: _searchResults.length,
                                  itemBuilder: (ctx, i) {
                                    final m = _searchResults[i];
                                    final isAdded =
                                        _selectedItems.containsKey(m.id);
                                    return ListTile(
                                      leading:
                                          const Icon(Icons.vaccines, size: 20),
                                      title: Text(m.name),
                                      subtitle: Text(m.barcode),
                                      trailing: isAdded
                                          ? const Icon(Icons.check_circle,
                                              color: AppTheme.success)
                                          : IconButton(
                                              icon: const Icon(
                                                  Icons.add_circle_outline),
                                              onPressed: () {
                                                setState(() =>
                                                    _selectedItems[m.id] = 1);
                                              },
                                            ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 40),
                  // Right Side: Quantities & Summary
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selected Items (${_selectedItems.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 24),
                        Expanded(
                          child: _selectedItems.isEmpty
                              ? Center(
                                  child: Text(
                                    'Add medicines from the left to start',
                                    style: TextStyle(
                                        color: context.textMutedColor),
                                  ),
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
                                          SizedBox(
                                            width: 100,
                                            child: TextField(
                                              keyboardType:
                                                  TextInputType.number,
                                              textAlign: TextAlign.center,
                                              decoration: InputDecoration(
                                                isDense: true,
                                                contentPadding:
                                                    const EdgeInsets.all(8),
                                                suffixText: m.unit,
                                                border:
                                                    const OutlineInputBorder(),
                                              ),
                                              onChanged: (v) {
                                                final qty =
                                                    int.tryParse(v) ?? 0;
                                                _selectedItems[id] = qty;
                                              },
                                              controller: TextEditingController(
                                                  text:
                                                      '${_selectedItems[id]}'),
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _batchNoCtrl,
                    decoration: InputDecoration(
                      labelText: 'Batch Number',
                      prefixIcon: const Icon(Icons.layers),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: _pickExpiry,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Expiry Date',
                        prefixIcon: const Icon(Icons.event),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        '${_expiryDate.day}/${_expiryDate.month}/${_expiryDate.year}',
                      ),
                    ),
                  ),
                ),
              ],
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
                  inv.addBatchStock(
                    _selectedItems, // mainUpdates
                    note: _noteCtrl.text,
                    supplier: _supplierCtrl.text,
                    batchNo: _batchNoCtrl.text.trim(),
                    expiryDate: _expiryDate,
                  );
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

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }
}

class _PurchaseHistoryTab extends StatelessWidget {
  const _PurchaseHistoryTab();

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final history = inv.purchaseHistory;

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
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  Text('${history.length} records found',
                      style: TextStyle(color: context.textMutedColor)),
                ],
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
                      Icon(Icons.inventory_2_outlined,
                          size: 64, color: context.textMutedColor),
                      const SizedBox(height: 24),
                      Text('No purchase records yet',
                          style: TextStyle(
                              color: context.textMutedColor, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final p = history[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: BorderSide(
                            color: context.borderColor.withValues(alpha: 0.5)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.shopping_bag,
                              color: AppTheme.primary),
                        ),
                        title: Row(
                          children: [
                            Text(p.medicineName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 16)),
                            const Spacer(),
                            Text(
                              '+${p.qty} Units',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.success),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => showDialog(
                                context: context,
                                builder: (ctx) =>
                                    _EditPurchaseDialog(purchase: p),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: AppTheme.danger, size: 20),
                              onPressed: () =>
                                  _showDeleteConfirm(context, inv, p),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (p.supplier.isNotEmpty) ...[
                                    Icon(Icons.business,
                                        size: 14,
                                        color: context.textMutedColor),
                                    const SizedBox(width: 4),
                                    Text(p.supplier,
                                        style: TextStyle(
                                            color: context.textColor,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 16),
                                  ],
                                  Icon(Icons.calendar_today,
                                      size: 14, color: context.textMutedColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${p.purchasedAt.day}/${p.purchasedAt.month}/${p.purchasedAt.year}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: context.textMutedColor),
                                  ),
                                ],
                              ),
                              if (p.note.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(p.note,
                                    style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: context.textMutedColor,
                                        fontSize: 13)),
                              ],
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
  String _fromLoc = 'main'; // 'main' or 'store'
  String _toLoc = 'store'; // 'store' or 'main'

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final syncService = context.read<SyncService>();

    // Get all medicines that have stock in the source location
    final eligibleMeds = inv.rawMedicines.where((m) {
      final stock = _fromLoc == 'main' ? m.mainStock : m.storeStock;
      return stock > 0;
    }).toList();

    // Filter by search query
    final filtered = eligibleMeds.where((m) =>
        m.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        m.barcode.contains(_searchQuery)).toList();

    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.1),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Row(
          children: [
            const Icon(Icons.swap_horiz, color: AppTheme.success),
            const SizedBox(width: 12),
            Text(_fromLoc == 'main'
                ? 'Bulk Clinic to Store Transfer'
                : 'Bulk Store to Clinic Transfer'),
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
        height: 600,
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
            : Column(
                children: [
                  // Direction selector
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment<String>(
                          value: 'main_to_store',
                          label: Text('Clinic Stock → Store Stock'),
                          icon: Icon(Icons.arrow_forward_rounded),
                        ),
                        ButtonSegment<String>(
                          value: 'store_to_main',
                          label: Text('Store Stock → Clinic Stock'),
                          icon: Icon(Icons.arrow_back_rounded),
                        ),
                      ],
                      selected: <String>{'${_fromLoc}_to_${_toLoc}'},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          final val = newSelection.first;
                          if (val == 'main_to_store') {
                            _fromLoc = 'main';
                            _toLoc = 'store';
                          } else {
                            _fromLoc = 'store';
                            _toLoc = 'main';
                          }
                          _selectedIds.clear();
                          _transferQtys.clear();
                        });
                      },
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: AppTheme.primary,
                        selectedForegroundColor: Colors.white,
                      ),
                    ),
                  ),
                  // Search & Select All row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'Search eligible medicines...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v),
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
                              _transferQtys[m.id] = _fromLoc == 'main' ? m.mainStock : m.storeStock;
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
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              _fromLoc == 'main'
                                  ? 'No medicines with Clinic stock found.'
                                  : 'No medicines with Store stock found.',
                              style: const TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (ctx, idx) {
                              final m = filtered[idx];
                              final isSelected = _selectedIds.contains(m.id);
                              final maxQty = _fromLoc == 'main' ? m.mainStock : m.storeStock;
                              final qty = _transferQtys[m.id] ?? maxQty;

                              return _BulkTransferRow(
                                key: ValueKey('${m.id}_$_fromLoc'),
                                medicine: m,
                                isSelected: isSelected,
                                fromLoc: _fromLoc,
                                initialQty: qty,
                                onSelectedChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedIds.add(m.id);
                                      _transferQtys[m.id] = maxQty;
                                    } else {
                                      _selectedIds.remove(m.id);
                                      _transferQtys.remove(m.id);
                                    }
                                  });
                                },
                                onQtyChanged: (val) {
                                  _transferQtys[m.id] = val;
                                },
                              );
                            },
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
                style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
                icon: const Icon(Icons.send),
                label: Text('Transfer Selected (${_selectedIds.length})'),
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () async {
                        setState(() => _isProcessing = true);
                        int count = 0;
                        for (final id in _selectedIds) {
                          final m = inv.rawMedicines
                              .where((med) => med.id == id)
                              .firstOrNull;
                          final qty = _transferQtys[id] ?? 0;
                          if (m != null && qty > 0) {
                            await widget.wh.transfer(
                              medicine: m,
                              qty: qty,
                              from: _fromLoc,
                              to: _toLoc,
                              note: 'Bulk Transfer',
                              syncService: syncService,
                            );
                            count++;
                          }
                        }
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Successfully transferred stock for $count medicines.'),
                              backgroundColor: AppTheme.success,
                            ),
                          );
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
  final String fromLoc;
  final int initialQty;
  final ValueChanged<bool?> onSelectedChanged;
  final ValueChanged<int> onQtyChanged;

  const _BulkTransferRow({
    super.key,
    required this.medicine,
    required this.isSelected,
    required this.fromLoc,
    required this.initialQty,
    required this.onSelectedChanged,
    required this.onQtyChanged,
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
    final isClinicSource = widget.fromLoc == 'main';
    final maxQty = isClinicSource ? widget.medicine.mainStock : widget.medicine.storeStock;
    final destQty = isClinicSource ? widget.medicine.storeStock : widget.medicine.mainStock;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.isSelected
              ? AppTheme.success
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: CheckboxListTile(
        value: widget.isSelected,
        onChanged: widget.onSelectedChanged,
        title: Text(widget.medicine.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: isClinicSource
            ? Text('Clinic Stock: $maxQty | Store Stock: $destQty')
            : Text('Store Stock: $maxQty | Clinic Stock: $destQty'),
        secondary: widget.isSelected
            ? SizedBox(
                width: 120,
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Qty to Send',
                    isDense: true,
                  ),
                  onChanged: (val) {
                    final parsed = int.tryParse(val) ?? 0;
                    final clamped = parsed.clamp(0, maxQty);
                    widget.onQtyChanged(clamped);
                  },
                ),
              )
            : null,
      ),
    );
  }
}
