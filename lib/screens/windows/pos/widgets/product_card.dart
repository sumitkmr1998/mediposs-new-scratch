import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/models/medicine.dart';
import '../../../../shared/models/procedure.dart';
import '../../../../shared/providers/cart_provider.dart';
import '../../../../theme/app_theme.dart';

class ProductCard extends StatelessWidget {
  final dynamic item;
  final VoidCallback onTap;
  final FocusNode focusNode;
  final void Function(TapDownDetails)? onSecondaryTap;

  const ProductCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.focusNode,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final isProcedure = item is Procedure;
    final name = item.name;
    final price = isProcedure ? item.basePrice : item.sellingPrice;
    final icon = isProcedure ? Icons.auto_awesome : Icons.medication;
    final cart = context.read<CartProvider>();
    final isLowStock = !isProcedure && 
        (cart.isClinicalDispense ? item.mainStock <= item.lowStockThreshold : item.isLowStock);
    final activeBatch = isProcedure ? null : (item as Medicine).getActiveBatch(cart.isClinicalDispense);

    return InkWell(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTap,
      focusNode: focusNode,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        // Use a slight border when focused
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: focusNode.hasFocus
              ? BorderSide(
                  color: isLowStock
                      ? AppTheme.warning
                      : Theme.of(context).colorScheme.primary,
                  width: 2)
              : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                isProcedure ? 'Procedure' : item.unit,
                style: TextStyle(color: context.textMutedColor, fontSize: 11),
              ),
              const SizedBox(height: 4),
              if (!isProcedure && activeBatch != null) ...[
                Row(
                  children: [
                    Icon(Icons.layers, size: 10, color: context.textMutedColor),
                    const SizedBox(width: 4),
                    Text(
                      'Batch: ${activeBatch.batchNo}',
                      style: TextStyle(
                        fontSize: 10,
                        color: context.textMutedColor,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.event,
                        size: 10,
                        color: activeBatch.expiryDate.isBefore(
                                DateTime.now().add(const Duration(days: 90)))
                            ? AppTheme.danger
                            : context.textMutedColor),
                    const SizedBox(width: 4),
                    Text(
                      'Exp: ${activeBatch.expiryDate.day}/${activeBatch.expiryDate.month}/${activeBatch.expiryDate.year}',
                      style: TextStyle(
                        fontSize: 10,
                        color: activeBatch.expiryDate.isBefore(
                                DateTime.now().add(const Duration(days: 90)))
                            ? AppTheme.danger
                            : context.textMutedColor,
                        fontWeight: activeBatch.expiryDate.isBefore(
                                DateTime.now().add(const Duration(days: 90)))
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '₹${price.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  if (!isProcedure)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: item.isLowStock
                            ? AppTheme.warning.withValues(alpha: 0.2)
                            : context.borderColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '${cart.isClinicalDispense ? item.getNonExpiredMainStock() : item.getNonExpiredStoreStock()}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isLowStock
                              ? AppTheme.warning
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.add_circle_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
