import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../shared/models/medicine.dart';
import '../pdf_purchase_import_dialog.dart';

class _BulkItem {
  final Medicine medicine;
  int clinicQty;
  int storeQty;
  int bulkClinicQty;
  int bulkStoreQty;
  String batchNo;
  DateTime expiryDate;
  
  _BulkItem({
    required this.medicine,
    this.clinicQty = 0,
    this.storeQty = 0,
    this.bulkClinicQty = 0,
    this.bulkStoreQty = 0,
    this.batchNo = '',
    required this.expiryDate,
  });

  int get totalQty => clinicQty + storeQty + bulkClinicQty + bulkStoreQty;
}

class AndroidBulkPurchaseDialog extends StatefulWidget {
  final Medicine? initialMedicine;
  const AndroidBulkPurchaseDialog({super.key, this.initialMedicine});

  static void show(BuildContext context, {Medicine? initialMedicine}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AndroidBulkPurchaseDialog(initialMedicine: initialMedicine),
    );
  }

  @override
  State<AndroidBulkPurchaseDialog> createState() => _AndroidBulkPurchaseDialogState();
}

class _AndroidBulkPurchaseDialogState extends State<AndroidBulkPurchaseDialog> {
  final Map<int, _BulkItem> _selectedItems = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialMedicine != null) {
      final m = widget.initialMedicine!;
      final activeBatch = m.batches.isNotEmpty ? m.batches.last : null;
      _selectedItems[m.id] = _BulkItem(
        medicine: m,
        bulkClinicQty: 1,
        batchNo: activeBatch?.batchNo ?? '',
        expiryDate: activeBatch?.expiryDate ?? DateTime.now().add(const Duration(days: 365)),
      );
    }
  }
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _supplierCtrl = TextEditingController();
  List<Medicine> _searchResults = [];
  bool _isSubmitting = false;

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

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2, color: AppTheme.primary),
                  const SizedBox(width: 12),
                  const Text('Bulk Purchase Receipt', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      PdfPurchaseImportDialog.show(context);
                    },
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: AppTheme.primary),
                    label: const Text('UPLOAD PDF', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(),
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (q) => _onSearch(q, inv.medicines),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search medicine to add...',
                  filled: true,
                  fillColor: context.bgColor.withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            // Search Results (only show if typing)
            if (_searchCtrl.text.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: context.bgColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.borderColor),
                ),
                child: _searchResults.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('No medicines found')))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        itemBuilder: (ctx, i) {
                          final m = _searchResults[i];
                          final isAdded = _selectedItems.containsKey(m.id);
                          return ListTile(
                            leading: const Icon(Icons.vaccines, size: 20),
                            title: Text(m.name),
                            subtitle: Text(m.barcode),
                            trailing: isAdded
                                ? const Icon(Icons.check_circle, color: AppTheme.success)
                                : IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: () {
                                      setState(() {
                                        final activeBatch = m.batches.isNotEmpty ? m.batches.last : null;
                                        _selectedItems[m.id] = _BulkItem(
                                          medicine: m,
                                          bulkClinicQty: 1,
                                          batchNo: activeBatch?.batchNo ?? '',
                                          expiryDate: activeBatch?.expiryDate ?? DateTime.now().add(const Duration(days: 365)),
                                        );
                                        _searchCtrl.clear();
                                        _searchResults.clear();
                                      });
                                    },
                                  ),
                          );
                        },
                      ),
              ),
            
            // Selected Items List
            Expanded(
              child: _selectedItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 64, color: context.textMutedColor),
                          const SizedBox(height: 16),
                          Text('Search and add medicines above', style: TextStyle(color: context.textMutedColor)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      itemCount: _selectedItems.length,
                      itemBuilder: (ctx, i) {
                        final id = _selectedItems.keys.elementAt(i);
                        final item = _selectedItems[id]!;
                        final m = item.medicine;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: context.borderColor)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                          Text('Current Hub Stock: ${m.mainStock}', style: TextStyle(color: context.textMutedColor, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                                      onPressed: () => setState(() => _selectedItems.remove(id)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        decoration: InputDecoration(
                                          labelText: 'Batch No',
                                          isDense: true,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        onChanged: (v) => item.batchNo = v,
                                        controller: TextEditingController(text: item.batchNo),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () async {
                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate: item.expiryDate,
                                            firstDate: DateTime.now(),
                                            lastDate: DateTime.now().add(const Duration(days: 3650)),
                                          );
                                          if (picked != null) {
                                            setState(() => item.expiryDate = picked);
                                          }
                                        },
                                        child: InputDecorator(
                                          decoration: InputDecoration(
                                            labelText: 'Expiry Date',
                                            isDense: true,
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          child: Text('${item.expiryDate.day}/${item.expiryDate.month}/${item.expiryDate.year}'),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(child: _buildQtyField('Store Qty', item.storeQty, (v) => item.storeQty = v)),
                                    const SizedBox(width: 8),
                                    Expanded(child: _buildQtyField('Clinic Qty', item.clinicQty, (v) => item.clinicQty = v)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(child: _buildQtyField('Bulk Store', item.bulkStoreQty, (v) => item.bulkStoreQty = v)),
                                    const SizedBox(width: 8),
                                    Expanded(child: _buildQtyField('Bulk Clinic', item.bulkClinicQty, (v) => item.bulkClinicQty = v)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            
            // Footer (Supplier, Dest, Notes)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _supplierCtrl,
                          decoration: InputDecoration(
                            labelText: 'Supplier',
                            prefixIcon: const Icon(Icons.business),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'Order Notes',
                      prefixIcon: const Icon(Icons.note),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _selectedItems.isEmpty || _isSubmitting
                          ? null
                          : () {
                              setState(() => _isSubmitting = true);
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
                                content: Text('Bulk purchase recorded!'),
                                backgroundColor: AppTheme.success,
                                behavior: SnackBarBehavior.floating,
                              ));
                            },
                      icon: const Icon(Icons.check_circle),
                      label: const Text('CONFIRM PURCHASE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQtyField(String label, int val, Function(int) onChanged) {
    return TextField(
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
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
