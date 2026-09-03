import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/models/medicine.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/sync_service.dart';
import '../../../../theme/app_theme.dart';

class EditBatchDialog extends StatefulWidget {
  final Medicine medicine;
  final MedicineBatch? batch;
  const EditBatchDialog({super.key, required this.medicine, this.batch});

  @override
  State<EditBatchDialog> createState() => EditBatchDialogState();
}

class EditBatchDialogState extends State<EditBatchDialog> {
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
  late final _sellingPriceCtrl = TextEditingController(
      text: widget.batch != null && widget.batch!.sellingPrice > 0
          ? widget.batch!.sellingPrice.toStringAsFixed(2)
          : widget.medicine.sellingPrice.toStringAsFixed(2));
  late final _purchasePriceCtrl = TextEditingController(
      text: widget.batch != null && widget.batch!.purchasePrice > 0
          ? widget.batch!.purchasePrice.toStringAsFixed(2)
          : widget.medicine.purchasePrice.toStringAsFixed(2));
  late DateTime _expiryDate =
      widget.batch?.expiryDate ?? DateTime.now().add(const Duration(days: 365));

  @override
  void dispose() {
    _batchNoCtrl.dispose();
    _hubStockCtrl.dispose();
    _storeStockCtrl.dispose();
    _bulkClinicCtrl.dispose();
    _bulkStoreCtrl.dispose();
    _sellingPriceCtrl.dispose();
    _purchasePriceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final isAdmin = user?.role.toLowerCase() == 'admin';

    // Permissions:
    // Can modify stock quantities: requires canOverrideStock or Admin (or adding a new batch if user has canAddStock)
    final canOverrideStock = isAdmin || (user?.canOverrideStock == true);
    final isNewBatch = widget.batch == null;
    final canEditStockCounts = isNewBatch ? (canOverrideStock || (user?.canAddStock == true) || (user?.canEditInventory == true)) : canOverrideStock;

    // Can modify metadata / prices: requires canEditInventory or Admin
    final canEditPricing = isAdmin || (user?.canEditInventory == true);
    final canViewPurchasePrice = isAdmin || (user?.canViewPurchasePrice == true);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isNewBatch ? Icons.add_circle_outline : Icons.edit_note,
            color: AppTheme.primary,
          ),
          const SizedBox(width: 8),
          Text(isNewBatch ? 'Add New Batch' : 'Edit Batch Details'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _batchNoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Batch Number *',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Expiry Date',
                    isDense: true,
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(
                      '${_expiryDate.day.toString().padLeft(2, '0')}/${_expiryDate.month.toString().padLeft(2, '0')}/${_expiryDate.year}'),
                ),
              ),
              const SizedBox(height: 16),

              // Pricing Section
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _sellingPriceCtrl,
                      readOnly: !canEditPricing,
                      decoration: InputDecoration(
                        labelText: 'Batch Selling Price (₹)',
                        isDense: true,
                        prefixIcon: const Icon(Icons.currency_rupee, size: 16),
                        helperText: canEditPricing ? 'Per-unit MRP / rate' : 'Read-only',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  if (canViewPurchasePrice) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _purchasePriceCtrl,
                        readOnly: !canEditPricing,
                        decoration: InputDecoration(
                          labelText: 'Batch Purchase Price (₹)',
                          isDense: true,
                          prefixIcon: const Icon(Icons.currency_rupee, size: 16),
                          helperText: canEditPricing ? 'Cost from supplier' : 'Read-only',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // Stock Quantities Section Header
              Row(
                children: [
                  const Text(
                    'STOCK QUANTITIES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Colors.grey,
                    ),
                  ),
                  const Spacer(),
                  if (!canEditStockCounts)
                    const Tooltip(
                      message: 'Requires "Stock Corrections" permission to modify existing quantities',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline, size: 14, color: AppTheme.warning),
                          SizedBox(width: 4),
                          Text(
                            'Locked (No Permission)',
                            style: TextStyle(fontSize: 11, color: AppTheme.warning, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _bulkStoreCtrl,
                      readOnly: !canEditStockCounts,
                      decoration: InputDecoration(
                        labelText: 'Store Bulk',
                        isDense: true,
                        filled: !canEditStockCounts,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _bulkClinicCtrl,
                      readOnly: !canEditStockCounts,
                      decoration: InputDecoration(
                        labelText: 'Clinic Bulk',
                        isDense: true,
                        filled: !canEditStockCounts,
                      ),
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
                      readOnly: !canEditStockCounts,
                      decoration: InputDecoration(
                        labelText: 'Store (POS)',
                        isDense: true,
                        filled: !canEditStockCounts,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hubStockCtrl,
                      readOnly: !canEditStockCounts,
                      decoration: InputDecoration(
                        labelText: 'Clinic (OPD)',
                        isDense: true,
                        filled: !canEditStockCounts,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.batch != null &&
            (isAdmin || user?.canDeleteInventory == true))
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
              final actor = context.read<AuthProvider>().currentUser;
              inv.deleteBatch(widget.medicine, widget.batch!,
                  syncService: sync, actor: actor);
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
    final sellingPrice = double.tryParse(_sellingPriceCtrl.text.trim()) ?? 0.0;
    final purchasePrice = double.tryParse(_purchasePriceCtrl.text.trim()) ?? 0.0;

    final actor = context.read<AuthProvider>().currentUser;
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
        sellingPrice: sellingPrice,
        purchasePrice: purchasePrice,
        syncService: sync,
        actor: actor,
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
        sellingPrice: sellingPrice,
        purchasePrice: purchasePrice,
        syncService: sync,
        actor: actor,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New batch added successfully')),
      );
    }

    Navigator.pop(context);
  }
}
