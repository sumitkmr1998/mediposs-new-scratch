import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../shared/models/medicine.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../theme/app_theme.dart';

class BulkItem {
  int clinicQty;
  int storeQty;
  int bulkClinicQty;
  int bulkStoreQty;
  String batchNo;
  DateTime expiryDate;
  
  BulkItem({
    this.clinicQty = 0,
    this.storeQty = 0,
    this.bulkClinicQty = 0,
    this.bulkStoreQty = 0,
    this.batchNo = '',
    required this.expiryDate,
  });

  int get totalQty => clinicQty + storeQty + bulkClinicQty + bulkStoreQty;
}

class BulkStockEntryDialog extends StatefulWidget {
  const BulkStockEntryDialog({super.key});

  @override
  State<BulkStockEntryDialog> createState() => BulkStockEntryDialogState();
}

class BulkStockEntryDialogState extends State<BulkStockEntryDialog> {
  final Map<int, BulkItem> _selectedItems = {}; // medicineId -> item
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _supplierCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  int _highlightedIndex = 0;
  List<Medicine> _searchResults = [];
  bool _isSubmitting = false;

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
      _selectedItems[m.id] = BulkItem(
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
