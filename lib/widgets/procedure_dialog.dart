import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../shared/models/procedure.dart';
import '../shared/providers/procedure_provider.dart';
import '../theme/app_theme.dart';

class ProcedureDialog extends StatefulWidget {
  final Procedure? procedure;
  const ProcedureDialog({super.key, this.procedure});

  @override
  State<ProcedureDialog> createState() => _ProcedureDialogState();
}

class _ProcedureDialogState extends State<ProcedureDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.procedure != null) {
      _nameCtrl.text = widget.procedure!.name;
      _categoryCtrl.text = widget.procedure!.category;
      _priceCtrl.text = widget.procedure!.basePrice.toString();
      _descCtrl.text = widget.procedure!.description;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.procedure == null ? 'Add Procedure' : 'Edit Procedure'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Procedure Name'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _categoryCtrl,
                decoration: const InputDecoration(labelText: 'Category (Laser, Skin, etc.)'),
              ),
              TextFormField(
                controller: _priceCtrl,
                decoration: const InputDecoration(labelText: 'Base Price (₹)'),
                keyboardType: TextInputType.number,
                validator: (v) => double.tryParse(v ?? '') == null ? 'Invalid price' : null,
              ),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final p = Procedure(
                id: widget.procedure?.id ?? 0,
                name: _nameCtrl.text,
                category: _categoryCtrl.text,
                basePrice: double.parse(_priceCtrl.text),
                description: _descCtrl.text,
              );
              context.read<ProcedureProvider>().saveProcedure(p);
              Navigator.pop(context);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
