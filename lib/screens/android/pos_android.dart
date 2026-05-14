import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';

import 'package:provider/provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/cart_provider.dart';
import '../../shared/models/medicine.dart';
import '../../theme/app_theme.dart';
import '../../widgets/android/patient_dialogs_android.dart';
import '../../shared/services/printing_service.dart';
import '../../shared/services/sync_service.dart';
import '../../shared/providers/patient_provider.dart';
import '../../shared/providers/procedure_provider.dart';
import '../../shared/models/procedure.dart';

class PosAndroid extends StatefulWidget {
  const PosAndroid({super.key});

  @override
  State<PosAndroid> createState() => _PosAndroidState();
}

class _PosAndroidState extends State<PosAndroid> {
  final _searchCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _patientCtrl = TextEditingController();

  final _mixCashCtrl = TextEditingController(text: '0');
  final _mixUpiCtrl = TextEditingController(text: '0');
  final _mixCardCtrl = TextEditingController(text: '0');

  String _paymentMethod = 'cash';

  // --- Keyboard Workflow Focus Nodes ---
  final _searchFocus = FocusNode();
  final _discountFocus = FocusNode();
  final _paymentFocus = FocusNode();
  final _mixCashFocus = FocusNode();
  final _mixUpiFocus = FocusNode();
  final _mixCardFocus = FocusNode();

  FocusNode? _currentSearchFocusNode;
  TextEditingController? _autocompleteCtrl;

  // Map of cart items to their quantity FocusNodes
  final Map<int, FocusNode> _qtyFocusNodes = {};
  final Map<int, TextEditingController> _qtyControllers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _currentSearchFocusNode?.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _discountCtrl.dispose();
    _patientCtrl.dispose();
    _mixCashCtrl.dispose();
    _mixUpiCtrl.dispose();
    _mixCardCtrl.dispose();
    _searchFocus.dispose();
    _discountFocus.dispose();
    _paymentFocus.dispose();
    _mixCashFocus.dispose();
    _mixUpiFocus.dispose();
    _mixCardFocus.dispose();
    for (var node in _qtyFocusNodes.values) {
      node.dispose();
    }
    for (var ctrl in _qtyControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  FocusNode _getQtyFocusNode(int medicineId) {
    if (!_qtyFocusNodes.containsKey(medicineId)) {
      final node = FocusNode();
      node.addListener(() {
        if (node.hasFocus && _qtyControllers.containsKey(medicineId)) {
          final ctrl = _qtyControllers[medicineId]!;
          ctrl.selection = TextSelection(
            baseOffset: 0,
            extentOffset: ctrl.text.length,
          );
        }
      });
      _qtyFocusNodes[medicineId] = node;
    }
    return _qtyFocusNodes[medicineId]!;
  }

  TextEditingController _getQtyController(int medicineId, int qty) {
    if (!_qtyControllers.containsKey(medicineId)) {
      _qtyControllers[medicineId] = TextEditingController(text: qty.toString());
    } else {
      if (!_qtyFocusNodes[medicineId]!.hasFocus) {
        _qtyControllers[medicineId]!.text = qty.toString();
      }
    }
    return _qtyControllers[medicineId]!;
  }

  void _onMedicineAddedToCart(int medicineId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _getQtyFocusNode(medicineId).requestFocus();
    });
  }

  Future<void> _doCheckout(CartProvider cart) async {
    cart.setPatient(name: _patientCtrl.text.trim(), id: cart.patientId);
    final discount = double.tryParse(_discountCtrl.text) ?? 0;
    cart.setDiscount(discount);
    cart.setPaymentMethod(_paymentMethod);

    if (_paymentMethod == 'mixed') {
      final cash = double.tryParse(_mixCashCtrl.text) ?? 0;
      final upi = double.tryParse(_mixUpiCtrl.text) ?? 0;
      final card = double.tryParse(_mixCardCtrl.text) ?? 0;

      final sum = cash + upi + card;
      if ((sum - cart.totalRounded).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Mixed amounts (₹$sum) must exactly equal total (₹${cart.totalRounded})!',
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
        return;
      }
      cart.setMixedAmounts(cash, upi, card);
    }

    final sale = await cart.checkout(context.read<SyncService>());
    if (!context.mounted) return;

    if (sale != null) {
      _mixCashCtrl.text = '0';
      _mixUpiCtrl.text = '0';
      _mixCardCtrl.text = '0';
      _discountCtrl.clear();
      _searchCtrl.clear();
      _patientCtrl.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sale.isReturn
                ? '✅ Return ${sale.invoiceNo} processed — Refund ₹${sale.total.abs().toStringAsFixed(2)}'
                : '✅ Sale ${sale.invoiceNo} complete — ₹${sale.total.toStringAsFixed(2)}',
          ),
          backgroundColor: sale.isReturn ? AppTheme.danger : AppTheme.success,
        ),
      );

      await PrintingService.instance.printReceipt(context, sale);
      _showPatientProactiveSearch();
      _currentSearchFocusNode?.requestFocus();
    }
  }

  void _handleManualClear() {
    final cart = context.read<CartProvider>();
    cart.clearCart();
    _patientCtrl.clear();
    _showPatientProactiveSearch();
  }

  void _showPatientProactiveSearch() {
    AndroidPatientDialogs.showSearchSheet(
      context,
      onSelected: (p) {
        final cart = context.read<CartProvider>();
        cart.setPatient(name: p.name, phone: p.phone, id: p.id);
        _patientCtrl.text = p.name;
        _currentSearchFocusNode?.requestFocus();
      },
    );
  }

  void _showItemContextMenu(CartItem item, CartProvider cart) {
    if (!item.isProcedure) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item.name.toUpperCase(),
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: AppTheme.primary),
              title: const Text('Edit Price'),
              onTap: () {
                Navigator.pop(ctx);
                _editProcedurePrice(item, cart);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: AppTheme.danger),
              title: const Text('Remove from Cart'),
              onTap: () {
                Navigator.pop(ctx);
                cart.removeItem(item.id, isProcedure: true);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _editProcedurePrice(CartItem item, CartProvider cart) {
    final ctrl = TextEditingController(
        text: (item.customPrice ?? item.procedure!.basePrice)
            .toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Procedure Price'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Price',
            prefixText: '₹',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              final newPrice = double.tryParse(ctrl.text);
              if (newPrice != null) {
                cart.updateProcedurePrice(item.id, newPrice);
              }
              Navigator.pop(ctx);
            },
            child: const Text('UPDATE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final cart = context.watch<CartProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Sale'),
        backgroundColor:
            cart.isReturnMode ? AppTheme.danger.withValues(alpha: 0.8) : null,
        actions: [
          Row(
            children: [
              Text(
                'RETURN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color:
                      cart.isReturnMode ? Colors.white : context.textMutedColor,
                ),
              ),
              Switch(
                value: cart.isReturnMode,
                onChanged: (_) => cart.toggleReturnMode(),
                activeThumbColor: Colors.white,
                activeTrackColor: AppTheme.danger,
              ),
            ],
          ),
          const SizedBox(width: 8),
          if (cart.items.isNotEmpty)
            IconButton(
              icon: Icon(
                Icons.delete_sweep,
                color: cart.isReturnMode ? Colors.white : AppTheme.danger,
              ),
              tooltip: 'Clear Cart',
              onPressed: _handleManualClear,
            ),
        ],
      ),
      body: Column(
        children: [
          // 1. Pinned Search Section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surfaceColor.withValues(alpha: 0.8),
              border: Border(
                  bottom: BorderSide(
                      color: context.borderColor.withValues(alpha: 0.2))),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              children: [
                // Currently Selected Patient
                if (cart.patientName.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person,
                            color: AppTheme.primary, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Patient attached',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: context.textMutedColor,
                                      fontWeight: FontWeight.bold)),
                              Text(
                                  '${cart.patientName}${context.read<PatientProvider>().getById(cart.patientId)?.uhid != null ? ' (${context.read<PatientProvider>().getById(cart.patientId)!.uhid})' : ''} ${cart.patientPhone.isNotEmpty ? ' • ${cart.patientPhone}' : ''}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.primaryLight)),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            cart.setPatient(name: '', phone: '', id: 0);
                            _patientCtrl.clear();
                          },
                          child: const Icon(Icons.close_rounded,
                              color: AppTheme.danger, size: 20),
                        ),
                      ],
                    ),
                  ),
                Autocomplete<Object>(
                  displayStringForOption: (item) => (item as dynamic).name,
                  optionsBuilder: (TextEditingValue val) {
                    if (val.text.isEmpty) return const Iterable.empty();
                    final q = val.text.toLowerCase();
                    final meds = inv.medicines.where((m) =>
                        m.storeStock > 0 &&
                        (m.name.toLowerCase().contains(q) ||
                            m.barcode.contains(val.text)));
                    final procs = context
                        .read<ProcedureProvider>()
                        .procedures
                        .where((p) => p.name.toLowerCase().contains(q));
                    return [...meds, ...procs];
                  },
                  onSelected: (item) {
                    if (item is Medicine) {
                      cart.addItem(item);
                      _onMedicineAddedToCart(item.id);
                    } else if (item is Procedure) {
                      cart.addProcedure(item);
                    }
                    _searchCtrl.clear();
                    _autocompleteCtrl?.clear();
                    _currentSearchFocusNode?.requestFocus();
                  },
                  fieldViewBuilder: (ctx, ctrl, focusNode, onFieldSubmitted) {
                    _currentSearchFocusNode = focusNode;
                    _autocompleteCtrl = ctrl;
                    _searchCtrl.text = ctrl.text;
                    ctrl.addListener(() {
                      if (ctrl.text != _searchCtrl.text) {
                        _searchCtrl.text = ctrl.text;
                      }
                    });
                    return TextField(
                      controller: ctrl,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        hintText: 'Search or Scan Barcode',
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: AppTheme.primary),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.person_search_rounded),
                              onPressed: _showPatientProactiveSearch,
                              color: AppTheme.primary,
                            ),
                          ],
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                              color:
                                  context.borderColor.withValues(alpha: 0.5)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                              color:
                                  context.borderColor.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(
                              color: AppTheme.primary, width: 2),
                        ),
                        filled: true,
                        fillColor: context.surfaceColor,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    );
                  },
                  optionsViewBuilder: (ctx, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.4,
                          ),
                          width: MediaQuery.of(context).size.width - 24,
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: options.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final item = options.elementAt(i);
                              final isProc = item is Procedure;
                              return ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: (isProc ? AppTheme.accent : AppTheme.primary)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                      isProc ? Icons.biotech : Icons.medication,
                                      color: isProc ? AppTheme.accent : AppTheme.primary,
                                      size: 20),
                                ),
                                title: Text((item as dynamic).name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(isProc ? 'Procedure' : (item as Medicine).unit),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                        '₹${isProc ? (item as Procedure).basePrice.toStringAsFixed(0) : (item as Medicine).sellingPrice.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                            color: AppTheme.primaryLight,
                                            fontWeight: FontWeight.bold)),
                                    if (!isProc)
                                      Text('Stock: ${(item as Medicine).storeStock}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: (item as Medicine).isLowStock
                                                  ? AppTheme.warning
                                                  : context.textMutedColor)),
                                  ],
                                ),
                                onTap: () => onSelected(item),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cart.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 64),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.shopping_basket_outlined,
                                size: 80,
                                color:
                                    context.borderColor.withValues(alpha: 0.3)),
                            const SizedBox(height: 16),
                            Text('YOUR CART IS EMPTY',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: context.textMutedColor,
                                    letterSpacing: 1.5)),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: cart.items.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: context.borderColor.withValues(alpha: 0.1)),
                      itemBuilder: (ctx, i) {
                        final item = cart.items[i];
                        return _CartItemTile(
                          item: item,
                          qtyFocusNode: _getQtyFocusNode(item.id),
                          qtyController:
                              _getQtyController(item.id, item.qty),
                          onQtyChanged: (val) {
                            final newQty = int.tryParse(val);
                            if (newQty != null && newQty > 0) {
                              cart.updateQty(item.id, newQty,
                                  isProcedure: item.isProcedure);
                            }
                          },
                          onRemove: () => cart.removeItem(item.id,
                              isProcedure: item.isProcedure),
                          onLongPress: () => _showItemContextMenu(item, cart),
                        );
                      },
                    ),
                  const SizedBox(height: 24),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: context.surfaceColor.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2)),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 20,
                                offset: const Offset(0, 10)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('TRANSACTION SUMMARY',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primaryLight,
                                    letterSpacing: 1)),
                            const SizedBox(height: 16),
                            _SummaryField(
                                label: 'Subtotal',
                                value: '₹${cart.subtotal.toStringAsFixed(2)}'),
                            if (cart.discountAmount > 0)
                              _SummaryField(
                                  label: 'Discount',
                                  value:
                                      '-₹${cart.discountAmount.toStringAsFixed(2)}',
                                  color: AppTheme.danger),
                            const Divider(height: 32),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('TOTAL DUE',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5)),
                                Text('₹${cart.totalRounded.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.primaryLight,
                                        letterSpacing: -1)),
                              ],
                            ),
                            const SizedBox(height: 24),
                            _PaymentSelector(
                              selected: _paymentMethod,
                              onSelected: (val) =>
                                  setState(() => _paymentMethod = val),
                            ),
                            if (_paymentMethod == 'mixed') ...[
                              const SizedBox(height: 16),
                              _MixedPaymentInputs(
                                cashCtrl: _mixCashCtrl,
                                upiCtrl: _mixUpiCtrl,
                                cardCtrl: _mixCardCtrl,
                                cashFocus: _mixCashFocus,
                                upiFocus: _mixUpiFocus,
                                cardFocus: _mixCardFocus,
                              ),
                            ],
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 60,
                              child: ElevatedButton(
                                onPressed: cart.items.isEmpty
                                    ? null
                                    : () => _doCheckout(cart),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18)),
                                ),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: cart.isReturnMode
                                          ? [
                                              AppTheme.danger,
                                              const Color(0xFFB91C1C)
                                            ]
                                          : [
                                              AppTheme.primary,
                                              AppTheme.primaryLight
                                            ],
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Container(
                                    alignment: Alignment.center,
                                    child: Text(
                                      cart.isReturnMode
                                          ? 'PROCESS RETURN'
                                          : 'COMPLETE CHECKOUT',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          letterSpacing: 1.5,
                                          color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryField extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _SummaryField({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.textMutedColor,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color ?? context.textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const _PaymentSelector({
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
            _PayChip(
                id: 'cash',
                label: 'Cash',
                selected: selected,
                onTap: onSelected),
            _PayChip(
                id: 'upi', label: 'UPI', selected: selected, onTap: onSelected),
            _PayChip(
                id: 'card',
                label: 'Card',
                selected: selected,
                onTap: onSelected),
            _PayChip(
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

class _PayChip extends StatelessWidget {
  final String id;
  final String label;
  final String selected;
  final ValueChanged<String> onTap;

  const _PayChip({
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

class _MixedPaymentInputs extends StatelessWidget {
  final TextEditingController cashCtrl, upiCtrl, cardCtrl;
  final FocusNode cashFocus, upiFocus, cardFocus;

  const _MixedPaymentInputs({
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
            child: _MixedField(
                label: 'Cash',
                controller: cashCtrl,
                focusNode: cashFocus,
                onSubmitted: () => upiFocus.requestFocus())),
        const SizedBox(width: 8),
        Expanded(
            child: _MixedField(
                label: 'UPI',
                controller: upiCtrl,
                focusNode: upiFocus,
                onSubmitted: () => cardFocus.requestFocus())),
        const SizedBox(width: 8),
        Expanded(
            child: _MixedField(
          label: 'Card',
          controller: cardCtrl,
          focusNode: cardFocus,
        )),
      ],
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final CartItem item;
  final FocusNode qtyFocusNode;
  final TextEditingController qtyController;
  final ValueChanged<String> onQtyChanged;
  final VoidCallback onRemove;
  final VoidCallback onLongPress;

  const _CartItemTile({
    required this.item,
    required this.qtyFocusNode,
    required this.qtyController,
    required this.onQtyChanged,
    required this.onRemove,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: TextField(
                  focusNode: qtyFocusNode,
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: AppTheme.primary),
                  decoration: const InputDecoration(
                      border: InputBorder.none, isDense: true),
                  onChanged: onQtyChanged,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name.toUpperCase(),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _Tag(
                          label:
                              '₹${item.isProcedure ? (item.customPrice ?? item.procedure!.basePrice).toStringAsFixed(0) : item.medicine!.sellingPrice.toStringAsFixed(0)}',
                          color: context.textMutedColor),
                      const SizedBox(width: 4),
                      _Tag(
                          label: item.isProcedure
                              ? 'PROCEDURE'
                              : 'BATCH: ${item.medicine!.batches.isNotEmpty ? item.medicine!.batches.first.batchNo : "N/A"}',
                          color: AppTheme.accent),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹${item.lineTotal.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: -0.5)),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('REMOVE',
                        style: TextStyle(
                            color: AppTheme.danger,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});

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

class _MixedField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onSubmitted;

  const _MixedField({
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
