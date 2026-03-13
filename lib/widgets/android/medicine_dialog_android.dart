import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/models/medicine.dart';
import '../../shared/services/sync_service.dart';
import '../../theme/app_theme.dart';

class AndroidMedicineDialog {
  static Future<void> show(BuildContext context, {Medicine? medicine}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _MedicineRegistrationSheet(medicine: medicine),
    );
  }
}

class _MedicineRegistrationSheet extends StatefulWidget {
  final Medicine? medicine;
  const _MedicineRegistrationSheet({this.medicine});

  @override
  State<_MedicineRegistrationSheet> createState() =>
      _MedicineRegistrationSheetState();
}

class _MedicineRegistrationSheetState
    extends State<_MedicineRegistrationSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _purchaseCtrl;
  late final TextEditingController _sellCtrl;
  late final TextEditingController _mainStockCtrl;
  late final TextEditingController _storeStockCtrl;
  late final TextEditingController _thresholdCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.medicine?.name ?? '');
    _barcodeCtrl = TextEditingController(text: widget.medicine?.barcode ?? '');
    _categoryCtrl =
        TextEditingController(text: widget.medicine?.category ?? 'General');
    _unitCtrl = TextEditingController(text: widget.medicine?.unit ?? 'Pcs');
    _purchaseCtrl =
        TextEditingController(text: '${widget.medicine?.purchasePrice ?? ''}');
    _sellCtrl =
        TextEditingController(text: '${widget.medicine?.sellingPrice ?? ''}');
    _mainStockCtrl =
        TextEditingController(text: '${widget.medicine?.mainStock ?? 0}');
    _storeStockCtrl =
        TextEditingController(text: '${widget.medicine?.storeStock ?? 0}');
    _thresholdCtrl = TextEditingController(
        text: '${widget.medicine?.lowStockThreshold ?? 10}');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _categoryCtrl.dispose();
    _unitCtrl.dispose();
    _purchaseCtrl.dispose();
    _sellCtrl.dispose();
    _mainStockCtrl.dispose();
    _storeStockCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController ctrl, String label,
      {TextInputType? keyboardType,
      String? Function(String?)? validator,
      IconData? prefixIcon}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      validator: validator,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.textMutedColor),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: AppTheme.primaryLight)
            : null,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: context.borderColor.withValues(alpha: 0.5))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: context.borderColor.withValues(alpha: 0.5))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
        filled: true,
        fillColor: Theme.of(context).scaffoldBackgroundColor,
        isDense: true,
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final inv = context.read<InventoryProvider>();
    final m = widget.medicine ??
        Medicine(
          name: _nameCtrl.text.trim(),
          purchasePrice: double.tryParse(_purchaseCtrl.text) ?? 0,
          sellingPrice: double.tryParse(_sellCtrl.text) ?? 0,
        );

    m
      ..name = _nameCtrl.text.trim()
      ..barcode = _barcodeCtrl.text.trim()
      ..category = _categoryCtrl.text.trim()
      ..unit = _unitCtrl.text.trim()
      ..purchasePrice = double.tryParse(_purchaseCtrl.text) ?? 0
      ..sellingPrice = double.tryParse(_sellCtrl.text) ?? 0
      ..mainStock = int.tryParse(_mainStockCtrl.text) ?? 0
      ..storeStock = int.tryParse(_storeStockCtrl.text) ?? 0
      ..lowStockThreshold = int.tryParse(_thresholdCtrl.text) ?? 10;

    final sync = context.read<SyncService>();
    if (widget.medicine != null) {
      inv.updateMedicine(m, syncService: sync);
    } else {
      inv.addMedicine(m, syncService: sync);
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            widget.medicine != null ? 'Medicine updated' : 'Medicine added'),
        backgroundColor: AppTheme.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.medicine != null;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Swipe handle
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                      color: context.borderColor,
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEdit ? 'Edit Medicine' : 'Add New Medicine',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryLight),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildFormSection(
                        title: 'General Details',
                        children: [
                          _field(_nameCtrl, 'Medicine Name *',
                              prefixIcon: Icons.medication_outlined,
                              validator: (v) =>
                                  v!.isEmpty ? 'Name required' : null),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                  child: _field(_barcodeCtrl, 'Barcode',
                                      prefixIcon: Icons.qr_code_rounded)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _field(_categoryCtrl, 'Category',
                                      prefixIcon: Icons.category_rounded)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                  child: _field(_unitCtrl, 'Unit (Pcs/ml)',
                                      prefixIcon: Icons.scale_rounded)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _field(
                                      _thresholdCtrl, 'Low Stock Alert',
                                      keyboardType: TextInputType.number,
                                      prefixIcon: Icons.warning_amber_rounded)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFormSection(
                        title: 'Pricing',
                        children: [
                          Row(
                            children: [
                              Expanded(
                                  child: _field(
                                      _purchaseCtrl, 'Purchase Price (₹)',
                                      keyboardType: TextInputType.number,
                                      prefixIcon:
                                          Icons.currency_rupee_rounded)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _field(
                                      _sellCtrl, 'Selling Price (₹) *',
                                      keyboardType: TextInputType.number,
                                      prefixIcon: Icons.sell_rounded,
                                      validator: (v) =>
                                          double.tryParse(v ?? '') == null
                                              ? 'Invalid price'
                                              : null)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFormSection(
                        title: 'Current Stock',
                        children: [
                          Row(
                            children: [
                              Expanded(
                                  child: _field(_mainStockCtrl, 'Warehouse Qty',
                                      keyboardType: TextInputType.number,
                                      prefixIcon: Icons.inventory_2_rounded)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _field(
                                      _storeStockCtrl, 'Store/POS Qty',
                                      keyboardType: TextInputType.number,
                                      prefixIcon: Icons.storefront_rounded)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: Text(isEdit ? 'Save Changes' : 'Add Medicine',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormSection(
      {required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
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
        border: Border.all(color: context.borderColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: AppTheme.primaryLight),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
