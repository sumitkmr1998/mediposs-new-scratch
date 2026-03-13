import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/cart_provider.dart';
import '../../shared/models/medicine.dart';
import '../../theme/app_theme.dart';
import '../../widgets/android/patient_dialogs_android.dart';
import '../../shared/services/printing_service.dart';
import '../../shared/services/sync_service.dart';

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
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
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
                                  '${cart.patientName} ${cart.patientPhone.isNotEmpty ? ' • ${cart.patientPhone}' : ''}',
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
                // Medicine Search
                Autocomplete<Medicine>(
                  displayStringForOption: (m) => m.name,
                  optionsBuilder: (TextEditingValue val) {
                    if (val.text.isEmpty) return const Iterable.empty();
                    final q = val.text.toLowerCase();
                    return inv.medicines.where((m) =>
                        m.storeStock > 0 &&
                        (m.name.toLowerCase().contains(q) ||
                            m.barcode.contains(val.text)));
                  },
                  onSelected: (m) {
                    cart.addItem(m);
                    _searchCtrl.clear();
                    _autocompleteCtrl
                        ?.clear(); // Immediately clear the visual input
                    _currentSearchFocusNode?.requestFocus();
                    _onMedicineAddedToCart(m.id);
                  },
                  fieldViewBuilder: (ctx, ctrl, focusNode, onFieldSubmitted) {
                    _currentSearchFocusNode =
                        focusNode; // Save a reference so we can focus it later
                    _autocompleteCtrl = ctrl; // Save reference to clear later
                    _searchCtrl.text = ctrl.text;
                    ctrl.addListener(() {
                      if (ctrl.text != _searchCtrl.text) {
                        _searchCtrl.text = ctrl.text;
                      }
                    });
                    return TextField(
                      controller: ctrl,
                      focusNode:
                          focusNode, // CRITICAL: Use Autocomplete's focus node!
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search medicine or scan barcode...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.person_add_alt_1),
                              tooltip: 'Select Patient',
                              onPressed: _showPatientProactiveSearch,
                              color: AppTheme.primary,
                            ),
                            IconButton(
                              icon: const Icon(Icons.receipt_long),
                              tooltip: 'Load Prescription',
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Load Prescription feature coming soon')),
                                );
                              },
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: context.borderColor),
                        ),
                        filled: true,
                        fillColor: context.surfaceColor,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
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
                              final m = options.elementAt(i);
                              return ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color:
                                        AppTheme.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.medication,
                                      color: AppTheme.primary, size: 20),
                                ),
                                title: Text(
                                  m.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(m.unit),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '₹${m.sellingPrice.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                          color: AppTheme.primaryLight,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'Stock: ${m.storeStock}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: m.isLowStock
                                            ? AppTheme.warning
                                            : context.textMutedColor,
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () => onSelected(m),
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

          // 2. Scrollable Cart & Checkout Section
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- CART LIST ---
                  if (cart.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.shopping_basket_outlined,
                                size: 64, color: context.borderColor),
                            const SizedBox(height: 16),
                            Text('No items in cart',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: context.textMutedColor)),
                            const SizedBox(height: 8),
                            Text('Search to add items',
                                style:
                                    TextStyle(color: context.textMutedColor)),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: cart.items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final item = cart.items[i];
                        return Container(
                          decoration: BoxDecoration(
                            color: context.surfaceColor,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                                color:
                                    context.borderColor.withValues(alpha: 0.5)),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Qty Input
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: TextField(
                                    focusNode:
                                        _getQtyFocusNode(item.medicine.id),
                                    controller: _getQtyController(
                                        item.medicine.id, item.qty),
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: AppTheme.primary),
                                    decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero),
                                    onChanged: (val) {
                                      final newQty = int.tryParse(val);
                                      if (newQty != null && newQty > 0) {
                                        int finalQty = newQty;
                                        if (!cart.isReturnMode &&
                                            finalQty >
                                                item.medicine.storeStock) {
                                          finalQty = item.medicine.storeStock;
                                          final ctrl = _getQtyController(
                                              item.medicine.id, item.qty);
                                          ctrl.text = finalQty.toString();
                                          ctrl.selection =
                                              TextSelection.collapsed(
                                                  offset: finalQty
                                                      .toString()
                                                      .length);
                                        }
                                        cart.updateQty(
                                            item.medicine.id, finalQty);
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Item Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.medicine.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Text(
                                        '₹${item.medicine.sellingPrice.toStringAsFixed(2)} / ${item.medicine.unit}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: context.textMutedColor)),
                                  ],
                                ),
                              ),
                              // Price & Remove
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('₹${item.lineTotal.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16)),
                                  const SizedBox(height: 8),
                                  InkWell(
                                    onTap: () =>
                                        cart.removeItem(item.medicine.id),
                                    child: const Text('Remove',
                                        style: TextStyle(
                                            color: AppTheme.danger,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),

                  // --- CHECKOUT PANEL ---
                  Container(
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                          color: context.borderColor.withValues(alpha: 0.5)),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Checkout',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primaryLight)),
                        const SizedBox(height: 12),

                        // Discount
                        TextField(
                          controller: _discountCtrl,
                          focusNode: _discountFocus,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Discount (₹)',
                            prefixIcon: const Icon(Icons.discount_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onChanged: (val) {
                            final discount = double.tryParse(val) ?? 0;
                            cart.setDiscount(discount);
                          },
                          onSubmitted: (_) => _paymentFocus.requestFocus(),
                        ),
                        const SizedBox(height: 12),

                        // Payment Method
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
                            _PayChip('cash', 'Cash', _paymentMethod,
                                (v) => setState(() => _paymentMethod = v)),
                            _PayChip('upi', 'UPI', _paymentMethod,
                                (v) => setState(() => _paymentMethod = v)),
                            _PayChip('card', 'Card', _paymentMethod,
                                (v) => setState(() => _paymentMethod = v)),
                            _PayChip('mixed', 'Mixed', _paymentMethod,
                                (v) => setState(() => _paymentMethod = v)),
                          ],
                        ),
                        if (_paymentMethod == 'mixed') ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                  child: _MixedField(
                                      label: 'Cash',
                                      controller: _mixCashCtrl,
                                      focusNode: _mixCashFocus,
                                      onSubmitted: () =>
                                          _mixUpiFocus.requestFocus())),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: _MixedField(
                                      label: 'UPI',
                                      controller: _mixUpiCtrl,
                                      focusNode: _mixUpiFocus,
                                      onSubmitted: () =>
                                          _mixCardFocus.requestFocus())),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: _MixedField(
                                      label: 'Card',
                                      controller: _mixCardCtrl,
                                      focusNode: _mixCardFocus,
                                      onSubmitted: () => _doCheckout(cart))),
                            ],
                          ),
                        ],

                        const SizedBox(height: 16),

                        // Summary & Total
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: AppTheme.primary.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            children: [
                              _TotalRow('Subtotal',
                                  '₹${cart.subtotal.toStringAsFixed(2)}'),
                              if (cart.discountAmount > 0)
                                _TotalRow('Discount',
                                    '-₹${cart.discountAmount.toStringAsFixed(2)}',
                                    color: AppTheme.danger),
                              if (cart.taxAmount > 0)
                                _TotalRow('Tax',
                                    '₹${cart.taxAmount.toStringAsFixed(2)}'),
                              const Divider(),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('TOTAL DUE',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14)),
                                  Text(
                                    cart.isReturnMode
                                        ? '-₹${cart.totalRounded.toStringAsFixed(2)}'
                                        : '₹${cart.totalRounded.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 22,
                                      color: cart.isReturnMode
                                          ? AppTheme.danger
                                          : AppTheme.primaryLight,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Main Checkout Button
                        SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: cart.items.isEmpty
                                ? null
                                : () => _doCheckout(cart),
                            icon: Icon(
                                cart.isReturnMode
                                    ? Icons.assignment_return
                                    : Icons.check_circle_outline,
                                size: 20),
                            label: Text(
                              cart.isReturnMode
                                  ? 'PROCESS RETURN'
                                  : 'COMPLETE SALE',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cart.isReturnMode
                                  ? AppTheme.danger
                                  : AppTheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(
                            height:
                                24), // Extra padding for bottom reachability
                      ], // closes Checkout Column children
                    ), // closes Checkout Column
                  ), // closes Checkout Container
                ], // closes Outer Column children
              ), // closes Outer Column
            ), // closes SingleChildScrollView
          ), // closes Expanded
        ], // closes Main Column children
      ), // closes Main Column
    ); // closes Scaffold
  }
}

class _PayChip extends StatelessWidget {
  final String value;
  final String label;
  final String selected;
  final ValueChanged<String> onChanged;

  const _PayChip(this.value, this.label, this.selected, this.onChanged);

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary
              : context.borderColor.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : context.textMutedColor,
          ),
        ),
      ),
    );
  }
}

class _MixedField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmitted;

  const _MixedField({
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
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      textAlign: TextAlign.center,
      onSubmitted: (_) => onSubmitted(),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _TotalRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(color: context.textMutedColor, fontSize: 14),
            ),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color ?? context.textColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
}
