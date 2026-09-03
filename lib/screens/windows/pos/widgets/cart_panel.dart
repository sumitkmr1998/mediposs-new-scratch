import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../shared/providers/cart_provider.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/patient_provider.dart';
import '../../../../shared/providers/opd_provider.dart';
import '../../../../shared/models/patient.dart';
import '../../../../shared/models/prescription.dart';
import '../../../../shared/services/objectbox_service.dart';
import '../../../../objectbox.g.dart';
import 'package:objectbox/objectbox.dart';
import '../../../../theme/app_theme.dart';

class CartPanel extends StatelessWidget {
  final CartProvider cart;
  final TextEditingController discountCtrl;
  final TextEditingController patientCtrl;
  final TextEditingController mixCashCtrl;
  final TextEditingController mixUpiCtrl;
  final TextEditingController mixCardCtrl;
  final FocusNode discountFocus;
  final FocusNode paymentFocus;
  final FocusNode mixCashFocus;
  final FocusNode mixUpiFocus;
  final FocusNode mixCardFocus;
  final FocusNode checkoutFocus;
  final String paymentMethod;
  final FocusNode Function(String) getQtyFocusNode;
  final TextEditingController Function(String, int) getQtyController;
  final FocusNode Function(String) getPriceFocusNode;
  final TextEditingController Function(String, double) getPriceController;
  final VoidCallback onQtyConfirm;
  final VoidCallback onPriceConfirm;
  final VoidCallback onDiscountConfirm;
  final VoidCallback onPaymentMethodConfirm;
  final ValueChanged<String> onPaymentMethodChanged;
  final VoidCallback onLoadPrescription;
  final VoidCallback onImportPreviousSales;
  final VoidCallback? onCheckout;

  const CartPanel({
    super.key,
    required this.cart,
    required this.discountCtrl,
    required this.patientCtrl,
    required this.mixCashCtrl,
    required this.mixUpiCtrl,
    required this.mixCardCtrl,
    required this.discountFocus,
    required this.paymentFocus,
    required this.mixCashFocus,
    required this.mixUpiFocus,
    required this.mixCardFocus,
    required this.checkoutFocus,
    required this.paymentMethod,
    required this.getQtyFocusNode,
    required this.getQtyController,
    required this.getPriceFocusNode,
    required this.getPriceController,
    required this.onQtyConfirm,
    required this.onPriceConfirm,
    required this.onDiscountConfirm,
    required this.onPaymentMethodConfirm,
    required this.onPaymentMethodChanged,
    required this.onLoadPrescription,
    required this.onImportPreviousSales,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Container(
      color: Theme.of(context).cardTheme.color,
      child: Column(
        children: [
          // Patient Name
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Autocomplete<Patient>(
                    displayStringForOption: (p) => p.name,
                    optionsBuilder: (TextEditingValue val) {
                      if (val.text.trim().isEmpty) return const Iterable.empty();
                      final patientProvider = context.read<PatientProvider>();
                      final results = patientProvider.searchPatients(val.text, limit: 40);
                      if (cart.isClinicalDispense) {
                        final opdPatientIds = context.read<OpdProvider>().todayQueue.map((a) => a.patientId).toSet();
                        return results.where((p) => opdPatientIds.contains(p.id));
                      }
                      return results;
                    },
                    onSelected: (p) {
                      cart.setPatient(name: p.name, phone: p.phone, id: p.id, uhid: p.uhid, address: p.address);
                      patientCtrl.text = p.name;
                    },
                    fieldViewBuilder: (ctx, ctrl, node, onFieldSubmitted) {
                      // Sync external controller if needed or just use this one
                      // We'll use the Autocomplete's internal ctrl but update our parent one
                      ctrl.addListener(() {
                        if (ctrl.text != patientCtrl.text) {
                          patientCtrl.text = ctrl.text;
                        }
                      });
                      // If parent ctrl changes (e.g. from prescription loader), sync here
                      if (patientCtrl.text != ctrl.text) {
                        ctrl.text = patientCtrl.text;
                      }

                      return TextField(
                        controller: ctrl,
                        focusNode: node,
                        onSubmitted: (_) => onFieldSubmitted(),
                        decoration: const InputDecoration(
                          hintText: 'Search Patient (Name/Phone/Addr)',
                          prefixIcon: Icon(Icons.person_outline),
                          isDense: true,
                        ),
                      );
                    },
                    optionsViewBuilder: (ctx, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          child: SizedBox(
                            width: 320,
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: options.length,
                              itemBuilder: (ctx, i) {
                                final p = options.elementAt(i);
                                final pres = ObjectBoxService.instance.prescriptionBox
                                    .query(Prescription_.patientId.equals(p.id))
                                    .order(Prescription_.createdAt, flags: Order.descending)
                                    .build()
                                    .findFirst();
                                final isDispensed = pres != null && pres.dispensed;
                                return Opacity(
                                  opacity: isDispensed ? 0.4 : 1.0,
                                  child: ListTile(
                                    title: Text(p.name),
                                    subtitle: Text('${p.uhid} • ${p.phone} • ${p.address}'),
                                    onTap: () => onSelected(p),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.receipt_long_outlined,
                    color: cart.isReturnMode
                        ? AppTheme.danger
                        : (cart.isClinicalDispense ? AppTheme.indigo : AppTheme.primary),
                  ),
                  tooltip: 'Load Prescription',
                  onPressed: onLoadPrescription,
                ),
                if (cart.patientId != 0) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      Icons.restore_page_outlined,
                      color: cart.isReturnMode
                          ? AppTheme.danger
                          : (cart.isClinicalDispense ? AppTheme.indigo : AppTheme.primary),
                    ),
                    tooltip: 'Import from Previous Sales',
                    onPressed: onImportPreviousSales,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Cart Items
          Expanded(
            child: cart.items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.shopping_cart_outlined,
                          size: 48,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Cart is empty',
                          style: TextStyle(color: context.textMutedColor),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: cart.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final item = cart.items[i];
                      final key =
                          item.isProcedure ? 'p_${item.id}' : 'm_${item.id}';
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (item.medicine?.isScheduleH1 == true) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppTheme.danger, width: 0.8),
                                ),
                                child: const Text(
                                  'H1',
                                  style: TextStyle(
                                    color: AppTheme.danger,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ]
                          ],
                        ),
                        subtitle: item.isProcedure
                            ? Row(
                                children: [
                                  const Text('₹', style: TextStyle(fontSize: 12)),
                                  SizedBox(
                                    width: 60,
                                    child: TextField(
                                      controller: getPriceController(
                                          key,
                                          item.customPrice ??
                                              item.procedure!.basePrice),
                                      focusNode: getPriceFocusNode(key),
                                      style: const TextStyle(fontSize: 12),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (val) {
                                        final p = double.tryParse(val);
                                        if (p != null) {
                                          cart.updatePrice(item.id, p);
                                        }
                                      },
                                      onSubmitted: (val) {
                                        final p = double.tryParse(val);
                                        if (p != null) {
                                          cart.updatePrice(item.id, p);
                                          onPriceConfirm();
                                        }
                                      },
                                    ),
                                  ),
                                  Text(' × ${item.qty}',
                                      style: const TextStyle(fontSize: 12)),
                                ],
                              )
                            : Text(
                                '₹${(item.medicine?.sellingPrice ?? item.customPrice ?? item.procedure!.basePrice).toStringAsFixed(2)} × ${item.qty}',
                              ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '₹${item.lineTotal.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: cart.isReturnMode
                                    ? AppTheme.danger
                                    : (cart.isClinicalDispense
                                        ? AppTheme.indigo
                                        : AppTheme.primaryLight),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => cart.removeItem(item.id,
                                  isProcedure: item.isProcedure),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: AppTheme.danger,
                              ),
                            ),
                          ],
                        ),
                        leading: Container(
                          width: 65,
                          height: 42,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness ==
                                    Brightness.dark
                                ? (cart.isClinicalDispense
                                    ? AppTheme.indigo.withValues(alpha: 0.15)
                                    : AppTheme.primary.withValues(alpha: 0.15))
                                : (cart.isClinicalDispense
                                    ? AppTheme.indigo.withValues(alpha: 0.1)
                                    : AppTheme.primaryLight.withValues(alpha: 0.1)),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: cart.isClinicalDispense
                                  ? AppTheme.indigo.withValues(alpha: 0.5)
                                  : AppTheme.primaryLight.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: TextField(
                            focusNode: getQtyFocusNode(key),
                            controller: getQtyController(
                              key,
                              item.qty,
                            ),
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? (cart.isClinicalDispense
                                      ? AppTheme.indigo
                                      : AppTheme.primaryLight)
                                  : (cart.isClinicalDispense
                                      ? AppTheme.indigo
                                      : AppTheme.primary),
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (val) {
                              final newQty = int.tryParse(val);
                              if (newQty != null && newQty > 0) {
                                int finalQty = newQty;
                                final maxStock = cart.isClinicalDispense ? item.medicine!.getNonExpiredMainStock() : item.medicine!.getNonExpiredStoreStock();
                                if (!item.isProcedure &&
                                    !cart.isReturnMode &&
                                    finalQty > maxStock) {
                                  finalQty = maxStock;
                                  final ctrl = getQtyController(
                                    key,
                                    item.qty,
                                  );
                                  ctrl.text = finalQty.toString();
                                  ctrl.selection = TextSelection.collapsed(
                                    offset: finalQty.toString().length,
                                  );
                                }
                                cart.updateQty(item.id, finalQty,
                                    isProcedure: item.isProcedure);
                              }
                            },
                            onSubmitted: (val) {
                              int newQty = int.tryParse(val) ?? 1;
                              if (newQty > 0) {
                                final maxStock = cart.isClinicalDispense ? item.medicine!.mainStock : item.medicine!.storeStock;
                                if (!item.isProcedure &&
                                    !cart.isReturnMode &&
                                    newQty > maxStock) {
                                  newQty = maxStock;
                                }
                                cart.updateQty(item.id, newQty,
                                    isProcedure: item.isProcedure);
                              } else {
                                cart.updateQty(item.id, 1,
                                    isProcedure: item.isProcedure);
                              }
                              onQtyConfirm();
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Discount & Totals
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.borderColor)),
            ),
            child: Column(
              children: [
                // Discount
                TextField(
                  controller: discountCtrl,
                  focusNode: discountFocus,
                  keyboardType: TextInputType.number,
                  enabled: auth.canDiscountSales,
                  decoration: const InputDecoration(
                    hintText: 'Discount (₹)',
                    prefixIcon: Icon(Icons.discount_outlined),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    final discount = double.tryParse(val) ?? 0.0;
                    cart.setDiscount(discount);
                  },
                  onSubmitted: (_) => onDiscountConfirm(),
                ),
                const SizedBox(height: 12),

                // Payment method
                SizedBox(
                  height: 32,
                  child: Focus(
                    focusNode: paymentFocus,
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent) {
                        final methods = ['cash', 'card', 'upi', 'mixed'];
                        var idx = methods.indexOf(paymentMethod);
                        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                          idx = (idx + 1) % methods.length;
                          onPaymentMethodChanged(methods[idx]);
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.arrowLeft) {
                          idx = (idx - 1 + methods.length) % methods.length;
                          onPaymentMethodChanged(methods[idx]);
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.enter) {
                          onPaymentMethodConfirm();
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Center(
                          child: Text(
                            'Pay: ',
                            style: TextStyle(
                              color: context.textMutedColor,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        PayChip(
                          'cash',
                          'Cash',
                          paymentMethod,
                          onPaymentMethodChanged,
                          paymentFocus,
                        ),
                        const SizedBox(width: 8),
                        PayChip(
                          'card',
                          'Card',
                          paymentMethod,
                          onPaymentMethodChanged,
                          paymentFocus,
                        ),
                        const SizedBox(width: 8),
                        PayChip(
                          'upi',
                          'UPI',
                          paymentMethod,
                          onPaymentMethodChanged,
                          paymentFocus,
                        ),
                        const SizedBox(width: 8),
                        PayChip(
                          'mixed',
                          'Mixed',
                          paymentMethod,
                          onPaymentMethodChanged,
                          paymentFocus,
                        ),
                      ],
                    ),
                  ),
                ),

                if (paymentMethod == 'mixed') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: MixedField(
                          label: 'Cash',
                          controller: mixCashCtrl,
                          focusNode: mixCashFocus,
                          onSubmitted: () => mixUpiFocus.requestFocus(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MixedField(
                          label: 'UPI',
                          controller: mixUpiCtrl,
                          focusNode: mixUpiFocus,
                          onSubmitted: () => mixCardFocus.requestFocus(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MixedField(
                          label: 'Card',
                          controller: mixCardCtrl,
                          focusNode: mixCardFocus,
                          onSubmitted: () => onCheckout?.call(),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),

                // Totals
                TotalRow('Subtotal', '₹${cart.subtotal.toStringAsFixed(2)}'),
                if (cart.discountAmount > 0)
                  TotalRow(
                    'Discount',
                    '-₹${cart.discountAmount.toStringAsFixed(2)}',
                    color: AppTheme.danger,
                  ),
                if (cart.taxAmount > 0)
                  TotalRow('Tax', '₹${cart.taxAmount.toStringAsFixed(2)}'),
                const Divider(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      cart.isReturnMode
                          ? '-₹${cart.totalRounded.toStringAsFixed(2)}'
                          : '₹${cart.totalRounded.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    focusNode: checkoutFocus,
                    onPressed: cart.items.isEmpty ? null : onCheckout,
                    icon: Icon(
                      cart.isReturnMode
                          ? Icons.assignment_return
                          : (cart.isClinicalDispense ? Icons.local_hospital_outlined : Icons.shopping_cart_checkout),
                    ),
                    label: Text(
                      cart.isEditingSale
                          ? 'UPDATE SALE'
                          : (cart.isReturnMode
                              ? 'REFUND & PROCESS RETURN'
                              : (cart.isClinicalDispense ? 'DISPENSE CLINICAL MEDICINES' : 'COLLECT PAYMENT & PRINT')),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PayChip extends StatelessWidget {
  final String value;
  final String label;
  final String selected;
  final ValueChanged<String> onChanged;
  final FocusNode? primaryFocusNode;

  const PayChip(
    this.value,
    this.label,
    this.selected,
    this.onChanged,
    this.primaryFocusNode, {
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedBuilder(
        animation: primaryFocusNode ?? const AlwaysStoppedAnimation(null),
        builder: (context, _) {
          final isFocused = primaryFocusNode?.hasFocus ?? false;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected
                  ? (context.read<CartProvider>().isReturnMode
                      ? AppTheme.danger
                      : (context.read<CartProvider>().isClinicalDispense
                          ? AppTheme.indigo
                          : AppTheme.primary))
                  : context.borderColor,
              borderRadius: BorderRadius.circular(8),
              border: (isFocused && isSelected)
                  ? Border.all(
                      color: context.read<CartProvider>().isReturnMode
                          ? AppTheme.danger
                          : (context.read<CartProvider>().isClinicalDispense
                              ? AppTheme.indigo
                              : AppTheme.primaryLight),
                      width: 2)
                  : null,
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : context.textMutedColor,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class MixedField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmitted;

  const MixedField({
    super.key,
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      textAlign: TextAlign.center,
      onSubmitted: (_) => onSubmitted(),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      ),
    );
  }
}

class TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const TotalRow(this.label, this.value, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(color: context.textMutedColor, fontSize: 13),
            ),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color ?? context.textColor,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
}
