import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/cart_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/prescription_provider.dart';
import '../../shared/providers/patient_provider.dart';
import '../../shared/models/medicine.dart';
import '../../shared/models/patient.dart';
import '../../theme/app_theme.dart';
import '../../widgets/medicine_dialog.dart';
import '../../widgets/patient_dialogs.dart';
import '../../shared/services/printing_service.dart';
import '../../shared/services/sync_service.dart';

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
  final Map<int, FocusNode> _qtyFocusNodes = {};
  final Map<int, TextEditingController> _qtyControllers = {};

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
    for (var ctrl in _qtyControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  // Gets or creates a focus node for a specific cart item's quantity field
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
      // If the user isn't actively typing, sync the controller with the cart state
      if (!_qtyFocusNodes[medicineId]!.hasFocus) {
        _qtyControllers[medicineId]!.text = qty.toString();
      }
    }
    return _qtyControllers[medicineId]!;
  }

  // --- Pipeline Navigation Logic ---

  void _onMedicineAddedToCart(int medicineId) {
    // Pipeline Step 3: When an item is added, focus its Qty field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _getQtyFocusNode(medicineId).requestFocus();
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
          backgroundColor: cart.isReturnMode
              ? AppTheme.danger.withValues(alpha: 0.05)
              : null,
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'RETURN MODE ACTIVE',
                      style: TextStyle(
                        color: AppTheme.danger,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            backgroundColor: cart.isReturnMode ? AppTheme.danger : null,
            foregroundColor: cart.isReturnMode ? Colors.white : null,
            actions: [
              Row(
                children: [
                  Switch(
                    value: cart.isReturnMode,
                    onChanged: (_) => cart.toggleReturnMode(),
                    activeThumbColor: AppTheme.danger,
                    activeTrackColor: Colors.white,
                  ),
                ],
              ),
              const SizedBox(width: 8),
              if (cart.items.isNotEmpty)
                TextButton.icon(
                  icon: Icon(
                    Icons.delete_sweep,
                    color: cart.isReturnMode ? Colors.white : AppTheme.danger,
                  ),
                  label: Text(
                    'Clear',
                    style: TextStyle(
                      color: cart.isReturnMode ? Colors.white : AppTheme.danger,
                    ),
                  ),
                  onPressed: _handleManualClear,
                ),
              const SizedBox(width: 8),
              if (cart.items.isNotEmpty)
                IconButton(
                  icon: Icon(
                    Icons.pause_circle_outline,
                    color: cart.isReturnMode
                        ? Colors.white
                        : AppTheme.primaryLight,
                  ),
                  tooltip: 'Hold Cart [F4]',
                  onPressed: _handleHoldCart,
                ),
              Badge(
                label: Text(cart.pendingCarts.length.toString()),
                isLabelVisible: cart.pendingCarts.isNotEmpty,
                child: IconButton(
                  icon: Icon(
                    Icons.history_outlined,
                    color: cart.isReturnMode
                        ? Colors.white
                        : AppTheme.primaryLight,
                  ),
                  tooltip: 'Pending Carts [F8]',
                  onPressed: _showPendingCartsDialog,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: Container(
            decoration: BoxDecoration(
              border: cart.isReturnMode
                  ? Border.all(color: AppTheme.danger, width: 4)
                  : null,
            ),
            child: Column(
              children: [
                if (cart.isReturnMode)
                  Container(
                    width: double.infinity,
                    color: AppTheme.danger,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: const Center(
                      child: Text(
                        'YOU ARE CURRENTLY IN RETURN / REFUND MODE',
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
                                  _onMedicineAddedToCart(medicine.id);
                                },
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
                                onQtyConfirm: _onQtyConfirm,
                                onDiscountConfirm: _onDiscountConfirm,
                                onPaymentMethodConfirm: _onPaymentMethodConfirm,
                                onPaymentMethodChanged: (v) =>
                                    setState(() => _paymentMethod = v),
                                onLoadPrescription: () =>
                                    _showPrescriptionLoader(context),
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
                                  _onMedicineAddedToCart(medicine.id);
                                },
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
                                onQtyConfirm: _onQtyConfirm,
                                onDiscountConfirm: _onDiscountConfirm,
                                onPaymentMethodConfirm: _onPaymentMethodConfirm,
                                onPaymentMethodChanged: (v) =>
                                    setState(() => _paymentMethod = v),
                                onLoadPrescription: () =>
                                    _showPrescriptionLoader(context),
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
      ),
    );
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
      // Reset mixed controllers
      _mixCashCtrl.text = '0';
      _mixUpiCtrl.text = '0';
      _mixCardCtrl.text = '0';
      _discountCtrl.clear();
      _searchCtrl.clear();

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
      await PrintingService.instance.printReceipt(context, sale);

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
    cart.setPatient(name: _patientCtrl.text.trim(), id: cart.patientId);
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
    showDialog(
      context: context,
      builder: (ctx) => PatientSearchDialog(
        onSelected: (p) {
          final cart = context.read<CartProvider>();
          cart.setPatient(name: p.name, phone: p.phone, id: p.id);
          _patientCtrl.text = p.name;
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
    cart.setPatient(
      name: prescription.patientName,
      phone: '', // Can be improved if prescription has phone
      id: prescription.patientId,
    );
    cart.setLinkedPrescription(prescription.id);

    final items = pProvider.getItems(prescription);
    int foundCount = 0;

    for (final pItem in items) {
      // Find matching medicine in inventory by ID or exact Name
      final medicine = inv.medicines
          .where(
            (m) =>
                m.id == pItem.medicineId ||
                m.name.toLowerCase() == pItem.medicineName.toLowerCase(),
          )
          .firstOrNull;

      if (medicine != null) {
        cart.addItem(medicine, qty: pItem.qty);
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
      final m = medicines.first;
      if (m.storeStock > 0) {
        cart.addItem(m);
        _onMedicineAddedToCart(m.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Added ${m.name}'),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 1),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${m.name} is out of stock'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
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
  final ValueChanged<Medicine> onAddToGrid;
  final VoidCallback onScanTap;

  const _MedicinesGrid({
    required this.inv,
    required this.cart,
    required this.searchCtrl,
    required this.searchFocus,
    required this.onSearchEnter,
    required this.onFirstGridFocusNodeCreated,
    required this.onAddToGrid,
    required this.onScanTap,
  });

  @override
  State<_MedicinesGrid> createState() => _MedicinesGridState();
}

class _MedicinesGridState extends State<_MedicinesGrid> {
  // Map of Grid Medicine ID -> FocusNode (for keyboard navigation in the grid)
  final Map<int, FocusNode> _gridFocusNodes = {};

  @override
  void dispose() {
    for (var node in _gridFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _getGridFocusNode(int medicineId, bool isFirst) {
    if (!_gridFocusNodes.containsKey(medicineId)) {
      final node = FocusNode();
      _gridFocusNodes[medicineId] = node;
      if (isFirst) {
        widget.onFirstGridFocusNodeCreated(node);
      }
    }
    return _gridFocusNodes[medicineId]!;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final medicines = widget.inv.medicines
        .where((m) => m.storeStock > 0)
        .where(
          (m) =>
              widget.searchCtrl.text.isEmpty ||
              m.name.toLowerCase().contains(
                    widget.searchCtrl.text.toLowerCase(),
                  ) ||
              m.barcode.contains(widget.searchCtrl.text),
        )
        .toList();

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
                        if (medicines.isNotEmpty) {
                          _getGridFocusNode(
                            medicines.first.id,
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
                    color: widget.cart.isReturnMode
                        ? AppTheme.danger
                        : AppTheme.primaryLight,
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
                    Icons.add_box,
                    color: widget.cart.isReturnMode
                        ? AppTheme.danger
                        : AppTheme.primaryLight,
                    size: 28,
                  ),
                  tooltip: 'Quick Add Medicine',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const MedicineDialog(),
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
                itemCount: medicines.length,
                itemBuilder: (ctx, i) {
                  final m = medicines[i];
                  final focusNode = _getGridFocusNode(m.id, i == 0);
                  return Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                          final nextIdx = (i + 1) % medicines.length;
                          _getGridFocusNode(medicines[nextIdx].id, false)
                              .requestFocus();
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.arrowLeft) {
                          final prevIdx =
                              (i - 1 + medicines.length) % medicines.length;
                          _getGridFocusNode(medicines[prevIdx].id, false)
                              .requestFocus();
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.arrowDown) {
                          final nextIdx = i + crossAxisCount;
                          if (nextIdx < medicines.length) {
                            _getGridFocusNode(medicines[nextIdx].id, false)
                                .requestFocus();
                          } else {
                            final topIdx = i % crossAxisCount;
                            _getGridFocusNode(medicines[topIdx].id, false)
                                .requestFocus();
                          }
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.arrowUp) {
                          final prevIdx = i - crossAxisCount;
                          if (prevIdx >= 0) {
                            _getGridFocusNode(medicines[prevIdx].id, false)
                                .requestFocus();
                          } else {
                            int lastVisibleIdx = i;
                            while (lastVisibleIdx + crossAxisCount <
                                medicines.length) {
                              lastVisibleIdx += crossAxisCount;
                            }
                            _getGridFocusNode(
                              medicines[lastVisibleIdx].id,
                              false,
                            ).requestFocus();
                          }
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: _MedicineCard(
                      medicine: m,
                      focusNode: focusNode,
                      onTap: () => widget.onAddToGrid(m),
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
}

class _MedicineCard extends StatelessWidget {
  final Medicine medicine;
  final VoidCallback onTap;
  final FocusNode focusNode;

  const _MedicineCard({
    required this.medicine,
    required this.onTap,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      focusNode: focusNode,
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          // Optionally add a subtle visual highlight when focused via keyboard
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Card(
        // Use a slight border when focused
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: focusNode.hasFocus
              ? BorderSide(
                  color: medicine.isLowStock
                      ? AppTheme.warning
                      : (context.read<CartProvider>().isReturnMode
                          ? AppTheme.danger
                          : AppTheme.primary),
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
                  color: (context.read<CartProvider>().isReturnMode
                          ? AppTheme.danger
                          : AppTheme.primary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.medication,
                  color: context.read<CartProvider>().isReturnMode
                      ? AppTheme.danger
                      : AppTheme.primaryLight,
                  size: 22,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                medicine.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                medicine.unit,
                style: TextStyle(color: context.textMutedColor, fontSize: 11),
              ),
              const SizedBox(height: 4),
              if (medicine.activeBatch != null) ...[
                Row(
                  children: [
                    Icon(Icons.layers, size: 10, color: context.textMutedColor),
                    const SizedBox(width: 4),
                    Text(
                      'Batch: ${medicine.activeBatch!.batchNo}',
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
                        color: medicine.activeBatch!.expiryDate.isBefore(
                                DateTime.now().add(const Duration(days: 90)))
                            ? AppTheme.danger
                            : context.textMutedColor),
                    const SizedBox(width: 4),
                    Text(
                      'Exp: ${medicine.activeBatch!.expiryDate.day}/${medicine.activeBatch!.expiryDate.month}/${medicine.activeBatch!.expiryDate.year}',
                      style: TextStyle(
                        fontSize: 10,
                        color: medicine.activeBatch!.expiryDate.isBefore(
                                DateTime.now().add(const Duration(days: 90)))
                            ? AppTheme.danger
                            : context.textMutedColor,
                        fontWeight: medicine.activeBatch!.expiryDate.isBefore(
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
                    '₹${medicine.sellingPrice.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: context.read<CartProvider>().isReturnMode
                          ? AppTheme.danger
                          : AppTheme.primaryLight,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: medicine.isLowStock
                          ? AppTheme.warning.withValues(alpha: 0.2)
                          : context.borderColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '${medicine.storeStock}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: medicine.isLowStock
                            ? AppTheme.warning
                            : (Theme.of(context).brightness == Brightness.dark
                                ? AppTheme.primaryLight
                                : AppTheme.primary),
                      ),
                    ),
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
  final FocusNode Function(int) getQtyFocusNode;
  final TextEditingController Function(int, int) getQtyController;
  final VoidCallback onQtyConfirm;
  final VoidCallback onDiscountConfirm;
  final VoidCallback onPaymentMethodConfirm;
  final ValueChanged<String> onPaymentMethodChanged;
  final VoidCallback onLoadPrescription;
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
    required this.onQtyConfirm,
    required this.onDiscountConfirm,
    required this.onPaymentMethodConfirm,
    required this.onPaymentMethodChanged,
    required this.onLoadPrescription,
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
                      cart.setPatient(name: p.name, phone: p.phone, id: p.id);
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
                          !node.hasFocus &&
                          patientCtrl.text.isNotEmpty) {
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
                                  subtitle: Text('${p.phone} • ${p.address}'),
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
                    color:
                        cart.isReturnMode ? AppTheme.danger : AppTheme.primary,
                  ),
                  tooltip: 'Load Prescription',
                  onPressed: onLoadPrescription,
                ),
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
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        title: Text(
                          item.medicine.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          '₹${item.medicine.sellingPrice.toStringAsFixed(2)} × ${item.qty}',
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
                                    : AppTheme.primaryLight,
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => cart.removeItem(item.medicine.id),
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
                                ? AppTheme.primary.withValues(alpha: 0.15)
                                : AppTheme.primaryLight.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  AppTheme.primaryLight.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: TextField(
                            focusNode: getQtyFocusNode(item.medicine.id),
                            controller: getQtyController(
                              item.medicine.id,
                              item.qty,
                            ),
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? AppTheme.primaryLight
                                  : AppTheme.primary,
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
                                if (!cart.isReturnMode &&
                                    finalQty > item.medicine.storeStock) {
                                  finalQty = item.medicine.storeStock;
                                  final ctrl = getQtyController(
                                    item.medicine.id,
                                    item.qty,
                                  );
                                  ctrl.text = finalQty.toString();
                                  ctrl.selection = TextSelection.collapsed(
                                    offset: finalQty.toString().length,
                                  );
                                }
                                cart.updateQty(item.medicine.id, finalQty);
                              }
                            },
                            onSubmitted: (val) {
                              int newQty = int.tryParse(val) ?? 1;
                              if (newQty > 0) {
                                if (!cart.isReturnMode &&
                                    newQty > item.medicine.storeStock) {
                                  newQty = item.medicine.storeStock;
                                }
                                cart.updateQty(item.medicine.id, newQty);
                              } else {
                                cart.updateQty(item.medicine.id, 1);
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
                        color: cart.isReturnMode
                            ? AppTheme.danger
                            : AppTheme.primaryLight,
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
                          : Icons.check_circle_outline,
                    ),
                    label: Text(
                      cart.isReturnMode ? 'PROCESS RETURN' : 'CHECKOUT',
                    ),
                    style: cart.isReturnMode
                        ? ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.danger,
                            foregroundColor: Colors.white,
                          )
                        : null,
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
                      : AppTheme.primary)
                  : context.borderColor,
              borderRadius: BorderRadius.circular(8),
              border: (isFocused && isSelected)
                  ? Border.all(
                      color: context.read<CartProvider>().isReturnMode
                          ? AppTheme.danger
                          : AppTheme.primaryLight,
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
