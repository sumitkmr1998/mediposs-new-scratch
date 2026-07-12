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
