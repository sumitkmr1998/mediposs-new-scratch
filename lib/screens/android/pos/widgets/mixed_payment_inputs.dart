import 'package:flutter/material.dart';

class MixedPaymentInputs extends StatelessWidget {
  final TextEditingController cashCtrl, upiCtrl, cardCtrl;
  final FocusNode cashFocus, upiFocus, cardFocus;

  const MixedPaymentInputs({
    super.key,
    required this.cashCtrl,
    required this.upiCtrl,
    required this.cardCtrl,
    required this.cashFocus,
    required this.upiFocus,
    required this.cardFocus,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: MixedField(
                label: 'Cash',
                controller: cashCtrl,
                focusNode: cashFocus,
                onSubmitted: () => upiFocus.requestFocus())),
        const SizedBox(width: 8),
        Expanded(
            child: MixedField(
                label: 'UPI',
                controller: upiCtrl,
                focusNode: upiFocus,
                onSubmitted: () => cardFocus.requestFocus())),
        const SizedBox(width: 8),
        Expanded(
            child: MixedField(
          label: 'Card',
          controller: cardCtrl,
          focusNode: cardFocus,
        )),
      ],
    );
  }
}

class MixedField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onSubmitted;

  const MixedField({
    super.key,
    required this.label,
    required this.controller,
    required this.focusNode,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onSubmitted: (_) => onSubmitted?.call(),
    );
  }
}
