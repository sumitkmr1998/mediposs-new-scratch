import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/models/purchase_record.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/sync_service.dart';
import '../../../../theme/app_theme.dart';

class EditPurchaseDialog extends StatefulWidget {
  final PurchaseRecord purchase;
  const EditPurchaseDialog({super.key, required this.purchase});

  @override
  State<EditPurchaseDialog> createState() => EditPurchaseDialogState();
}

class EditPurchaseDialogState extends State<EditPurchaseDialog> {
  late TextEditingController _qtyCtrl;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '${widget.purchase.qty}');
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final loc = widget.purchase.location;
    final locationName = loc == 'store' ? 'Store POS' :
                         loc == 'bulkClinic' ? 'Bulk Clinic' :
                         loc == 'bulkStore' ? 'Bulk Store' :
                         loc == 'clinic' ? 'Clinic Dispense' : 'Hub/Clinic';
    return AlertDialog(
      title: Text('Edit Purchase: ${widget.purchase.medicineName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
              'Updating the quantity will automatically adjust the $locationName stock level by the difference.'),
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
              final actor = context.read<AuthProvider>().currentUser;
              inv.updatePurchase(widget.purchase, qty,
                  syncService: context.read<SyncService>(), actor: actor);
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
