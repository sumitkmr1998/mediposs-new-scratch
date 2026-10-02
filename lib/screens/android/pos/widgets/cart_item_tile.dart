import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/providers/cart_provider.dart';
import '../../../../theme/app_theme.dart';

class CartItemTile extends StatelessWidget {
  final CartItem item;
  final VoidCallback onRemove;
  final VoidCallback onLongPress;

  const CartItemTile({
    super.key,
    required this.item,
    required this.onRemove,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final maxStock = item.isProcedure ? 9999 : (cart.isClinicalDispense ? item.medicine!.getNonExpiredMainStock() : item.medicine!.getNonExpiredStoreStock());

    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.borderColor.withValues(alpha: 0.1))),
        ),
        child: Row(
          children: [
            // Sleek Compact Quantity Selector
            Container(
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.borderColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_rounded, size: 14),
                    onPressed: item.qty > 1
                        ? () => cart.updateQty(item.id, item.qty - 1, isProcedure: item.isProcedure)
                        : onRemove,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 30),
                    color: AppTheme.primary,
                  ),
                  InkWell(
                    onTap: () => _showManualQtyDialog(context, cart, maxStock),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 26),
                      alignment: Alignment.center,
                      child: Text(
                        '${item.qty}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, size: 14),
                    onPressed: (item.isProcedure || cart.isReturnMode || cart.isEditingSale || item.qty < maxStock)
                        ? () => cart.updateQty(item.id, item.qty + 1, isProcedure: item.isProcedure)
                        : null,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 30),
                    color: AppTheme.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () => _showManualQtyDialog(context, cart, maxStock),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Tag(
                            label: '₹${item.unitPrice.toStringAsFixed(0)}',
                            color: context.textMutedColor,
                          ),
                          const SizedBox(width: 4),
                          Tag(
                            label: item.isProcedure
                                ? 'PROCEDURE'
                                : 'BATCH: ${(item.medicine!.getActiveBatch(cart.isClinicalDispense) ?? (item.medicine!.batches.isNotEmpty ? item.medicine!.batches.first : null))?.batchNo ?? "N/A"}',
                            color: AppTheme.accent,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '₹${item.lineTotal.toStringAsFixed(0)}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showManualQtyDialog(BuildContext context, CartProvider cart, int maxStock) {
    final ctrl = TextEditingController(text: item.qty.toString());
    ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void applyQty(int val) {
              int finalQty = val;
              if (finalQty <= 0) finalQty = 1;
              if (!item.isProcedure && !cart.isReturnMode && !cart.isEditingSale && finalQty > maxStock) {
                finalQty = maxStock;
              }
              cart.updateQty(item.id, finalQty, isProcedure: item.isProcedure);
              Navigator.pop(ctx);
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.edit_note_rounded, color: AppTheme.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          item.isProcedure
                              ? 'Procedure'
                              : (cart.isReturnMode
                                  ? 'Return Mode (Stock: $maxStock ${item.medicine?.unit ?? ""})'
                                  : 'Stock: $maxStock ${item.medicine?.unit ?? ""}'),
                          style: TextStyle(fontSize: 10, color: cart.isReturnMode ? AppTheme.danger : context.textMutedColor, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 4),
                  // Compact Number Stepper Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        icon: const Icon(Icons.remove_rounded, size: 18),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(38, 38),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          final cur = int.tryParse(ctrl.text) ?? item.qty;
                          if (cur > 1) {
                            final next = cur - 1;
                            ctrl.text = next.toString();
                            ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
                            setDialogState(() {});
                          }
                        },
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: ctrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          autofocus: true,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.primary),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: AppTheme.primary.withValues(alpha: 0.05),
                          ),
                          onSubmitted: (val) {
                            final parsed = int.tryParse(val) ?? item.qty;
                            applyQty(parsed);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.add_rounded, size: 18),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(38, 38),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          final cur = int.tryParse(ctrl.text) ?? item.qty;
                          if (item.isProcedure || cart.isReturnMode || cur < maxStock) {
                            final next = cur + 1;
                            ctrl.text = next.toString();
                            ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
                            setDialogState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Quick Preset Chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final preset in [1, 2, 5, 10])
                        if (item.isProcedure || cart.isReturnMode || preset <= maxStock)
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                            label: Text('+$preset', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            onPressed: () {
                              final cur = int.tryParse(ctrl.text) ?? item.qty;
                              final next = cur + preset;
                              final limited = (!item.isProcedure && !cart.isReturnMode && next > maxStock) ? maxStock : next;
                              ctrl.text = limited.toString();
                              ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
                              setDialogState(() {});
                            },
                          ),
                      if (!item.isProcedure && maxStock > 0 && !cart.isReturnMode)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                          avatar: const Icon(Icons.bolt_rounded, size: 14, color: AppTheme.warning),
                          label: Text('Max ($maxStock)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          onPressed: () {
                            ctrl.text = maxStock.toString();
                            ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
                            setDialogState(() {});
                          },
                        ),
                    ],
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('CANCEL', style: TextStyle(color: context.textMutedColor, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final val = int.tryParse(ctrl.text) ?? item.qty;
                    applyQty(val);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  child: const Text('SET QUANTITY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class Tag extends StatelessWidget {
  final String label;
  final Color color;
  const Tag({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}
