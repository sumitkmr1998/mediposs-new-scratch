import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/models/medicine.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/providers/warehouse_provider.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/sales_provider.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/medicine_dialog.dart';
import '../../../../shared/utils/analytics_helper.dart';
import '../../../../shared/widgets/app_status_badge.dart';
import '../dialogs/batch_details_dialog.dart';
import '../dialogs/transfer_dialog.dart';

class ModernMedicineCardWindows extends StatefulWidget {
  final Medicine medicine;
  final WarehouseProvider wh;
  final AuthProvider auth;
  final InventoryProvider inv;
  final bool isSelected;
  final ValueChanged<bool?>? onSelect;

  const ModernMedicineCardWindows({
    super.key,
    required this.medicine,
    required this.wh,
    required this.auth,
    required this.inv,
    this.isSelected = false,
    this.onSelect,
  });

  @override
  State<ModernMedicineCardWindows> createState() =>
      ModernMedicineCardWindowsState();
}

class ModernMedicineCardWindowsState
    extends State<ModernMedicineCardWindows> {
  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesProvider>().rawSales;
    final velocity = AnalyticsHelper.dailyConsumptionRate(widget.medicine.id, sales, trendDays: 30);
    final daysLeft = AnalyticsHelper.daysOfStockRemaining(widget.medicine, sales, trendDays: 30);
    final isSmartLow = widget.inv.isSmartLowStock(widget.medicine, sales);

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
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: MetricBlock(
                          label: 'Store Bulk',
                          value: widget.medicine.bulkStoreStock,
                          icon: Icons.warehouse_outlined,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(width: 58),
                      Expanded(
                        child: MetricBlock(
                          label: 'Clinic Bulk',
                          value: widget.medicine.bulkClinicStock,
                          icon: Icons.warehouse,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Center(
                            child: Tooltip(
                              message: 'Transfer Store Bulk to POS',
                              child: InkWell(
                                onTap: () => _showTransferDialog(
                                    context,
                                    widget.medicine,
                                    'bulkStore',
                                    'store',
                                    widget.wh),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF14B8A6)
                                        .withValues(alpha: 0.1),
                                  ),
                                  child: const Icon(Icons.arrow_downward_rounded,
                                      size: 16, color: Color(0xFF14B8A6)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 58),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Center(
                            child: Tooltip(
                              message: 'Transfer Clinic Bulk to Dispensing',
                              child: InkWell(
                                onTap: () => _showTransferDialog(
                                    context,
                                    widget.medicine,
                                    'bulkClinic',
                                    'clinic',
                                    widget.wh),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppTheme.indigo.withValues(alpha: 0.1),
                                  ),
                                  child: const Icon(Icons.arrow_downward_rounded,
                                      size: 16, color: AppTheme.indigo),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: MetricBlock(
                          label: 'Store',
                          value: widget.medicine.storeStock,
                          icon: Icons.storefront,
                          color: const Color(0xFF14B8A6),
                          isWarning: isSmartLow,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Tooltip(
                            message: 'Transfer Store to Clinic',
                            child: InkWell(
                              onTap: () => _showTransferDialog(
                                  context,
                                  widget.medicine,
                                  'store',
                                  'clinic',
                                  widget.wh),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 42,
                                height: 28,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: const Color(0xFF14B8A6)
                                      .withValues(alpha: 0.1),
                                ),
                                child: const Icon(Icons.arrow_forward_rounded,
                                    size: 16, color: Color(0xFF14B8A6)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Tooltip(
                            message: 'Transfer Clinic to Store',
                            child: InkWell(
                              onTap: () => _showTransferDialog(
                                  context,
                                  widget.medicine,
                                  'clinic',
                                  'store',
                                  widget.wh),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 42,
                                height: 28,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: AppTheme.indigo.withValues(alpha: 0.1),
                                ),
                                child: const Icon(Icons.arrow_back_rounded,
                                    size: 16, color: AppTheme.indigo),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MetricBlock(
                          label: 'Clinic',
                          value: widget.medicine.mainStock,
                          icon: Icons.medical_services,
                          color: AppTheme.indigo,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.medicine.totalStock <= 0)
                    AppStatusBadge(
                        label: 'OUT OF STOCK',
                        color: AppTheme.danger,
                        style: AppStatusBadgeStyle.text)
                  else if (velocity > 0 && daysLeft < 7)
                    AppStatusBadge(
                        label: 'CRITICAL: <7 DAYS',
                        color: AppTheme.danger,
                        style: AppStatusBadgeStyle.text)
                  else if (velocity > 0 && daysLeft < 15)
                    AppStatusBadge(
                        label: 'URGENT: ${daysLeft.toStringAsFixed(0)} DAYS',
                        color: AppTheme.orange,
                        style: AppStatusBadgeStyle.text)
                  else if (velocity > 0 && daysLeft < 30)
                    AppStatusBadge(
                        label: 'DEPLETING: ${daysLeft.toStringAsFixed(0)} DAYS',
                        color: AppTheme.warning,
                        style: AppStatusBadgeStyle.text)
                  else if (isSmartLow)
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
                      } else if (val == 'transfer') {
                        _showTransferDialog(context, widget.medicine,
                            'bulkClinic', 'clinic', widget.wh);
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
                          value: 'transfer',
                          child: Row(children: [
                            Icon(Icons.swap_horiz),
                            Text(' Transfer Stock')
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
      builder: (_) => BatchDetailsDialog(
          medicine: m,
          wh: widget.wh,
          canTransfer: context.read<AuthProvider>().hasWarehouseWriteAccess),
    );
  }

  void _showTransferDialog(BuildContext context, Medicine m, String from,
      String to, WarehouseProvider wh) {
    showDialog(
      context: context,
      builder: (_) => TransferDialog(medicine: m, from: from, to: to, wh: wh),
    );
  }
}

class MetricBlock extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final bool isWarning;

  const MetricBlock({
    super.key,
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
