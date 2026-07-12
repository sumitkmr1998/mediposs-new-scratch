import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';

class PaymentSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const PaymentSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payment Method',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: context.textMutedColor)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PayChip(
                id: 'cash',
                label: 'Cash',
                selected: selected,
                onTap: onSelected),
            PayChip(
                id: 'upi', label: 'UPI', selected: selected, onTap: onSelected),
            PayChip(
                id: 'card',
                label: 'Card',
                selected: selected,
                onTap: onSelected),
            PayChip(
                id: 'mixed',
                label: 'Mixed',
                selected: selected,
                onTap: onSelected),
          ],
        ),
      ],
    );
  }
}

class PayChip extends StatelessWidget {
  final String id;
  final String label;
  final String selected;
  final ValueChanged<String> onTap;

  const PayChip({
    super.key,
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == id;
    return GestureDetector(
      onTap: () => onTap(id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : context.surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isSelected ? AppTheme.primary : context.borderColor),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : context.textMutedColor,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
