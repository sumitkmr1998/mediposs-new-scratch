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
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.borderColor.withValues(alpha: 0.05))),
        ),
        child: Row(
          children: [
            // Sleek Rounded Quantity Selector
            Container(
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_rounded, size: 16),
                    onPressed: item.qty > 1
                        ? () => cart.updateQty(item.id, item.qty - 1, isProcedure: item.isProcedure)
                        : onRemove,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    color: AppTheme.primary,
                  ),
                  GestureDetector(
                    onTap: () => _showManualQtyDialog(context, cart, maxStock),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 28),
                      alignment: Alignment.center,
                      child: Text(
                        '${item.qty}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, size: 16),
                    onPressed: (item.isProcedure || cart.isReturnMode || item.qty < maxStock)
                        ? () => cart.updateQty(item.id, item.qty + 1, isProcedure: item.isProcedure)
                        : null,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    color: AppTheme.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name.toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Tag(
                        label: '₹${item.isProcedure ? (item.customPrice ?? item.procedure!.basePrice).toStringAsFixed(0) : item.medicine!.sellingPrice.toStringAsFixed(0)}',
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
            const SizedBox(width: 8),
            Text(
              '₹${item.lineTotal.toStringAsFixed(0)}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showManualQtyDialog(BuildContext context, CartProvider cart, int maxStock) {
    final ctrl = TextEditingController(text: item.qty.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Quantity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Max: $maxStock',
            suffixText: item.isProcedure ? '' : item.medicine!.unit,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(ctrl.text);
              if (val != null && val > 0) {
                int finalQty = val;
                if (!item.isProcedure && !cart.isReturnMode && finalQty > maxStock) {
                  finalQty = maxStock;
                }
                cart.updateQty(item.id, finalQty, isProcedure: item.isProcedure);
              }
              Navigator.pop(ctx);
            },
            child: const Text('SET'),
          ),
        ],
      ),
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
