import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/cart_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/prescription_provider.dart';
import '../../shared/providers/patient_provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/models/medicine.dart';
import '../../shared/models/patient.dart';
import '../../shared/models/sale.dart';
import '../../shared/models/procedure.dart';
import '../../shared/providers/opd_provider.dart';
import '../../shared/models/appointment.dart';
import '../../theme/app_theme.dart';
import '../../widgets/medicine_dialog.dart';
import '../../widgets/patient_dialogs.dart';
import '../../widgets/procedure_dialog.dart';
import '../../shared/services/printing_service.dart';
import '../../shared/services/sync_service.dart';
import '../../shared/providers/procedure_provider.dart';

class PosWindows extends StatefulWidget {
  const PosWindows({super.key});

  @override
  State<PosWindows> createState() => _PosWindowsState();
}

class _PosWindowsState extends State<PosWindows> {
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
  final _checkoutFocus = FocusNode();

  // Map of cart items to their quantity FocusNodes
  final Map<String, FocusNode> _qtyFocusNodes = {};
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, FocusNode> _priceFocusNodes = {};
  final Map<String, TextEditingController> _priceControllers = {};

  @override
  void initState() {
    super.initState();
    // Auto-focus search on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocus.requestFocus();
        // Proactive search on start if cart is empty
        final cart = context.read<CartProvider>();
        if (cart.items.isEmpty) {
          _showPatientProactiveSearch();
        }
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
    _checkoutFocus.dispose();
    for (var node in _qtyFocusNodes.values) {
      node.dispose();
    }
    for (var node in _priceFocusNodes.values) {
      node.dispose();
    }
    for (var ctrl in _qtyControllers.values) {
      ctrl.dispose();
    }
    for (var ctrl in _priceControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  // Gets or creates a focus node for a specific cart item's quantity field
  FocusNode _getQtyFocusNode(String key) {
    if (!_qtyFocusNodes.containsKey(key)) {
      final node = FocusNode();
      node.addListener(() {
        if (node.hasFocus && _qtyControllers.containsKey(key)) {
          final ctrl = _qtyControllers[key]!;
          ctrl.selection = TextSelection(
            baseOffset: 0,
            extentOffset: ctrl.text.length,
          );
        }
      });
      _qtyFocusNodes[key] = node;
    }
    return _qtyFocusNodes[key]!;
  }

  TextEditingController _getQtyController(String key, int qty) {
    if (!_qtyControllers.containsKey(key)) {
      _qtyControllers[key] = TextEditingController(text: qty.toString());
    } else {
      // If the user isn't actively typing, sync the controller with the cart state
      if (!_qtyFocusNodes[key]!.hasFocus) {
        _qtyControllers[key]!.text = qty.toString();
      }
    }
    return _qtyControllers[key]!;
  }

  FocusNode _getPriceFocusNode(String key) {
    if (!_priceFocusNodes.containsKey(key)) {
      final node = FocusNode();
      node.addListener(() {
        if (node.hasFocus && _priceControllers.containsKey(key)) {
          final ctrl = _priceControllers[key]!;
          ctrl.selection = TextSelection(
            baseOffset: 0,
            extentOffset: ctrl.text.length,
          );
        }
      });
      _priceFocusNodes[key] = node;
    }
    return _priceFocusNodes[key]!;
  }

  TextEditingController _getPriceController(String key, double price) {
    if (!_priceControllers.containsKey(key)) {
      _priceControllers[key] = TextEditingController(text: price.toStringAsFixed(2));
    } else {
      if (!_priceFocusNodes[key]!.hasFocus) {
        _priceControllers[key]!.text = price.toStringAsFixed(2);
      }
    }
    return _priceControllers[key]!;
  }

  // --- Pipeline Navigation Logic ---

  void _onItemAddedToCart(String key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (key.startsWith('p_')) {
          _getPriceFocusNode(key).requestFocus();
        } else {
          _getQtyFocusNode(key).requestFocus();
        }
      }
    });
  }

  void _onQtyConfirm() {
    // Pipeline Step 4: After Qty is confirmed (Enter), jump to Discount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _discountFocus.requestFocus();
    });
  }

  void _onDiscountConfirm() {
    // Pipeline Step 5: Jump to Payment Method selector
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _paymentFocus.requestFocus();
    });
  }

  void _onPaymentMethodConfirm() {
    // Pipeline Step 6: Jump to Split text fields OR trigger Checkout immediately
    if (_paymentMethod == 'mixed') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mixCashFocus.requestFocus();
      });
    } else {
      final cart = context.read<CartProvider>();
      if (cart.items.isNotEmpty) {
        _doCheckout(cart);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final cart = context.watch<CartProvider>();
    final auth = context.watch<AuthProvider>();
    final isWide = MediaQuery.of(context).size.width > 800;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.tab): () {
          if (mounted) {
            _searchFocus.requestFocus();
            _searchCtrl.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _searchCtrl.text.length,
            );
          }
        },
        const SingleActivator(LogicalKeyboardKey.f4): () => _handleHoldCart(),
        const SingleActivator(LogicalKeyboardKey.f8): () =>
            _showPendingCartsDialog(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Text('Point of Sale'),
                if (cart.isReturnMode) ...[
                  const SizedBox(width: 20),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.danger,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'RETURN MODE ACTIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(width: 24),
                  SegmentedButton<bool>(
                    segments: <ButtonSegment<bool>>[
                      ButtonSegment<bool>(
                        value: false,
                        label: const Text('Store Sale'),
                        icon: const Icon(Icons.shopping_bag_outlined),
                        enabled: auth.canProcessRetailSales,
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: const Text('Clinic Dispense'),
                        icon: const Icon(Icons.medical_services_outlined),
                        enabled: auth.canProcessClinicalDispenses,
                      ),
                    ],
                    selected: <bool>{cart.isClinicalDispense},
                    onSelectionChanged: (Set<bool> newSelection) {
                      _handleClinicalDispenseToggle(newSelection.first, cart);
                    },
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      selectedBackgroundColor: Theme.of(context).colorScheme.primary,
                      selectedForegroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              Row(
                children: [
                  Switch(
                    value: cart.isReturnMode,
                    onChanged: (_) => cart.toggleReturnMode(),
                    activeThumbColor: AppTheme.danger,
                  ),
                ],
              ),
              const SizedBox(width: 8),
              if (cart.items.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(
                    Icons.delete_sweep,
                    color: AppTheme.danger,
                  ),
                  label: const Text(
                    'Clear',
                    style: TextStyle(
                      color: AppTheme.danger,
                    ),
                  ),
                  onPressed: _handleManualClear,
                ),
              const SizedBox(width: 8),
              if (cart.items.isNotEmpty)
                IconButton(
                  icon: const Icon(
                    Icons.pause_circle_outline,
                  ),
                  tooltip: 'Hold Cart [F4]',
                  onPressed: _handleHoldCart,
                ),
              Badge(
                label: Text(cart.pendingCarts.length.toString()),
                isLabelVisible: cart.pendingCarts.isNotEmpty,
                child: IconButton(
                  icon: const Icon(
                    Icons.history_outlined,
                  ),
                  tooltip: 'Pending Carts [F8]',
                  onPressed: _showPendingCartsDialog,
                ),
              ),
              const SizedBox(width: 12),
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
                        Row(
                          children: [
                            const Icon(Icons.edit_document, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'EDITING SALE: ${cart.editingInvoiceNo} — CHANGES WILL OVERWRITE THE ORIGINAL RECORD',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () {
                            cart.clearCart();
                            _syncControllersWithCart();
                          },
                          icon: const Icon(Icons.cancel_outlined, color: Colors.white, size: 18),
                          label: const Text(
                            'CANCEL EDIT',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.15),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!cart.isClinicalDispense && !cart.isReturnMode)
                  Container(
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: const Center(
                      child: Text(
                        'STORE SALE MODE ACTIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                if (cart.isClinicalDispense && !cart.isReturnMode)
                  Container(
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: const Center(
                      child: Text(
                        'CLINICAL DISPENSE MODE ACTIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                if (cart.isReturnMode)
                  Container(
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: const Center(
                      child: Text(
                        'RETURN / REFUND MODE ACTIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: isWide
                      ? Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: _MedicinesGrid(
                                inv: inv,
                                cart: cart,
                                searchCtrl: _searchCtrl,
                                searchFocus: _searchFocus,
                                onFirstGridFocusNodeCreated: (node) {
                                  // Empty callback to satisfy the parameter if we decide to use it later
                                },
                                onSearchEnter: () {
                                  if (mounted) _discountFocus.requestFocus();
                                },
                                onAddToGrid: (medicine) {
                                  cart.addItem(medicine);
                                  _onItemAddedToCart('m_${medicine.id}');
                                },
                                onItemAddedToCart: _onItemAddedToCart,
                                onScanTap: _showScannerDialog,
                              ),
                            ),
                            Container(width: 1, color: context.borderColor),
                            SizedBox(
                              width: 360,
                              child: _CartPanel(
                                cart: cart,
                                discountCtrl: _discountCtrl,
                                patientCtrl: _patientCtrl,
                                mixCashCtrl: _mixCashCtrl,
                                mixUpiCtrl: _mixUpiCtrl,
                                mixCardCtrl: _mixCardCtrl,
                                discountFocus: _discountFocus,
                                paymentFocus: _paymentFocus,
                                mixCashFocus: _mixCashFocus,
                                mixUpiFocus: _mixUpiFocus,
                                mixCardFocus: _mixCardFocus,
                                checkoutFocus: _checkoutFocus,
                                paymentMethod: _paymentMethod,
                                getQtyFocusNode: _getQtyFocusNode,
                                getQtyController: _getQtyController,
                                getPriceFocusNode: _getPriceFocusNode,
                                getPriceController: _getPriceController,
                                onQtyConfirm: _onQtyConfirm,
                                onPriceConfirm: _onQtyConfirm,
                                onDiscountConfirm: _onDiscountConfirm,
                                onPaymentMethodConfirm: _onPaymentMethodConfirm,
                                onPaymentMethodChanged: (v) =>
                                    setState(() => _paymentMethod = v),
                                onLoadPrescription: () =>
                                    _showPrescriptionLoader(context),
                                onImportPreviousSales: () =>
                                    _showImportPreviousSalesDialog(context, cart),
                                onCheckout: () => _doCheckout(cart),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: _MedicinesGrid(
                                inv: inv,
                                cart: cart,
                                searchCtrl: _searchCtrl,
                                searchFocus: _searchFocus,
                                onFirstGridFocusNodeCreated: (node) {
                                  // Empty callback
                                },
                                onSearchEnter: () {
                                  if (mounted) _discountFocus.requestFocus();
                                },
                                onAddToGrid: (medicine) {
                                  cart.addItem(medicine);
                                  _onItemAddedToCart('m_${medicine.id}');
                                },
                                onItemAddedToCart: _onItemAddedToCart,
                                onScanTap: _showScannerDialog,
                              ),
                            ),
                            Container(height: 1, color: context.borderColor),
                            Expanded(
                              child: _CartPanel(
                                cart: cart,
                                discountCtrl: _discountCtrl,
                                patientCtrl: _patientCtrl,
                                mixCashCtrl: _mixCashCtrl,
                                mixUpiCtrl: _mixUpiCtrl,
                                mixCardCtrl: _mixCardCtrl,
                                discountFocus: _discountFocus,
                                paymentFocus: _paymentFocus,
                                mixCashFocus: _mixCashFocus,
                                mixUpiFocus: _mixUpiFocus,
                                mixCardFocus: _mixCardFocus,
                                checkoutFocus: _checkoutFocus,
                                paymentMethod: _paymentMethod,
                                getQtyFocusNode: _getQtyFocusNode,
                                getQtyController: _getQtyController,
                                getPriceFocusNode: _getPriceFocusNode,
                                getPriceController: _getPriceController,
                                onQtyConfirm: _onQtyConfirm,
                                onPriceConfirm: _onQtyConfirm,
                                onDiscountConfirm: _onDiscountConfirm,
                                onPaymentMethodConfirm: _onPaymentMethodConfirm,
                                onPaymentMethodChanged: (v) =>
                                    setState(() => _paymentMethod = v),
                                onLoadPrescription: () =>
                                    _showPrescriptionLoader(context),
                                onImportPreviousSales: () =>
                                    _showImportPreviousSalesDialog(context, cart),
                                onCheckout: () => _doCheckout(cart),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
        ),
      ),
    );
  }

  void _handleClinicalDispenseToggle(bool val, CartProvider cart) {
    if (!val) {
      cart.setClinicalDispense(false);
      return;
    }
    
    // Attempting to turn ON Clinical Dispense
    // Enforce selection of a patient from today's queue
    final opd = context.read<OpdProvider>();
    final activeAppts = opd.todayQueue;
    
    if (activeAppts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No appointments found in today\'s OPD queue. Clinical Dispense requires a patient in the OPD queue.'),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Appointment for Clinical Dispense'),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: activeAppts.length,
            itemBuilder: (c, i) {
              final a = activeAppts[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withOpacity(0.1),
                  child: Text('#${a.tokenNumber}',
                      style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
                title: Text(a.patientName),
                subtitle: Text('Status: ${a.status} • Dr. ${a.doctorName}'),
                onTap: () {
                  final patient = context.read<PatientProvider>().getById(a.patientId);
                  cart.setPatient(name: a.patientName, phone: a.patientPhone, id: a.patientId, uhid: patient?.uhid);
                  _patientCtrl.text = a.patientName;
                  cart.setLinkedAppointment(a.id);
                  cart.setClinicalDispense(true);
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _doCheckout(CartProvider cart) async {
    final pName = _patientCtrl.text.trim();
    if (cart.isClinicalDispense) {
      if (cart.patientId == 0 || pName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Registered patient is strictly required for Clinical Dispense Mode!'),
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

    final sale = await cart.checkout(context.read<SyncService>());
    if (!context.mounted) return;

    if (sale != null) {
      // Reset mixed controllers
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

      // Trigger Print Preview (Wait for it to close)
      await PrintingService.instance.printSaleAsInvoice(context, sale);

      // Proactive Search for next sale
      _showPatientProactiveSearch();

      // Return focus to search for the next rapid transaction
      _searchFocus.requestFocus();
    }
  }

  void _handleManualClear() {
    final cart = context.read<CartProvider>();
    cart.clearCart();
    _patientCtrl.clear();
    _discountCtrl.clear();
    _showPatientProactiveSearch();
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
    _searchFocus.requestFocus();
  }

  void _handleHoldCart() {
    final cart = context.read<CartProvider>();
    if (cart.items.isEmpty) return;

    // Sync current UI values to provider before holding
    cart.setPatient(name: _patientCtrl.text.trim(), id: cart.patientId, phone: cart.patientPhone, uhid: cart.patientUhid);
    cart.setDiscount(double.tryParse(_discountCtrl.text) ?? 0);
    cart.setPaymentMethod(_paymentMethod);
    if (_paymentMethod == 'mixed') {
      cart.setMixedAmounts(
        double.tryParse(_mixCashCtrl.text) ?? 0,
        double.tryParse(_mixUpiCtrl.text) ?? 0,
        double.tryParse(_mixCardCtrl.text) ?? 0,
      );
    }

    cart.holdCurrentCart();
    _syncControllersWithCart();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Cart put on hold'),
        backgroundColor: AppTheme.primary,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _showPendingCartsDialog() {
    final cart = context.read<CartProvider>();
    if (cart.pendingCarts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending carts available.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.history, color: AppTheme.primary),
                SizedBox(width: 8),
                Text('Pending Carts'),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Select a cart to restore or discard',
                    style:
                        TextStyle(color: context.textMutedColor, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  if (cart.pendingCarts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No more pending carts.'),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: cart.pendingCarts.length,
                        itemBuilder: (_, i) {
                          final pc = cart.pendingCarts[i];
                          final timeAgo = DateTime.now().difference(pc.heldAt);
                          final timeStr = timeAgo.inMinutes > 0
                              ? '${timeAgo.inMinutes}m ago'
                              : 'Just now';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(
                                pc.patientName.isEmpty
                                    ? 'Walk-in Customer'
                                    : pc.patientName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                '${pc.items.length} items • Total: ₹${pc.total.toStringAsFixed(2)} • $timeStr',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: AppTheme.danger),
                                    onPressed: () {
                                      cart.deletePendingCart(pc);
                                      if (cart.pendingCarts.isEmpty) {
                                        Navigator.pop(ctx);
                                      } else {
                                        setDialogState(() {});
                                      }
                                    },
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      cart.restoreCart(pc);
                                      _syncControllersWithCart();
                                    },
                                    child: const Text('Restore'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPatientProactiveSearch() {
    final cart = context.read<CartProvider>();
    showDialog(
      context: context,
      builder: (ctx) => PatientSearchDialog(
        limitToTodayOpd: cart.isClinicalDispense,
        onSelected: (p) {
          cart.setPatient(name: p.name, phone: p.phone, id: p.id, uhid: p.uhid);
          _patientCtrl.text = p.name;
          _searchFocus.requestFocus();
        },
        onAppointmentSelected: (Appointment appt) {
          final patient = context.read<PatientProvider>().getById(appt.patientId);
          cart.setPatient(name: appt.patientName, phone: appt.patientPhone, id: appt.patientId, uhid: patient?.uhid);
          _patientCtrl.text = appt.patientName;
          cart.setLinkedAppointment(appt.id);
          _searchFocus.requestFocus();
        },
      ),
    );
  }

  void _showPrescriptionLoader(BuildContext context) {
    // Explicitly import if needed, but here it's already in the provider's context
    final pProvider = context.read<PrescriptionProvider>();
    pProvider.load();
    final pending = pProvider.pendingDispensation;

    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending prescriptions for today.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.receipt_long, color: AppTheme.primary),
            SizedBox(width: 8),
            Text('Load Prescription'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Today\'s pending prescriptions',
                style: TextStyle(color: context.textMutedColor, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: pending.length,
                  itemBuilder: (_, i) {
                    final p = pending[i];
                    return ListTile(
                      title: Text(
                        p.patientName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('Dr. ${p.doctorName}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(ctx);
                        _loadPrescriptionIntoCart(context, p);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _loadPrescriptionIntoCart(BuildContext context, dynamic prescription) {
    final cart = context.read<CartProvider>();
    final inv = context.read<InventoryProvider>();
    final pProvider = context.read<PrescriptionProvider>();

    cart.clearCart();
    cart.setClinicalDispense(true);
    if (prescription.appointmentId != 0) {
      cart.setLinkedAppointment(prescription.appointmentId);
    }
    final patientProv = context.read<PatientProvider>();
    final patient = patientProv.getById(prescription.patientId);
    cart.setPatient(
      name: prescription.patientName,
      phone: patient?.phone ?? '',
      id: prescription.patientId,
      uhid: patient?.uhid ?? '',
    );
    cart.setLinkedPrescription(prescription.id);

    final items = pProvider.getItems(prescription);
    int foundCount = 0;

    for (final pItem in items) {
      // Find matching medicine in inventory by exact Name (IDs differ between synced client devices)
      final medicine = inv.medicines
          .where(
            (m) => m.name.toLowerCase() == pItem.medicineName.toLowerCase(),
          )
          .firstOrNull;

      if (medicine != null) {
        cart.addItem(medicine, qty: pItem.qty);
        foundCount++;
      }
    }

    // Load procedures
    final procProv = context.read<ProcedureProvider>();
    final procedures = pProvider.getProcedures(prescription);
    for (final pName in procedures) {
      final proc = procProv.procedures.where((p) => p.name.toLowerCase() == pName.toLowerCase()).firstOrNull;
      if (proc != null) {
        cart.addProcedure(proc);
        foundCount++;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Loaded $foundCount items from ${prescription.patientName}\'s prescription.',
        ),
        backgroundColor: AppTheme.success,
      ),
    );

    // Update the controller in parent state
    _patientCtrl.text = prescription.patientName;
  }

  void _showImportPreviousSalesDialog(BuildContext context, CartProvider cart) {
    final salesProv = context.read<SalesProvider>();
    final patientProv = context.read<PatientProvider>();

    final patient = patientProv.patients.where((p) => p.id == cart.patientId).firstOrNull;
    if (patient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected patient details not found in database.')),
      );
      return;
    }

    final previousSales = salesProv.getSalesForPatient(patient);
    if (previousSales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No previous sales found for ${patient.name}.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.restore_page, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text('Import Previous Sale for ${patient.name}'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select a previous transaction to load items into the cart:',
                style: TextStyle(color: context.textMutedColor, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: previousSales.length,
                  itemBuilder: (_, i) {
                    final sale = previousSales[i];
                    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(sale.createdAt);
                    final items = salesProv.getSaleItems(sale);
                    final itemsSummary = items.map((e) => '${e.qty}x ${e.medicineName}').join(', ');

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          '${sale.invoiceNo} • ₹${sale.total.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dateStr, style: const TextStyle(fontSize: 11)),
                            const SizedBox(height: 4),
                            Text(
                              itemsSummary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: context.textMutedColor, fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(ctx);
                          _importSaleItemsIntoCart(context, cart, sale, items);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _importSaleItemsIntoCart(BuildContext context, CartProvider cart, Sale sale, List<SaleItem> saleItems) {
    final inv = context.read<InventoryProvider>();

    final currentPatientId = cart.patientId;
    final currentPatientName = cart.patientName;
    final currentPatientPhone = cart.patientPhone;
    final currentPatientUhid = cart.patientUhid;
    final currentIsClinicalDispense = cart.isClinicalDispense;

    cart.clearCart();
    cart.setPatient(id: currentPatientId, name: currentPatientName, phone: currentPatientPhone, uhid: currentPatientUhid);
    cart.setClinicalDispense(currentIsClinicalDispense);

    int loadedCount = 0;
    for (final sItem in saleItems) {
      if (sItem.isProcedure) {
        final procProv = context.read<ProcedureProvider>();
        final proc = procProv.procedures.where((p) => p.id == sItem.procedureId || p.name.toLowerCase() == sItem.medicineName.toLowerCase()).firstOrNull;
        if (proc != null) {
          cart.addProcedure(proc, price: sItem.unitPrice, qty: sItem.qty);
          loadedCount++;
        }
      } else {
        final medicine = inv.medicines.where((m) => m.id == sItem.medicineId || m.name.toLowerCase() == sItem.medicineName.toLowerCase()).firstOrNull;
        if (medicine != null) {
          cart.addItem(medicine, qty: sItem.qty);
          loadedCount++;
        }
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Successfully imported $loadedCount items from previous sale ${sale.invoiceNo}.'),
        backgroundColor: AppTheme.success,
      ),
    );
  }

  void _showScannerDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scan Barcode'),
        content: SizedBox(
          width: 300,
          height: 300,
          child: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  final code = barcode.rawValue!;
                  Navigator.pop(ctx);
                  _handleBarcodeScanned(code);
                  break;
                }
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _handleBarcodeScanned(String code) {
    final inv = context.read<InventoryProvider>();
    final cart = context.read<CartProvider>();

    // Try to find exact match by barcode
    final medicines = inv.medicines.where((m) => m.barcode == code).toList();

    if (medicines.isNotEmpty) {
      final match = medicines.first;
      cart.addItem(match);
      _onItemAddedToCart('m_${match.id}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Added ${match.name}'),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 1),
        ),
      );
    } else {
      // If no exact match, set search text
      _searchCtrl.text = code;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No item found with barcode: $code'),
          backgroundColor: AppTheme.warning,
        ),
      );
    }
  }
}

class _MedicinesGrid extends StatefulWidget {
  final InventoryProvider inv;
  final CartProvider cart;
  final TextEditingController searchCtrl;
  final FocusNode searchFocus;
  final VoidCallback onSearchEnter;
  final ValueChanged<FocusNode> onFirstGridFocusNodeCreated;
  final Function(Medicine) onAddToGrid;
  final Function(String) onItemAddedToCart;
  final VoidCallback onScanTap;

  const _MedicinesGrid({
    required this.inv,
    required this.cart,
    required this.searchCtrl,
    required this.searchFocus,
    required this.onSearchEnter,
    required this.onFirstGridFocusNodeCreated,
    required this.onAddToGrid,
    required this.onItemAddedToCart,
    required this.onScanTap,
  });

  @override
  State<_MedicinesGrid> createState() => _MedicinesGridState();
}

class _MedicinesGridState extends State<_MedicinesGrid> {
  // Map of Grid Item ID -> FocusNode (for keyboard navigation in the grid)
  final Map<String, FocusNode> _gridFocusNodes = {};

  @override
  void dispose() {
    for (var node in _gridFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _getGridFocusNode(String key, bool isFirst) {
    if (!_gridFocusNodes.containsKey(key)) {
      final node = FocusNode();
      _gridFocusNodes[key] = node;
      if (isFirst) {
        widget.onFirstGridFocusNodeCreated(node);
      }
    }
    return _gridFocusNodes[key]!;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final procProv = context.watch<ProcedureProvider>();
    final query = widget.searchCtrl.text.toLowerCase();

    final isClinical = widget.cart.isClinicalDispense;
    final medicines = widget.inv.medicines
        .where((m) => isClinical ? m.mainStock > 0 : m.storeStock > 0)
        .where(
          (m) =>
              query.isEmpty ||
              m.name.toLowerCase().contains(query) ||
              m.barcode.contains(query),
        )
        .toList();

    final procedures = procProv.procedures
        .where((p) => query.isEmpty || p.name.toLowerCase().contains(query))
        .toList();

    final List<dynamic> combined = [...medicines, ...procedures];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        // Pipeline Step 1: User presses Down Arrow in search -> Focus First Grid Item
                        if (combined.isNotEmpty) {
                          final first = combined.first;
                          final key = first is Medicine
                              ? 'm_${first.id}'
                              : 'p_${first.id}';
                          _getGridFocusNode(
                            key,
                            true,
                          ).requestFocus();
                        }
                      }
                    }
                  },
                  child: TextField(
                    controller: widget.searchCtrl,
                    focusNode: widget.searchFocus,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => widget.onSearchEnter(),
                    decoration: const InputDecoration(
                      hintText:
                          'Search medicine [Down for list, Enter to Checkout]...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!kIsWeb && !Platform.isWindows) ...[
                IconButton(
                  icon: Icon(
                    Icons.qr_code_scanner,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  tooltip: 'Scan Barcode',
                  onPressed: widget.onScanTap,
                ),
                const SizedBox(width: 4),
              ],
              if (auth.hasInventoryWriteAccess) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.person_add_alt_1,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  tooltip: 'Add Patient to OPD',
                  onPressed: () => _showPatientQueueDialog(context),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.auto_awesome_motion,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  tooltip: 'Quick Add Procedure',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const ProcedureDialog(),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Calculate crossAxisCount based on SliverGridDelegateWithMaxCrossAxisExtent logic
              final int crossAxisCount =
                  (constraints.maxWidth / (180 + 12)).floor().clamp(1, 10);

              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: combined.length,
                itemBuilder: (ctx, i) {
                  final item = combined[i];
                  final isProcedure = item is Procedure;
                  final key = isProcedure ? 'p_${item.id}' : 'm_${item.id}';
                  final focusNode = _getGridFocusNode(key, i == 0);

                  return Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                          final nextIdx = (i + 1) % combined.length;
                          final nextItem = combined[nextIdx];
                          final nextKey = nextItem is Procedure
                              ? 'p_${nextItem.id}'
                              : 'm_${nextItem.id}';
                          _getGridFocusNode(nextKey, false).requestFocus();
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.arrowLeft) {
                          final prevIdx =
                              (i - 1 + combined.length) % combined.length;
                          final prevItem = combined[prevIdx];
                          final prevKey = prevItem is Procedure
                              ? 'p_${prevItem.id}'
                              : 'm_${prevItem.id}';
                          _getGridFocusNode(prevKey, false).requestFocus();
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.arrowDown) {
                          final nextIdx = i + crossAxisCount;
                          if (nextIdx < combined.length) {
                            final nextItem = combined[nextIdx];
                            final nextKey = nextItem is Procedure
                                ? 'p_${nextItem.id}'
                                : 'm_${nextItem.id}';
                            _getGridFocusNode(nextKey, false).requestFocus();
                          } else {
                            final topIdx = i % crossAxisCount;
                            final topItem = combined[topIdx];
                            final topKey = topItem is Procedure
                                ? 'p_${topItem.id}'
                                : 'm_${topItem.id}';
                            _getGridFocusNode(topKey, false).requestFocus();
                          }
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.arrowUp) {
                          final prevIdx = i - crossAxisCount;
                          if (prevIdx >= 0) {
                            final prevItem = combined[prevIdx];
                            final prevKey = prevItem is Procedure
                                ? 'p_${prevItem.id}'
                                : 'm_${prevItem.id}';
                            _getGridFocusNode(prevKey, false).requestFocus();
                          } else {
                            int lastVisibleIdx = i;
                            while (lastVisibleIdx + crossAxisCount <
                                combined.length) {
                              lastVisibleIdx += crossAxisCount;
                            }
                            final lastItem = combined[lastVisibleIdx];
                            final lastKey = lastItem is Procedure
                                ? 'p_${lastItem.id}'
                                : 'm_${lastItem.id}';
                            _getGridFocusNode(lastKey, false).requestFocus();
                          }
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: _ProductCard(
                      item: item,
                      focusNode: focusNode,
                      onTap: () {
                        if (isProcedure) {
                          widget.cart.addProcedure(item);
                          widget.onItemAddedToCart(key);
                        } else {
                          widget.onAddToGrid(item);
                        }
                      },
                      onSecondaryTap: isProcedure
                          ? (details) =>
                              _showProcedureContextMenu(context, details, item)
                          : null,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showPatientQueueDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading:
                const Icon(Icons.app_registration, color: AppTheme.primary),
            title: const Text('Register New Patient'),
            subtitle: const Text('For first-time clinic visit'),
            onTap: () async {
              Navigator.pop(ctx);
              final patient = await showDialog<Patient>(
                context: context,
                builder: (ctx) => const PatientDialog(),
              );
              if (patient != null && context.mounted) {
                _showBookingDialog(context, patient);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_search, color: AppTheme.primary),
            title: const Text('Existing Patient'),
            subtitle: const Text('Search by name, phone or UHID'),
            onTap: () {
              Navigator.pop(ctx);
              showDialog(
                context: context,
                builder: (ctx) => PatientSearchDialog(
                  showSkip: false,
                  onSelected: (p) => _showBookingDialog(context, p),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showBookingDialog(BuildContext context, Patient patient) {
    showDialog(
      context: context,
      builder: (ctx) => BookAppointmentDialog(patient: patient),
    );
  }

  void _showProcedureContextMenu(
      BuildContext context, TapDownDetails details, Procedure procedure) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          child: const ListTile(
            leading: Icon(Icons.edit, color: AppTheme.primary),
            title: Text('Edit Procedure'),
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              showDialog(
                context: context,
                builder: (_) => ProcedureDialog(procedure: procedure),
              );
            });
          },
        ),
        PopupMenuItem(
          child: const ListTile(
            leading: Icon(Icons.delete, color: AppTheme.danger),
            title: Text('Delete Procedure'),
          ),
          onTap: () {
            _confirmDeleteProcedure(context, procedure);
          },
        ),
      ],
    );
  }

  void _confirmDeleteProcedure(BuildContext context, Procedure p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Procedure'),
        content: Text('Are you sure you want to delete "${p.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              context.read<ProcedureProvider>().deleteProcedure(p.id,
                  syncService: context.read<SyncService>());
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final dynamic item;
  final VoidCallback onTap;
  final FocusNode focusNode;

  final void Function(TapDownDetails)? onSecondaryTap;

  const _ProductCard({
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
                        '${cart.isClinicalDispense ? item.mainStock : item.storeStock}',
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

class _CartPanel extends StatelessWidget {
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
  final VoidCallback onCheckout;

  const _CartPanel({
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
                      if (val.text.isEmpty) return const Iterable.empty();
                      final patients = context.read<PatientProvider>().patients;
                      return patients.where((p) {
                        final q = val.text.toLowerCase();
                        return p.name.toLowerCase().contains(q) ||
                            p.phone.contains(q) ||
                            p.address.toLowerCase().contains(q);
                      });
                    },
                    onSelected: (p) {
                      cart.setPatient(name: p.name, phone: p.phone, id: p.id, uhid: p.uhid);
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
                      if (patientCtrl.text != ctrl.text &&
                          !node.hasFocus) {
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
                                return ListTile(
                                  title: Text(p.name),
                                  subtitle: Text('${p.uhid} • ${p.phone} • ${p.address}'),
                                  onTap: () => onSelected(p),
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
                        title: Text(
                          item.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
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
                                final maxStock = cart.isClinicalDispense ? item.medicine!.mainStock : item.medicine!.storeStock;
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
                        _PayChip(
                          'cash',
                          'Cash',
                          paymentMethod,
                          onPaymentMethodChanged,
                          paymentFocus,
                        ),
                        const SizedBox(width: 8),
                        _PayChip(
                          'card',
                          'Card',
                          paymentMethod,
                          onPaymentMethodChanged,
                          paymentFocus,
                        ),
                        const SizedBox(width: 8),
                        _PayChip(
                          'upi',
                          'UPI',
                          paymentMethod,
                          onPaymentMethodChanged,
                          paymentFocus,
                        ),
                        const SizedBox(width: 8),
                        _PayChip(
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
                        child: _MixedField(
                          label: 'Cash',
                          controller: mixCashCtrl,
                          focusNode: mixCashFocus,
                          onSubmitted: () => mixUpiFocus.requestFocus(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MixedField(
                          label: 'UPI',
                          controller: mixUpiCtrl,
                          focusNode: mixUpiFocus,
                          onSubmitted: () => mixCardFocus.requestFocus(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MixedField(
                          label: 'Card',
                          controller: mixCardCtrl,
                          focusNode: mixCardFocus,
                          onSubmitted: () => onCheckout(),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),

                // Totals
                _TotalRow('Subtotal', '₹${cart.subtotal.toStringAsFixed(2)}'),
                if (cart.discountAmount > 0)
                  _TotalRow(
                    'Discount',
                    '-₹${cart.discountAmount.toStringAsFixed(2)}',
                    color: AppTheme.danger,
                  ),
                if (cart.taxAmount > 0)
                  _TotalRow('Tax', '₹${cart.taxAmount.toStringAsFixed(2)}'),
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

class _PayChip extends StatelessWidget {
  final String value;
  final String label;
  final String selected;
  final ValueChanged<String> onChanged;
  final FocusNode? primaryFocusNode;

  const _PayChip(
    this.value,
    this.label,
    this.selected,
    this.onChanged,
    this.primaryFocusNode,
  );

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

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _TotalRow(this.label, this.value, {this.color});

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
