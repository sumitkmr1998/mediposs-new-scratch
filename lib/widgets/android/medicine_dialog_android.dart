import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/auth_provider.dart';
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
  late final TextEditingController _thresholdCtrl;

  // Temporary list for editing batches
  final List<MedicineBatch> _localBatches = [];
  bool _isScheduleH1 = false;

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
    _thresholdCtrl = TextEditingController(
        text: '${widget.medicine?.lowStockThreshold ?? 10}');
    _isScheduleH1 = widget.medicine?.isScheduleH1 ?? false;

    if (widget.medicine != null) {
      _localBatches.addAll(widget.medicine!.batches.map((b) => MedicineBatch(
            id: b.id,
            batchNo: b.batchNo,
            expiryDate: b.expiryDate,
            mainStock: b.mainStock,
            storeStock: b.storeStock,
            bulkClinicStock: b.bulkClinicStock,
            bulkStoreStock: b.bulkStoreStock,
          )));
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _categoryCtrl.dispose();
    _unitCtrl.dispose();
    _purchaseCtrl.dispose();
    _sellCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController ctrl, String label,
      {TextInputType? keyboardType,
      String? Function(String?)? validator,
      IconData? prefixIcon,
      bool readOnly = false}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      validator: validator,
      readOnly: readOnly,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.textMutedColor, fontSize: 13, fontWeight: FontWeight.w600),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: AppTheme.primaryLight, size: 20)
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
        fillColor: readOnly ? context.textMutedColor.withValues(alpha: 0.05) : Theme.of(context).scaffoldBackgroundColor,
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
      ..isScheduleH1 = _isScheduleH1
      ..lowStockThreshold = int.tryParse(_thresholdCtrl.text) ?? 10;

    // Recalculate main/store stock from batches
    int totalMain = 0;
    int totalStore = 0;
    int totalBulkClinic = 0;
    int totalBulkStore = 0;
    for (var b in _localBatches) {
      totalMain += b.mainStock;
      totalStore += b.storeStock;
      totalBulkClinic += b.bulkClinicStock;
      totalBulkStore += b.bulkStoreStock;
    }
    m.mainStock = totalMain;
    m.storeStock = totalStore;
    m.bulkClinicStock = totalBulkClinic;
    m.bulkStoreStock = totalBulkStore;

    // Sync batches
    m.batches.clear();
    for (var b in _localBatches) {
      b.medicine.target = m;
      m.batches.add(b);
    }

    final sync = context.read<SyncService>();
    final actor = context.read<AuthProvider>().currentUser;
    if (widget.medicine != null) {
      inv.updateMedicine(m, syncService: sync, actor: actor);
    } else {
      inv.addMedicine(m, syncService: sync, actor: actor);
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            widget.medicine != null ? 'Medicine record synchronized' : 'New medicine record established'),
        backgroundColor: AppTheme.success,
      ),
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
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            onPressed: () {
              context.read<InventoryProvider>().deleteMedicine(m.id);
              Navigator.pop(ctx); // Close confirmation
              Navigator.pop(context); // Close medicine dialog sheet
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.medicine != null;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final currentUser = context.watch<AuthProvider>().currentUser;
    final canEditFull = currentUser?.role.toLowerCase() == 'admin' || (currentUser?.canEditInventory ?? false) || !isEdit;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.95,
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
              Center(
                child: Container(
                  width: 48, height: 5,
                  decoration: BoxDecoration(color: context.borderColor, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isEdit ? 'Clinical Update' : 'New Registry',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.primaryLight, letterSpacing: -0.5)),
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      _buildFormSection(
                        title: 'SPECIFICATIONS',
                        children: [
                          _field(_nameCtrl, 'MEDICINE NAME', prefixIcon: Icons.medication_outlined, validator: (v) => v!.isEmpty ? 'Name required' : null, readOnly: !canEditFull),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: _field(_barcodeCtrl, 'BARCODE', prefixIcon: Icons.qr_code_rounded, readOnly: !canEditFull)),
                              const SizedBox(width: 8),
                              Expanded(child: _field(_categoryCtrl, 'CATEGORY', prefixIcon: Icons.category_rounded, readOnly: !canEditFull)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: _field(_unitCtrl, 'UNIT', prefixIcon: Icons.scale_rounded, readOnly: !canEditFull)),
                              const SizedBox(width: 8),
                              Expanded(child: _field(_thresholdCtrl, 'LOW STOCK ALERT', keyboardType: TextInputType.number, prefixIcon: Icons.warning_amber_rounded, readOnly: !canEditFull)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            title: const Text('SCHEDULE H1 DRUG', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.2, color: AppTheme.danger)),
                            subtitle: const Text('Prescription & special reporting compliance mandatory', style: TextStyle(fontSize: 10)),
                            value: _isScheduleH1,
                            activeColor: AppTheme.danger,
                            onChanged: canEditFull ? (val) {
                              setState(() {
                                _isScheduleH1 = val ?? false;
                              });
                            } : null,
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFormSection(
                        title: 'FINANCIALS',
                        children: [
                          Row(
                            children: [
                              Expanded(child: _field(_purchaseCtrl, 'PURCHASE PRICE (₹)', keyboardType: TextInputType.number, prefixIcon: Icons.currency_rupee_rounded, readOnly: !canEditFull)),
                              const SizedBox(width: 8),
                              Expanded(child: _field(_sellCtrl, 'SELLING PRICE (₹)', keyboardType: TextInputType.number, prefixIcon: Icons.sell_rounded,
                                readOnly: !canEditFull,
                                validator: (v) => double.tryParse(v ?? '') == null ? 'Invalid price' : null)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFormSection(
                        title: 'BATCHES & EXPIRY',
                        children: [
                          if (_localBatches.isEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              decoration: BoxDecoration(color: context.borderColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                              child: Center(child: Text('No batches registered', style: TextStyle(color: context.textMutedColor, fontWeight: FontWeight.w600, fontSize: 13))),
                            )
                          else
                            Column(
                              children: _localBatches.map((b) => _BatchItem(
                                batch: b,
                                onDelete: () => setState(() => _localBatches.remove(b)),
                                onEdit: () => _showBatchEdit(b),
                              )).toList(),
                            ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: () => _showBatchEdit(),
                            icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: AppTheme.primaryLight),
                            label: const Text('REGISTER NEW BATCH', style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.primaryLight, fontSize: 12)),
                            style: TextButton.styleFrom(
                              backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.05),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 80),
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
                    backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(isEdit ? 'SYNCHRONIZE RECORD' : 'ESTABLISH REGISTRY', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ),
              ),
              if (isEdit && (context.read<AuthProvider>().currentUser?.role.toLowerCase() == 'admin' ||
                  context.read<AuthProvider>().currentUser?.canDeleteInventory == true)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      side: const BorderSide(color: AppTheme.danger),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => _confirmDeleteMedicine(context, widget.medicine!),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('DELETE MEDICINE', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showBatchEdit([MedicineBatch? existing]) {
    showDialog(
      context: context,
      builder: (_) => _BatchDialog(
        batch: existing,
        onSave: (b) {
          setState(() {
            if (existing != null) {
              final idx = _localBatches.indexOf(existing);
              _localBatches[idx] = b;
            } else {
              _localBatches.add(b);
            }
          });
        },
      ),
    );
  }

  Widget _buildFormSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 10),
          child: Text(title.toUpperCase(), 
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppTheme.primaryLight, letterSpacing: 1.2)),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.surfaceColor.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(color: context.borderColor.withValues(alpha: 0.3)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _BatchItem extends StatelessWidget {
  final MedicineBatch batch;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _BatchItem({required this.batch, required this.onDelete, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final isExpired = batch.expiryDate.isBefore(DateTime.now());
    final isNear = batch.expiryDate.isBefore(DateTime.now().add(const Duration(days: 90)));
    final Color statusColor = isExpired ? AppTheme.danger : (isNear ? AppTheme.warning : AppTheme.success);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.textMutedColor.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.inventory_2_rounded, color: statusColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(batch.batchNo.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text('EXPIRY: ${DateFormat('MMM yyyy').format(batch.expiryDate).toUpperCase()}', 
                  style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${batch.mainStock + batch.storeStock + batch.bulkClinicStock + batch.bulkStoreStock} PCS', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(height: 2),
              Text('STORE:${batch.storeStock} | CLINIC:${batch.mainStock}', style: TextStyle(fontSize: 10, color: context.textMutedColor, fontWeight: FontWeight.w700)),
              Text('S.BULK:${batch.bulkStoreStock} | C.BULK:${batch.bulkClinicStock}', style: TextStyle(fontSize: 9, color: context.textMutedColor, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.edit_note_rounded, color: AppTheme.primary), onPressed: onEdit, visualDensity: VisualDensity.compact),
          if (context.read<AuthProvider>().currentUser?.role.toLowerCase() == 'admin' ||
              context.read<AuthProvider>().currentUser?.canDeleteInventory == true)
            IconButton(icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger), onPressed: onDelete, visualDensity: VisualDensity.compact),
        ],
      ),
    );
  }
}

class _BatchDialog extends StatefulWidget {
  final MedicineBatch? batch;
  final Function(MedicineBatch) onSave;

  const _BatchDialog({this.batch, required this.onSave});

  @override
  State<_BatchDialog> createState() => _BatchDialogState();
}

class _BatchDialogState extends State<_BatchDialog> {
  late final TextEditingController _noCtrl;
  late final TextEditingController _hubCtrl;
  late final TextEditingController _posCtrl;
  late final TextEditingController _bulkClinicCtrl;
  late final TextEditingController _bulkStoreCtrl;
  late DateTime _expiry;

  @override
  void initState() {
    super.initState();
    _noCtrl = TextEditingController(text: widget.batch?.batchNo ?? '');
    _hubCtrl = TextEditingController(text: '${widget.batch?.mainStock ?? 0}');
    _posCtrl = TextEditingController(text: '${widget.batch?.storeStock ?? 0}');
    _bulkClinicCtrl = TextEditingController(text: '${widget.batch?.bulkClinicStock ?? 0}');
    _bulkStoreCtrl = TextEditingController(text: '${widget.batch?.bulkStoreStock ?? 0}');
    _expiry = widget.batch?.expiryDate ?? DateTime.now().add(const Duration(days: 365));
  }

  Widget _field(TextEditingController ctrl, String label, {TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.textMutedColor, fontWeight: FontWeight.w600, fontSize: 13),
        isDense: true,
        filled: true,
        fillColor: context.textMutedColor.withValues(alpha: 0.03),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor.withValues(alpha: 0.3))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor.withValues(alpha: 0.3))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(widget.batch != null ? 'EDIT BATCH' : 'NEW REGISTRY', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1, color: AppTheme.primaryLight)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_noCtrl, 'BATCH NUMBER'),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _expiry,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                  locale: const Locale('en', 'GB'),
                  initialEntryMode: DatePickerEntryMode.input,
                );
                if (d != null) setState(() => _expiry = d);
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.textMutedColor.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 20, color: AppTheme.primary),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('EXPIRY DATE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 0.5)),
                        Text(DateFormat('dd MMM yyyy').format(_expiry).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _field(_bulkStoreCtrl, 'STORE BULK', keyboardType: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: _field(_bulkClinicCtrl, 'CLINIC BULK', keyboardType: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _field(_posCtrl, 'STORE POS', keyboardType: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: _field(_hubCtrl, 'CLINIC DISP', keyboardType: TextInputType.number)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: () {
            if (_noCtrl.text.isEmpty) return;
            widget.onSave(MedicineBatch(
              id: widget.batch?.id ?? 0,
              batchNo: _noCtrl.text.trim(),
              expiryDate: _expiry,
              mainStock: int.tryParse(_hubCtrl.text) ?? 0,
              storeStock: int.tryParse(_posCtrl.text) ?? 0,
              bulkClinicStock: int.tryParse(_bulkClinicCtrl.text) ?? 0,
              bulkStoreStock: int.tryParse(_bulkStoreCtrl.text) ?? 0,
            ));
            Navigator.pop(context);
          },
          child: const Text('SAVE BATCH'),
        ),
      ],
    );
  }
}
