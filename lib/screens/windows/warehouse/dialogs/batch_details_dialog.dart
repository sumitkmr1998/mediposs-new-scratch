import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/models/medicine.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/providers/warehouse_provider.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/sync_service.dart';
import '../../../../theme/app_theme.dart';
import 'edit_batch_dialog.dart';
import 'transfer_dialog.dart';

class BatchDetailsDialog extends StatelessWidget {
  final Medicine medicine;
  final WarehouseProvider wh;
  final bool canTransfer;
  const BatchDetailsDialog(
      {super.key, required this.medicine, required this.wh, required this.canTransfer});

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, inv, _) {
        // Refetch medicine to get latest batches
        final m = inv.medicines.where((m) => m.id == medicine.id).firstOrNull ??
            medicine;
        final sortedBatches = m.batches.toList()
          ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

        final auth = context.read<AuthProvider>();
        final user = auth.currentUser;
        final isAdmin = user?.role.toLowerCase() == 'admin';
        final canAddBatch = isAdmin || user?.canAddStock == true || user?.canEditInventory == true;
        final canEditBatch = isAdmin || user?.canOverrideStock == true || user?.canEditInventory == true;
        final canViewCost = isAdmin || user?.canViewPurchasePrice == true;

        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.layers_outlined, color: AppTheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Text('Batches: ${m.name}')),
              if (canAddBatch)
                IconButton(
                  tooltip: 'Add New Batch',
                  icon: const Icon(Icons.add_circle_outline,
                      color: AppTheme.primary),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => EditBatchDialog(
                        medicine: m,
                        batch: null,
                      ),
                    );
                  },
                ),
            ],
          ),
          content: SizedBox(
            width: 650,
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
                        final effectiveSellPrice = b.sellingPrice > 0 ? b.sellingPrice : m.sellingPrice;
                        final effectiveCostPrice = b.purchasePrice > 0 ? b.purchasePrice : m.purchasePrice;

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
                                      'Exp: ${b.expiryDate.day.toString().padLeft(2, '0')}/${b.expiryDate.month.toString().padLeft(2, '0')}/${b.expiryDate.year}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: isExpired
                                              ? AppTheme.danger
                                              : context.textMutedColor),
                                    ),
                                    const SizedBox(height: 2),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        Text(
                                          'MRP: ₹${effectiveSellPrice.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.primaryLight,
                                          ),
                                        ),
                                        if (canViewCost)
                                          Text(
                                            'Cost: ₹${effectiveCostPrice.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: context.textMutedColor,
                                            ),
                                          ),
                                      ],
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
                              if (canEditBatch) ...[
                                IconButton(
                                  tooltip: 'Edit Batch',
                                  icon:
                                      const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => EditBatchDialog(
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
                                                final actor = context.read<AuthProvider>().currentUser;
                                                inv.deleteBatch(m, b,
                                                    syncService: sync,
                                                    actor: actor);
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
      builder: (_) => TransferDialog(medicine: m, from: from, to: to, wh: wh),
    );
  }
}
