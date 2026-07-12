import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/models/medicine.dart';
import '../../../../shared/providers/warehouse_provider.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/sync_service.dart';
import '../../../../theme/app_theme.dart';

class TransferDialog extends StatefulWidget {
  final Medicine medicine;
  final String from;
  final String to;
  final WarehouseProvider wh;

  const TransferDialog({
    super.key,
    required this.medicine,
    required this.from,
    required this.to,
    required this.wh,
  });

  @override
  State<TransferDialog> createState() => TransferDialogState();
}

class TransferDialogState extends State<TransferDialog> {
  final _qtyCtrl = TextEditingController(text: '1');
  final _noteCtrl = TextEditingController();
  MedicineBatch? _selectedBatch;
  late String _fromLoc;
  late String _toLoc;
  bool _isSubmitting = false;

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
          onPressed: _isSubmitting ? null : () async {
            setState(() => _isSubmitting = true);
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
              setState(() => _isSubmitting = false);
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
              setState(() => _isSubmitting = false);
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
