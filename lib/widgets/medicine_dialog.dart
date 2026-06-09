import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../shared/providers/inventory_provider.dart';
import '../shared/providers/auth_provider.dart';
import '../shared/models/medicine.dart';
import '../shared/services/sync_service.dart';
import '../theme/app_theme.dart';

class MedicineDialog extends StatefulWidget {
  final Medicine? medicine;
  const MedicineDialog({super.key, this.medicine});

  static Future<void> show(BuildContext context, {Medicine? medicine}) {
    return showDialog(
      context: context,
      builder: (_) => MedicineDialog(medicine: medicine),
    );
  }

  @override
  State<MedicineDialog> createState() => _MedicineDialogState();
}

class _MedicineDialogState extends State<MedicineDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl =
      TextEditingController(text: widget.medicine?.name ?? '');
  late final _barcodeCtrl =
      TextEditingController(text: widget.medicine?.barcode ?? '');
  late final _categoryCtrl =
      TextEditingController(text: widget.medicine?.category ?? 'General');
  late final _unitCtrl =
      TextEditingController(text: widget.medicine?.unit ?? 'Pcs');
  late final _purchaseCtrl =
      TextEditingController(text: '${widget.medicine?.purchasePrice ?? ''}');
  late final _sellCtrl =
      TextEditingController(text: '${widget.medicine?.sellingPrice ?? ''}');
  late final _mainStockCtrl =
      TextEditingController(text: '0'); // Default to 0 for adding batches
  late final _storeStockCtrl =
      TextEditingController(text: '0');
  late final _bulkClinicCtrl =
      TextEditingController(text: '0');
  late final _bulkStoreCtrl =
      TextEditingController(text: '0');
  late final _thresholdCtrl = TextEditingController(
      text: '${widget.medicine?.lowStockThreshold ?? 10}');

  Medicine? _selectedExisting;
  late final _batchNoCtrl = TextEditingController();
  late DateTime _expiryDate = DateTime.now().add(const Duration(days: 365));
  bool _isScheduleH1 = false;

  @override
  void initState() {
    super.initState();
    if (widget.medicine != null) {
      _mainStockCtrl.text = '${widget.medicine!.mainStock}';
      _storeStockCtrl.text = '${widget.medicine!.storeStock}';
      _bulkClinicCtrl.text = '${widget.medicine!.bulkClinicStock}';
      _bulkStoreCtrl.text = '${widget.medicine!.bulkStoreStock}';
      _isScheduleH1 = widget.medicine!.isScheduleH1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.medicine != null || _selectedExisting != null;

    return AlertDialog(
      title: Text(isEdit ? 'Update Medicine / Add Batch' : 'Add Medicine'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _autocompleteNameField(),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _field(_barcodeCtrl, 'Barcode')),
                  const SizedBox(width: 12),
                  Expanded(child: _field(_categoryCtrl, 'Category')),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _field(_unitCtrl, 'Unit (Pcs/ml/mg)')),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _field(_thresholdCtrl, 'Low Stock Alert',
                          keyboardType: TextInputType.number)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: _field(_purchaseCtrl, 'Purchase Price ₹',
                          keyboardType: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _field(_sellCtrl, 'Selling Price ₹ *',
                          keyboardType: TextInputType.number,
                          validator: (v) => double.tryParse(v ?? '') == null
                              ? 'Invalid price'
                              : null)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: _field(_bulkClinicCtrl, widget.medicine != null ? 'Clinic Bulk' : 'Add to Clinic Bulk',
                          keyboardType: TextInputType.number,
                          readOnly: widget.medicine != null)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _field(_bulkStoreCtrl, widget.medicine != null ? 'Store Bulk' : 'Add to Store Bulk',
                          keyboardType: TextInputType.number,
                          readOnly: widget.medicine != null)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: _field(_mainStockCtrl, widget.medicine != null ? 'Clinic Dispense' : 'Add to Clinic Disp.',
                          keyboardType: TextInputType.number,
                          readOnly: widget.medicine != null)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _field(_storeStockCtrl, widget.medicine != null ? 'Store POS' : 'Add to Store POS',
                          keyboardType: TextInputType.number,
                          readOnly: widget.medicine != null)),
                ]),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text('Schedule H1 Drug (Requires prescription & special logs)'),
                  value: _isScheduleH1,
                  activeColor: AppTheme.danger,
                  onChanged: (val) {
                    setState(() {
                      _isScheduleH1 = val ?? false;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                const Text('New Batch Info (Optional)', 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                Row(children: [
                   Expanded(child: _field(_batchNoCtrl, 'Batch Number')),
                   const SizedBox(width: 12),
                   Expanded(
                     child: InkWell(
                       onTap: _pickExpiry,
                       child: InputDecorator(
                         decoration: const InputDecoration(
                           labelText: 'Expiry Date',
                           isDense: true,
                         ),
                         child: Text(
                           '${_expiryDate.day}/${_expiryDate.month}/${_expiryDate.year}',
                         ),
                       ),
                     ),
                   ),
                ]),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        if (isEdit) ...[
          if (context.read<AuthProvider>().currentUser?.role.toLowerCase() == 'admin' ||
              context.read<AuthProvider>().currentUser?.canDeleteInventory == true)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
              onPressed: () {
                final m = widget.medicine ?? _selectedExisting;
                if (m != null) {
                  _confirmDeleteMedicine(context, m);
                }
              },
              child: const Text('Delete Medicine'),
            ),
          TextButton(
            onPressed: _updateMetadata,
            child: const Text('Update Info'),
          ),
          ElevatedButton(
            onPressed: _addBatch,
            child: const Text('Add Batch'),
          ),
        ] else
          ElevatedButton(
            onPressed: _addBatch,
            child: const Text('Create & Add'),
          ),
      ],
    );
  }

  void _confirmDeleteMedicine(BuildContext context, Medicine m) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Medicine?'),
        content: Text('Are you sure you want to permanently delete ${m.name}? This will remove all batch and stock details.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              context.read<InventoryProvider>().deleteMedicine(m.id);
              Navigator.pop(ctx); // Close confirmation
              Navigator.pop(context); // Close medicine dialog
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _autocompleteNameField() {
    final inv = context.read<InventoryProvider>();
    return Autocomplete<Medicine>(
      initialValue: TextEditingValue(text: _nameCtrl.text),
      displayStringForOption: (m) => m.name,
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) return const Iterable<Medicine>.empty();
        return inv.medicines.where((m) => m.name
            .toLowerCase()
            .contains(textEditingValue.text.toLowerCase()));
      },
      onSelected: (Medicine selection) {
        setState(() {
          _selectedExisting = selection;
          _nameCtrl.text = selection.name;
          _barcodeCtrl.text = selection.barcode;
          _categoryCtrl.text = selection.category;
          _unitCtrl.text = selection.unit;
          _purchaseCtrl.text = selection.purchasePrice.toString();
          _sellCtrl.text = selection.sellingPrice.toString();
          _thresholdCtrl.text = selection.lowStockThreshold.toString();
          _isScheduleH1 = selection.isScheduleH1;
          // Quantities stay 0 for new batch entry unless editing established medicine
        });
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        if (controller.text.isEmpty && _nameCtrl.text.isNotEmpty) {
          controller.text = _nameCtrl.text;
        }
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          onFieldSubmitted: (v) => onFieldSubmitted(),
          decoration: const InputDecoration(
            labelText: 'Medicine Name *',
            isDense: true,
          ),
          onChanged: (val) {
            _nameCtrl.text = val;
          },
          validator: (v) => v!.isEmpty ? 'Name required' : null,
        );
      },
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      {TextInputType? keyboardType,
      String? Function(String?)? validator,
      bool readOnly = false}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      validator: validator,
      readOnly: readOnly,
      decoration: InputDecoration(labelText: label, isDense: true, filled: readOnly, fillColor: readOnly ? Colors.grey.shade100 : null),
    );
  }

  void _updateMetadata() {
    if (!_formKey.currentState!.validate()) return;
    final inv = context.read<InventoryProvider>();
    final sync = context.read<SyncService>();

    final m = _selectedExisting ?? widget.medicine;
    if (m == null) return;

    m
      ..name = _nameCtrl.text.trim()
      ..barcode = _barcodeCtrl.text.trim()
      ..category = _categoryCtrl.text.trim()
      ..unit = _unitCtrl.text.trim()
      ..purchasePrice = double.tryParse(_purchaseCtrl.text) ?? 0
      ..sellingPrice = double.tryParse(_sellCtrl.text) ?? 0
      ..isScheduleH1 = _isScheduleH1
      // We no longer update mainStock/storeStock here to prevent desync with batches
      ..lowStockThreshold = int.tryParse(_thresholdCtrl.text) ?? 10;

    inv.updateMedicine(m, syncService: sync);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Medicine details updated')),
    );
  }

  void _addBatch() {
    if (!_formKey.currentState!.validate()) return;
    final inv = context.read<InventoryProvider>();
    final sync = context.read<SyncService>();

    final inputMain = int.tryParse(_mainStockCtrl.text) ?? 0;
    final inputStore = int.tryParse(_storeStockCtrl.text) ?? 0;
    final inputBulkClinic = int.tryParse(_bulkClinicCtrl.text) ?? 0;
    final inputBulkStore = int.tryParse(_bulkStoreCtrl.text) ?? 0;

    if (inputMain <= 0 && inputStore <= 0 && inputBulkClinic <= 0 && inputBulkStore <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter quantity for the new batch')),
      );
      return;
    }

    final m = _selectedExisting ?? widget.medicine;
    if (m == null) {
      // New medicine creation flow
      final newM = Medicine(
        name: _nameCtrl.text.trim(),
        barcode: _barcodeCtrl.text.trim(),
        category: _categoryCtrl.text.trim(),
        unit: _unitCtrl.text.trim(),
        purchasePrice: double.tryParse(_purchaseCtrl.text) ?? 0,
        sellingPrice: double.tryParse(_sellCtrl.text) ?? 0,
        lowStockThreshold: int.tryParse(_thresholdCtrl.text) ?? 10,
        isScheduleH1: _isScheduleH1,
      );
      inv.addMedicine(newM, syncService: sync);
      
      inv.addBatchStock(
        {newM.id: inputMain},
        storeUpdates: {newM.id: inputStore},
        bulkClinicUpdates: {newM.id: inputBulkClinic},
        bulkStoreUpdates: {newM.id: inputBulkStore},
        batchNo: _batchNoCtrl.text.isNotEmpty ? _batchNoCtrl.text.trim() : 'B-${DateTime.now().millisecondsSinceEpoch}',
        expiryDate: _expiryDate,
        syncService: sync,
      );
    } else {
      // Existing medicine: add batch only
      inv.addBatchStock(
        {m.id: inputMain},
        storeUpdates: {m.id: inputStore},
        bulkClinicUpdates: {m.id: inputBulkClinic},
        bulkStoreUpdates: {m.id: inputBulkStore},
        batchNo: _batchNoCtrl.text.isNotEmpty ? _batchNoCtrl.text.trim() : 'B-${DateTime.now().millisecondsSinceEpoch}',
        expiryDate: _expiryDate,
        syncService: sync,
      );
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('New batch added successfully')),
    );
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      locale: const Locale('en', 'GB'),
      initialEntryMode: DatePickerEntryMode.input,
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }
}
