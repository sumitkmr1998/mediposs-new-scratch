import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../shared/providers/inventory_provider.dart';
import '../shared/models/medicine.dart';
import '../shared/services/sync_service.dart';

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
  late final _thresholdCtrl = TextEditingController(
      text: '${widget.medicine?.lowStockThreshold ?? 10}');

  Medicine? _selectedExisting;
  late final _batchNoCtrl = TextEditingController();
  late DateTime _expiryDate = DateTime.now().add(const Duration(days: 365));

  @override
  void initState() {
    super.initState();
    if (widget.medicine != null) {
      _mainStockCtrl.text = '${widget.medicine!.mainStock}';
      _storeStockCtrl.text = '${widget.medicine!.storeStock}';
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
                      child: _field(_mainStockCtrl, widget.medicine != null ? 'Main Hub Stock' : 'Add to Main Hub',
                          keyboardType: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _field(_storeStockCtrl, widget.medicine != null ? 'Store Stock' : 'Add to Store',
                          keyboardType: TextInputType.number)),
                ]),
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
        const Spacer(),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        if (isEdit || _selectedExisting != null) ...[
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
          // Quantities stay 0 for new batch entry unless editing established medicine
        });
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        if (controller.text != _nameCtrl.text && _nameCtrl.text.isNotEmpty && controller.text.isEmpty) {
           controller.text = _nameCtrl.text;
        }
        controller.addListener(() {
          _nameCtrl.text = controller.text;
        });

        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          onFieldSubmitted: (v) => onFieldSubmitted(),
          decoration: const InputDecoration(
            labelText: 'Medicine Name *',
            isDense: true,
          ),
          validator: (v) => v!.isEmpty ? 'Name required' : null,
        );
      },
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      {TextInputType? keyboardType, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(labelText: label, isDense: true),
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
      ..mainStock = int.tryParse(_mainStockCtrl.text) ?? m.mainStock
      ..storeStock = int.tryParse(_storeStockCtrl.text) ?? m.storeStock
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

    if (inputMain <= 0 && inputStore <= 0) {
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
      );
      inv.addMedicine(newM, syncService: sync);
      
      inv.addBatchStock(
        {newM.id: inputMain},
        storeUpdates: {newM.id: inputStore},
        batchNo: _batchNoCtrl.text.isNotEmpty ? _batchNoCtrl.text.trim() : 'B-${DateTime.now().millisecondsSinceEpoch}',
        expiryDate: _expiryDate,
        syncService: sync,
      );
    } else {
      // Existing medicine: add batch only
      inv.addBatchStock(
        {m.id: inputMain},
        storeUpdates: {m.id: inputStore},
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
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }
}
