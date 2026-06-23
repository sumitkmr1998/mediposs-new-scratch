import 'dart:convert';
import 'dart:io';
import '../shared/services/sync_queue_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../shared/models/sale.dart';
import '../shared/providers/inventory_provider.dart';
import '../shared/providers/sales_provider.dart';
import '../shared/services/objectbox_service.dart';
import '../shared/services/time_service.dart';
import '../theme/app_theme.dart';

class ReturnDialog extends StatefulWidget {
  final Sale originalSale;

  const ReturnDialog({super.key, required this.originalSale});

  @override
  State<ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends State<ReturnDialog> {
  late final List<SaleItem> _items;
  late final Map<int, int> _returnQuantities;

  @override
  void initState() {
    super.initState();
    // Load SaleItems from JSON
    _items = context.read<SalesProvider>().getSaleItems(widget.originalSale);
    // Initialize return quantities to 0
    _returnQuantities = {for (var i in _items) i.medicineId: 0};
  }

  double get _returnTotal {
    double total = 0;
    for (final item in _items) {
      total += (item.unitPrice * _returnQuantities[item.medicineId]!);
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Process Return - ${widget.originalSale.invoiceNo}'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Select quantities to return:',
              style: TextStyle(color: context.textMutedColor),
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics:
                  const NeverScrollableScrollPhysics(), // Since it's inside a dialog that might be unconstrained
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final item = _items[i];
                final currentQ = _returnQuantities[item.medicineId]!;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.medicineName),
                  subtitle: Text(
                      'Sold: ${item.qty} @ ₹${item.unitPrice.toStringAsFixed(2)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: currentQ > 0
                            ? () => setState(() =>
                                _returnQuantities[item.medicineId] =
                                    currentQ - 1)
                            : null,
                      ),
                      Text('$currentQ',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: currentQ < item.qty
                            ? () => setState(() =>
                                _returnQuantities[item.medicineId] =
                                    currentQ + 1)
                            : null,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Refund Amount:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: AppTheme.danger)),
                  Text('-₹${_returnTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppTheme.danger)),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
          onPressed: _returnTotal > 0 ? _processReturn : null,
          child: const Text('Confirm Return',
              style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Future<void> _processReturn() async {
    final invProvider = context.read<InventoryProvider>();
    final salesProvider = context.read<SalesProvider>();
    final db = ObjectBoxService.instance;

    // Filter items being returned
    final returnedItems = <SaleItem>[];
    for (final item in _items) {
      final q = _returnQuantities[item.medicineId]!;
      if (q > 0) {
        returnedItems.add(SaleItem(
          medicineId: item.medicineId,
          medicineName: item.medicineName,
          qty: -q, // Negative for return
          unitPrice: item.unitPrice,
          batchNo: item.batchNo,
          expiryDate: item.expiryDate,
        ));

        // Restock inventory directly
        if (widget.originalSale.isClinicalDispense) {
          invProvider.deductClinicStock(item.medicineId, -q);
        } else {
          invProvider.deductStoreStock(item.medicineId, -q);
        }
      }
    }

    if (returnedItems.isEmpty) return;

    // Generate Return Sale Record
    final now = await TimeService.getRobustTime();
    final count = db.saleBox.count();
    final invoiceNo =
        'RET-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(count + 1).toString().padLeft(4, '0')}';

    final returnSale = Sale(
      invoiceNo: invoiceNo,
      patientName: widget.originalSale.patientName,
      patientPhone: widget.originalSale.patientPhone,
      subtotal: -_returnTotal,
      discount: 0,
      taxRate: 0,
      taxAmount: 0,
      total: -_returnTotal,
      paymentMethod: widget.originalSale.paymentMethod,
      isReturn: true, // Mark as return
      isClinicalDispense: widget.originalSale.isClinicalDispense,
      itemsJson: "[]", // Encode list below
      createdAt: now,
    );

    returnSale.itemsJson = jsonEncode(returnedItems.map((i) => i.toJson()).toList());

    db.saleBox.put(returnSale);
    salesProvider.load(); // Refresh sales history

    // SYNC: Push return record to Hub if client
    final isClient = db.settings.isWindowsClient;
    if (isClient) {
      SyncQueueService.instance.addToQueue(
        entity: 'sale',
        action: 'create',
        data: returnSale.toJson(),
      );
    }

    if (!mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Refund processed for $invoiceNo'),
      backgroundColor: AppTheme.success,
    ));
  }
}
