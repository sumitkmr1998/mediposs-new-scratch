import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/warehouse_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/models/medicine.dart';
import '../../shared/services/sync_service.dart';
import '../../theme/app_theme.dart';

class _BulkTransferItem {
  int qty;
  MedicineBatch? selectedBatch;
  String note;
  
  _BulkTransferItem({
    this.qty = 1,
    this.selectedBatch,
    this.note = '',
  });
}

class AndroidBulkTransferDialog extends StatefulWidget {
  const AndroidBulkTransferDialog({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const AndroidBulkTransferDialog(),
    );
  }

  @override
  State<AndroidBulkTransferDialog> createState() => _AndroidBulkTransferDialogState();
}

class _AndroidBulkTransferDialogState extends State<AndroidBulkTransferDialog> {
  final Map<int, _BulkTransferItem> _selectedItems = {};
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  List<Medicine> _searchResults = [];
  bool _isSubmitting = false;

  String _fromLoc = 'bulkClinic';
  String _toLoc = 'clinic';

  int _getStock(MedicineBatch b, String loc) {
    if (loc == 'main' || loc == 'clinic') return b.mainStock;
    if (loc == 'store') return b.storeStock;
    if (loc == 'bulkClinic') return b.bulkClinicStock;
    if (loc == 'bulkStore') return b.bulkStoreStock;
    return 0;
  }

  void _onSearch(String q, List<Medicine> all) {
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() {
      _searchResults = all.where((m) {
        // Only allow medicines that have stock in the source location
        final hasStock = m.batches.any((b) => _getStock(b, _fromLoc) > 0);
        return hasStock && (m.name.toLowerCase().contains(q.toLowerCase()) || m.barcode.contains(q));
      }).toList();
    });
  }

  void _selectMedicine(Medicine m) {
    setState(() {
      final availableBatches = m.batches.where((b) => _getStock(b, _fromLoc) > 0).toList();
      MedicineBatch? batch;
      if (availableBatches.isNotEmpty) {
        availableBatches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
        batch = availableBatches.first;
      }
      
      _selectedItems[m.id] = _BulkTransferItem(
        qty: 1,
        selectedBatch: batch,
      );
      _searchCtrl.clear();
      _searchResults.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final wh = context.read<WarehouseProvider>();

    final locations = const {
      'bulkClinic': 'Clinic Bulk',
      'clinic': 'Clinic',
      'bulkStore': 'Store Bulk',
      'store': 'Store',
    };

    final isToStore = _toLoc == 'store' || _toLoc == 'bulkStore';
    final accentColor = isToStore ? const Color(0xFF14B8A6) : AppTheme.indigo;

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
                  Icon(Icons.swap_horiz, color: accentColor),
                  const SizedBox(width: 12),
                  const Text('Bulk Stock Transfer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(),
            
            // From/To Selection Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _fromLoc,
                      decoration: const InputDecoration(labelText: 'From Location', isDense: true, border: OutlineInputBorder()),
                      items: locations.entries.map((e) {
                        return DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _fromLoc = val;
                            _selectedItems.clear();
                            _searchCtrl.clear();
                            _searchResults.clear();
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _toLoc,
                      decoration: const InputDecoration(labelText: 'To Location', isDense: true, border: OutlineInputBorder()),
                      items: locations.entries.map((e) {
                        return DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _toLoc = val;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (q) => _onSearch(q, inv.medicines),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search stock to transfer...',
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
                    ? const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('No medicines with stock found')))
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
                                    onPressed: () => _selectMedicine(m),
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
                          Icon(Icons.swap_horiz_outlined, size: 64, color: context.textMutedColor),
                          const SizedBox(height: 16),
                          Text('Search and add stock above', style: TextStyle(color: context.textMutedColor)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      itemCount: _selectedItems.length,
                      itemBuilder: (ctx, i) {
                        final id = _selectedItems.keys.elementAt(i);
                        final m = inv.medicines.firstWhere((e) => e.id == id);
                        final item = _selectedItems[id]!;
                        final availableBatches = m.batches.where((b) => _getStock(b, _fromLoc) > 0).toList();
                        
                        final maxQty = item.selectedBatch != null
                            ? _getStock(item.selectedBatch!, _fromLoc)
                            : 0;

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
                                          Text('Max Available: $maxQty', style: TextStyle(color: context.textMutedColor, fontSize: 12)),
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
                                if (availableBatches.isNotEmpty) ...[
                                  DropdownButtonFormField<MedicineBatch>(
                                    value: item.selectedBatch,
                                    decoration: const InputDecoration(labelText: 'Select Batch', isDense: true, border: OutlineInputBorder()),
                                    style: const TextStyle(fontSize: 12, color: Colors.black),
                                    items: availableBatches.map((b) {
                                      final qty = _getStock(b, _fromLoc);
                                      return DropdownMenuItem(value: b, child: Text('${b.batchNo} (Qty: $qty)'));
                                    }).toList(),
                                    onChanged: (b) {
                                      setState(() {
                                        item.selectedBatch = b;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          labelText: 'Qty to Transfer',
                                          isDense: true,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        initialValue: '${item.qty}',
                                        onChanged: (v) {
                                          final q = int.tryParse(v) ?? 1;
                                          item.qty = q;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        decoration: InputDecoration(
                                          labelText: 'Audit Note',
                                          isDense: true,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        initialValue: item.note,
                                        onChanged: (v) => item.note = v,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            
            // Footer
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'Global Transfer Notes (Optional)',
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
                          : () async {
                              setState(() => _isSubmitting = true);
                              final actor = context.read<AuthProvider>().currentUser;
                              final sync = context.read<SyncService>();
                              
                              int successCount = 0;
                              final errors = <String>[];
                              
                              for (final entry in _selectedItems.entries) {
                                final mId = entry.key;
                                final item = entry.value;
                                final m = inv.medicines.firstWhere((e) => e.id == mId);
                                if (item.qty <= 0) continue;
                                
                                final maxAvail = item.selectedBatch != null
                                    ? _getStock(item.selectedBatch!, _fromLoc)
                                    : 0;
                                
                                if (item.qty > maxAvail) {
                                  errors.add('${m.name}: Insufficient stock in selected batch (Available: $maxAvail)');
                                  continue;
                                }
                                
                                final err = await wh.transfer(
                                  medicine: m,
                                  qty: item.qty,
                                  from: _fromLoc,
                                  to: _toLoc,
                                  batchNo: item.selectedBatch?.batchNo,
                                  expiryDate: item.selectedBatch?.expiryDate,
                                  note: item.note.isNotEmpty ? item.note : (_noteCtrl.text.isNotEmpty ? _noteCtrl.text : 'Bulk Transfer'),
                                  syncService: sync,
                                  actor: actor,
                                );
                                
                                if (err == null) {
                                  successCount++;
                                } else {
                                  errors.add('${m.name}: $err');
                                }
                              }
                              
                              if (mounted) {
                                setState(() => _isSubmitting = false);
                                Navigator.pop(context);
                                
                                if (errors.isNotEmpty) {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Bulk Transfer Results'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Successfully transferred $successCount items.', style: const TextStyle(fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 12),
                                          const Text('Errors encountered:', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 8),
                                          ...errors.map((e) => Text('• $e', style: const TextStyle(fontSize: 12))),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                                      ],
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text('Successfully executed bulk transfer for $successCount items!'),
                                    backgroundColor: AppTheme.success,
                                    behavior: SnackBarBehavior.floating,
                                  ));
                                }
                              }
                            },
                      icon: const Icon(Icons.check_circle),
                      label: const Text('CONFIRM TRANSFER', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                      style: FilledButton.styleFrom(
                        backgroundColor: accentColor,
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
}
