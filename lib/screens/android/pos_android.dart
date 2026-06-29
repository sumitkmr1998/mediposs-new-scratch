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
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/opd_provider.dart';
import '../../shared/models/appointment.dart';

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
  bool _isCheckingOut = false;

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
    final cart = context.read<CartProvider>();
    _patientCtrl.text = cart.patientName;
    _discountCtrl.text = cart.discountAmount > 0 ? cart.discountAmount.toStringAsFixed(0) : '';
    _paymentMethod = cart.paymentMethod;
    _mixCashCtrl.text = cart.mixedCash.toStringAsFixed(0);
    _mixUpiCtrl.text = cart.mixedUpi.toStringAsFixed(0);
    _mixCardCtrl.text = cart.mixedCard.toStringAsFixed(0);

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

  void _syncControllersWithCart() {
    final cart = context.read<CartProvider>();
    _patientCtrl.text = cart.patientName;
    _discountCtrl.text =
        cart.discountAmount > 0 ? cart.discountAmount.toStringAsFixed(0) : '';

    setState(() {
      _paymentMethod = cart.paymentMethod;
      _mixCashCtrl.text = cart.mixedCash.toStringAsFixed(0);
      _mixUpiCtrl.text = cart.mixedUpi.toStringAsFixed(0);
      _mixCardCtrl.text = cart.mixedCard.toStringAsFixed(0);
    });

    _searchCtrl.clear();
    _currentSearchFocusNode?.requestFocus();
  }

  void _onMedicineAddedToCart(int medicineId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _getQtyFocusNode(medicineId).requestFocus();
    });
  }

  void _handleClinicalDispenseToggle(bool val, CartProvider cart) {
    if (!val) {
      cart.setPatient(name: '', phone: '', id: 0, uhid: '');
      cart.setLinkedAppointment(null);
      _patientCtrl.clear();
      cart.setClinicalDispense(false);
      return;
    }

    final opd = context.read<OpdProvider>();
    final activeAppts = opd.todayQueue;

    if (activeAppts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No appointments found in today\'s OPD queue. Clinic Dispense requires a patient in today\'s queue.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).padding.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: context.borderColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'SELECT APPOINTMENT FOR CLINIC DISPENSE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: AppTheme.primaryLight,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: activeAppts.length,
                  itemBuilder: (c, i) {
                    final a = activeAppts[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: context.surfaceColor.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: context.borderColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              '#${a.tokenNumber}',
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          a.patientName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          'Doctor: Dr. ${a.doctorName} • Status: ${a.status.toUpperCase()}',
                          style: TextStyle(
                            color: context.textMutedColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onTap: () {
                          final patient = context.read<PatientProvider>().getById(a.patientId);
                          cart.setPatient(
                            name: a.patientName,
                            phone: a.patientPhone,
                            id: a.patientId,
                            uhid: patient?.uhid,
                          );
                          _patientCtrl.text = a.patientName;
                          cart.setLinkedAppointment(a.id);
                          cart.setClinicalDispense(true);
                          Navigator.pop(ctx);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _doCheckout(CartProvider cart) async {
    if (_isCheckingOut) return;
    setState(() => _isCheckingOut = true);
    try {
      final pName = _patientCtrl.text.trim();
      if (cart.isClinicalDispense) {
        if (cart.patientId == 0 || pName.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Clinic Dispense requires a registered patient!'),
              backgroundColor: AppTheme.danger,
            ),
          );
          return;
        }
      }
      
      if (pName.isEmpty) {
        cart.setPatient(name: '', phone: '', id: 0, uhid: '');
      } else {
        cart.setPatient(name: pName, id: cart.patientId, phone: cart.patientPhone, uhid: cart.patientUhid);
      }
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

      final currentUser = context.read<AuthProvider>().currentUser;
      final sale = await cart.checkout(context.read<SyncService>(), currentUser);
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
    } finally {
      setState(() => _isCheckingOut = false);
    }
  }

  void _handleManualClear() {
    final cart = context.read<CartProvider>();
    cart.clearCart();
    _patientCtrl.clear();
    _showPatientProactiveSearch();
  }

  void _showPatientProactiveSearch() {
    final cart = context.read<CartProvider>();
    AndroidPatientDialogs.showSearchSheet(
      context,
      limitToTodayOpd: cart.isClinicalDispense,
      onSelected: (p) {
        cart.setPatient(name: p.name, phone: p.phone, id: p.id, uhid: p.uhid);
        _patientCtrl.text = p.name;
        _currentSearchFocusNode?.requestFocus();
      },
      onAppointmentSelected: (Appointment appt) {
        final patient = context.read<PatientProvider>().getById(appt.patientId);
        cart.setPatient(name: appt.patientName, phone: appt.patientPhone, id: appt.patientId, uhid: patient?.uhid);
        _patientCtrl.text = appt.patientName;
        cart.setLinkedAppointment(appt.id);
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

  void _showCheckoutBottomSheet(CartProvider cart) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
            return Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 20 + keyboardHeight),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: context.borderColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'CHECKOUT SUMMARY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primaryLight,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SummaryField(
                    label: 'Subtotal',
                    value: '₹${cart.subtotal.toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Discount (₹)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.textMutedColor),
                      ),
                      SizedBox(
                        width: 120,
                        height: 36,
                        child: TextField(
                          controller: _discountCtrl,
                          focusNode: _discountFocus,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.end,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onChanged: (val) {
                            final disc = double.tryParse(val) ?? 0;
                            cart.setDiscount(disc);
                            setSheetState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TOTAL DUE',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '₹${cart.totalRounded.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryLight,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Payment Method',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.textMutedColor),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PayChip(
                        id: 'cash',
                        label: 'Cash',
                        selected: _paymentMethod,
                        onTap: (val) {
                          setSheetState(() => _paymentMethod = val);
                          setState(() => _paymentMethod = val);
                        },
                      ),
                      _PayChip(
                        id: 'upi',
                        label: 'UPI',
                        selected: _paymentMethod,
                        onTap: (val) {
                          setSheetState(() => _paymentMethod = val);
                          setState(() => _paymentMethod = val);
                        },
                      ),
                      _PayChip(
                        id: 'card',
                        label: 'Card',
                        selected: _paymentMethod,
                        onTap: (val) {
                          setSheetState(() => _paymentMethod = val);
                          setState(() => _paymentMethod = val);
                        },
                      ),
                      _PayChip(
                        id: 'mixed',
                        label: 'Mixed',
                        selected: _paymentMethod,
                        onTap: (val) {
                          setSheetState(() => _paymentMethod = val);
                          setState(() => _paymentMethod = val);
                        },
                      ),
                    ],
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
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isCheckingOut
                          ? null
                          : () async {
                              setState(() => _isCheckingOut = true);
                              try {
                                Navigator.pop(ctx);
                                await _doCheckout(cart);
                              } finally {
                                setState(() => _isCheckingOut = false);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: cart.isReturnMode
                                ? [AppTheme.danger, const Color(0xFFB91C1C)]
                                : [AppTheme.primary, AppTheme.primaryLight],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          child: Text(
                            cart.isEditingSale
                                ? 'UPDATE SALE'
                                : (cart.isReturnMode ? 'PROCESS RETURN' : 'COMPLETE CHECKOUT'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              letterSpacing: 1.2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStickyBottomBar(CartProvider cart) {
    final int itemCount = cart.items.fold(0, (sum, item) => sum + item.qty);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border(top: BorderSide(color: context.borderColor.withValues(alpha: 0.12))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                    style: TextStyle(
                      color: context.textMutedColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₹${cart.totalRounded.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primaryLight,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              height: 46,
              width: 170,
              child: ElevatedButton(
                onPressed: () => _showCheckoutBottomSheet(cart),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: cart.isReturnMode
                          ? [AppTheme.danger, const Color(0xFFB91C1C)]
                          : [AppTheme.primary, AppTheme.primaryLight],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Container(
                    alignment: Alignment.center,
                    child: Text(
                      cart.isReturnMode ? 'RETURN' : 'PROCEED TO PAY',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.8,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final cart = context.watch<CartProvider>();
    final auth = context.watch<AuthProvider>();

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
          if (cart.isEditingSale)
            Container(
              width: double.infinity,
              color: AppTheme.warning,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.edit_document, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'EDITING SALE: ${cart.editingInvoiceNo}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      cart.clearCart();
                      _syncControllersWithCart();
                    },
                    icon: const Icon(Icons.cancel_outlined, color: Colors.white, size: 18),
                    label: const Text(
                      'CANCEL',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        fontSize: 12,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            ),
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
                if (cart.isReturnMode)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.assignment_return_rounded, color: AppTheme.danger, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'RETURN MODE ACTIVE',
                          style: TextStyle(
                            color: AppTheme.danger,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      segments: <ButtonSegment<bool>>[
                        ButtonSegment<bool>(
                          value: false,
                          label: const Text('Store Sale'),
                          icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                          enabled: auth.canProcessRetailSales,
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          label: const Text('Clinic Dispense'),
                          icon: const Icon(Icons.medical_services_outlined, size: 16),
                          enabled: auth.canProcessClinicalDispenses,
                        ),
                      ],
                      selected: <bool>{cart.isClinicalDispense},
                      onSelectionChanged: (Set<bool> newSelection) {
                        _handleClinicalDispenseToggle(newSelection.first, cart);
                      },
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        selectedBackgroundColor: AppTheme.primary,
                        selectedForegroundColor: Colors.white,
                        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
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
                            cart.setPatient(name: '', phone: '', id: 0, uhid: '');
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
                    final isClinical = cart.isClinicalDispense;
                    final meds = inv.rawMedicines.where((m) =>
                        (isClinical ? m.getNonExpiredMainStock() > 0 : m.getNonExpiredStoreStock() > 0) &&
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
                                    if (!isProc) ...[
                                      Builder(builder: (ctx) {
                                        final isClinical = cart.isClinicalDispense;
                                         final stock = isClinical ? (item as Medicine).getNonExpiredMainStock() : (item as Medicine).getNonExpiredStoreStock();
                                         final isLow = isClinical ? stock <= (item as Medicine).lowStockThreshold : (item as Medicine).isLowStock;
                                        return Text('Stock: $stock',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: isLow
                                                    ? AppTheme.warning
                                                    : context.textMutedColor));
                                      }),
                                    ],
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
          // 2. Scrollable Middle Area for Cart Items
          Expanded(
            child: cart.items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_basket_outlined,
                            size: 80,
                            color: context.borderColor.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Text('YOUR CART IS EMPTY',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: context.textMutedColor,
                                letterSpacing: 1.5)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    itemCount: cart.items.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: context.borderColor.withValues(alpha: 0.1)),
                    itemBuilder: (ctx, i) {
                      final item = cart.items[i];
                      return _CartItemTile(
                        item: item,
                        onRemove: () => cart.removeItem(item.id, isProcedure: item.isProcedure),
                        onLongPress: () => _showItemContextMenu(item, cart),
                      );
                    },
                  ),
          ),
          // 3. Sticky Bottom Bar
          if (cart.items.isNotEmpty)
            _buildStickyBottomBar(cart),
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
  final VoidCallback onRemove;
  final VoidCallback onLongPress;

  const _CartItemTile({
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
                      _Tag(
                        label: '₹${item.isProcedure ? (item.customPrice ?? item.procedure!.basePrice).toStringAsFixed(0) : item.medicine!.sellingPrice.toStringAsFixed(0)}',
                        color: context.textMutedColor,
                      ),
                      const SizedBox(width: 4),
                      _Tag(
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
