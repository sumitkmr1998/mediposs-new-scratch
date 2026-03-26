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
      final inv = context.read<InventoryProvider>();

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
          // Update existing
          final updatedMed = Medicine(
            id: existing.id,
            name: nameCell,
            barcode: barcode.isNotEmpty ? barcode : existing.barcode,
            category: category,
            unit: unit,
            purchasePrice:
                purchasePrice > 0 ? purchasePrice : existing.purchasePrice,
            sellingPrice:
                sellingPrice > 0 ? sellingPrice : existing.sellingPrice,
            mainStock: mainStock > 0 ? mainStock : existing.mainStock,
            storeStock: storeStock > 0 ? storeStock : existing.storeStock,
            lowStockThreshold: lowStock,
            synced: false,
          );
          inv.updateMedicine(updatedMed);
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
            mainStock: mainStock,
            storeStock: storeStock,
            lowStockThreshold: lowStock,
          );
          inv.addMedicine(newMed);
          added++;
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
        title: const Text('Warehouse Control'),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                        'main-empty': 'Main Hub Empty',
                        'expired': 'Expired',
                        'near-expiry': 'Near Expiry',
                      },
                      onChanged: (v) => inv.setFilter(v!),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Medicines Grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 400,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
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
                      label: 'Hub',
                      value: widget.medicine.mainStock,
                      icon: Icons.warehouse,
                      color: const Color(0xFF6366F1),
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
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.medicine.isLowStock)
                    _StatusBadge(
                        label: 'LOW STOCK', color: AppTheme.warning),
                  if (widget.medicine.hasExpiredBatch)
                    _StatusBadge(label: 'EXPIRED', color: AppTheme.danger)
                  else if (widget.medicine.hasNearExpiryBatch)
                    _StatusBadge(label: 'NEAR EXPIRY', color: AppTheme.danger),
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
                          child:
                              Row(children: [Icon(Icons.edit), Text(' Edit Info')])),
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
                            Text(' Return to Hub')
                          ])),
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
  const _BatchDetailsDialog({required this.medicine, required this.wh, required this.canTransfer});

  @override
  Widget build(BuildContext context) {
    final sortedBatches = medicine.batches.toList()
      ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.layers_outlined, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text('Batches: ${medicine.name}')),
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
                                : context.borderColor.withValues(alpha: 0.5)),
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
                                const Text('HUB',
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
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                if (canTransfer) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF14B8A6), // Teal
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _showTransfer(context, medicine, 'main', 'store', wh);
                    },
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('Send to Store'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1), // Indigo
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _showTransfer(context, medicine, 'store', 'main', wh);
                    },
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Return to Hub'),
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
  }

  void _showTransfer(BuildContext context, Medicine m, String from, String to,
      WarehouseProvider wh) {
    showDialog(
      context: context,
      builder: (_) => _TransferDialog(medicine: m, from: from, to: to, wh: wh),
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

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(label.toUpperCase(),
          style: const TextStyle(
              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
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
              _FilterChip(
                label: 'Today',
                isSelected: wh.activeFilter == SalesFilter.today,
                onSelected: () => wh.setFilter(SalesFilter.today),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Yesterday',
                isSelected: wh.activeFilter == SalesFilter.yesterday,
                onSelected: () => wh.setFilter(SalesFilter.yesterday),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Last 7 Days',
                isSelected: wh.activeFilter == SalesFilter.last7Days,
                onSelected: () => wh.setFilter(SalesFilter.last7Days),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'All Time',
                isSelected: wh.activeFilter == SalesFilter.allTime,
                onSelected: () => wh.setFilter(SalesFilter.allTime),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Custom Range',
                isSelected: wh.activeFilter == SalesFilter.custom,
                onSelected: () async {
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
              ),
            ],
          ),
        ),
        Expanded(
          child: wh.transfers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history,
                          size: 48, color: context.textMutedColor),
                      const SizedBox(height: 16),
                      Text('No transfers recorded in this period',
                          style: TextStyle(color: context.textMutedColor)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: wh.transfers.length,
                  itemBuilder: (ctx, i) {
                    final t = wh.transfers[i];
                    final isToStore = t.toWarehouse.toLowerCase() == 'store';
                    final accentColor = isToStore
                        ? const Color(0xFF14B8A6)
                        : const Color(0xFF6366F1);

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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : context.textMutedColor,
          )),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: AppTheme.primary,
      backgroundColor: context.bgColor.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected ? AppTheme.primary : Colors.transparent,
        ),
      ),
      showCheckmark: false,
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

  @override
  Widget build(BuildContext context) {
    final fromLabel = widget.from == 'main' ? 'Main Warehouse' : 'Store Stock';
    final toLabel = widget.to == 'main' ? 'Main Warehouse' : 'Store Stock';
    final available = widget.from == 'main'
        ? widget.medicine.mainStock
        : widget.medicine.storeStock;
    final primaryColor = widget.to == 'store'
        ? const Color(0xFF14B8A6)
        : const Color(0xFF6366F1);

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
            const SizedBox(height: 20),
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
            final err = await widget.wh.transfer(
              medicine: widget.medicine,
              qty: qty,
              from: widget.from,
              to: widget.to,
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
                        const SizedBox(height: 12),
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
                      const SizedBox(height: 16),
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
