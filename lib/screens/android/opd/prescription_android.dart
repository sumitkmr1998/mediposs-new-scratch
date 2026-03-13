import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/models/appointment.dart';
import '../../../shared/models/prescription.dart';
import '../../../shared/providers/prescription_provider.dart';
import '../../../shared/providers/inventory_provider.dart';
import '../../../shared/providers/template_provider.dart';
import '../../../shared/services/sync_service.dart';
import '../../../theme/app_theme.dart';

class PrescriptionAndroid extends StatefulWidget {
  final Appointment appointment;

  const PrescriptionAndroid({super.key, required this.appointment});

  @override
  State<PrescriptionAndroid> createState() => _PrescriptionAndroidState();
}

class _PrescriptionAndroidState extends State<PrescriptionAndroid> {
  final _diagnosisCtrl = TextEditingController();
  final _complaintsCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // Vitals
  final _bpCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _tempCtrl = TextEditingController();
  final _spo2Ctrl = TextEditingController();
  final _pulseCtrl = TextEditingController();

  // Medicine search
  final _medSearchCtrl = TextEditingController();
  final _dosageCtrl = TextEditingController();
  final _daysCtrl = TextEditingController(text: '3');
  final _qtyCtrl = TextEditingController(text: '1');

  List<PrescriptionItem> _items = [];
  List<String> _labTests = [];
  final _labTestCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Load existing prescription if it exists
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pProvider = context.read<PrescriptionProvider>();
      final existing =
          pProvider.getPrescriptionForAppointment(widget.appointment.id);
      if (existing != null) {
        _diagnosisCtrl.text = existing.diagnosis;
        _complaintsCtrl.text = existing.complaints;
        _notesCtrl.text = existing.notes;
        final vitals = pProvider.getVitals(existing);
        _bpCtrl.text = vitals.bp;
        _weightCtrl.text = vitals.weight;
        _tempCtrl.text = vitals.temp;
        _spo2Ctrl.text = vitals.spo2;
        _pulseCtrl.text = vitals.pulse;
        setState(() {
          _items = pProvider.getItems(existing);
          _labTests = pProvider.getLabTests(existing);
        });
      }
    });
  }

  @override
  void dispose() {
    _diagnosisCtrl.dispose();
    _complaintsCtrl.dispose();
    _notesCtrl.dispose();
    _bpCtrl.dispose();
    _weightCtrl.dispose();
    _tempCtrl.dispose();
    _spo2Ctrl.dispose();
    _pulseCtrl.dispose();
    _medSearchCtrl.dispose();
    _dosageCtrl.dispose();
    _daysCtrl.dispose();
    _qtyCtrl.dispose();
    _labTestCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Prescription — Token #${widget.appointment.tokenNumber}'),
            Text(
              '${widget.appointment.patientName}  •  Dr. ${widget.appointment.doctorName}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          // Load Template button
          OutlinedButton.icon(
            onPressed: () => _loadTemplateDialog(context),
            icon: const Icon(Icons.library_books_outlined, size: 18),
            label: const Text('Templates'),
          ),
          const SizedBox(width: 8),
          // Save as Template button
          OutlinedButton.icon(
            onPressed: () => _saveAsTemplateDialog(context),
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('Save Template'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save & Send'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Vitals Section ──────────────────────────
            _SectionHeader(
                title: '🩺 Vitals', icon: Icons.monitor_heart_outlined),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _VitalField(
                    ctrl: _bpCtrl, label: 'Blood Pressure', hint: '120/80'),
                _VitalField(ctrl: _pulseCtrl, label: 'Pulse', hint: '72 bpm'),
                _VitalField(
                    ctrl: _tempCtrl, label: 'Temperature', hint: '98.6°F'),
                _VitalField(ctrl: _weightCtrl, label: 'Weight', hint: '65 kg'),
                _VitalField(ctrl: _spo2Ctrl, label: 'SpO2', hint: '98%'),
              ],
            ),
            const SizedBox(height: 24),

            // ── Complaints & Diagnosis ──────────────────
            _SectionHeader(
                title: '📋 Consultation', icon: Icons.chat_bubble_outline),
            const SizedBox(height: 12),
            TextField(
              controller: _complaintsCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Chief Complaints',
                hintText: 'e.g. Fever since 2 days, headache...',
                prefixIcon: Icon(Icons.sick_outlined),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _diagnosisCtrl,
              decoration: const InputDecoration(
                labelText: 'Diagnosis / Impression',
                hintText: 'e.g. Viral fever, URTI',
                prefixIcon: Icon(Icons.biotech_outlined),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: "Doctor's Notes",
                hintText: 'Additional clinical observations...',
                prefixIcon: Icon(Icons.notes),
                isDense: true,
              ),
            ),
            const SizedBox(height: 24),

            // ── Medicines ──────────────────────────────
            _SectionHeader(
                title: '💊 Medicines', icon: Icons.medication_outlined),
            const SizedBox(height: 12),
            _MedicineAdder(
              searchCtrl: _medSearchCtrl,
              dosageCtrl: _dosageCtrl,
              daysCtrl: _daysCtrl,
              qtyCtrl: _qtyCtrl,
              onAdd: (item) => setState(() => _items.add(item)),
            ),
            const SizedBox(height: 8),
            ..._items.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                  title: Text(item.medicineName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text(
                      'Qty: ${item.qty}  •  ${item.dosage.isNotEmpty ? item.dosage : "No dosage"}  •  ${item.days} days',
                      style: TextStyle(
                          color: context.textMutedColor, fontSize: 11)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close,
                        size: 16, color: AppTheme.danger),
                    onPressed: () => setState(() => _items.removeAt(i)),
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),

            // ── Lab Tests ──────────────────────────────
            _SectionHeader(title: '🧪 Lab Tests', icon: Icons.science_outlined),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _labTestCtrl,
                    decoration: const InputDecoration(
                      hintText: 'e.g. CBC, Blood Sugar, Urine',
                      prefixIcon: Icon(Icons.add_circle_outline),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addLabTest(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                    onPressed: _addLabTest, child: const Text('Add')),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _labTests.asMap().entries.map((entry) {
                return Chip(
                  label: Text(entry.value),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () =>
                      setState(() => _labTests.removeAt(entry.key)),
                  backgroundColor: Color(0xFF7C3AED).withValues(alpha: 0.1),
                  side: const BorderSide(color: Color(0xFF7C3AED), width: 0.5),
                  labelStyle:
                      const TextStyle(color: Color(0xFF7C3AED), fontSize: 12),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _addLabTest() {
    final test = _labTestCtrl.text.trim();
    if (test.isNotEmpty) {
      setState(() {
        _labTests.add(test);
        _labTestCtrl.clear();
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final vitals = Vitals(
        bp: _bpCtrl.text.trim(),
        weight: _weightCtrl.text.trim(),
        temp: _tempCtrl.text.trim(),
        spo2: _spo2Ctrl.text.trim(),
        pulse: _pulseCtrl.text.trim(),
      );

      final syncService = context.read<SyncService>();
      context.read<PrescriptionProvider>().savePrescription(
            appointmentId: widget.appointment.id,
            patientId: widget.appointment.patientId,
            patientName: widget.appointment.patientName,
            doctorId: widget.appointment.doctorId,
            doctorName: widget.appointment.doctorName,
            diagnosis: _diagnosisCtrl.text.trim(),
            complaints: _complaintsCtrl.text.trim(),
            notes: _notesCtrl.text.trim(),
            items: _items,
            labTests: _labTests,
            vitals: vitals,
            syncService: syncService,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Prescription saved! Patient moved to Pharmacy status.'),
        backgroundColor: AppTheme.success,
      ));
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Shows a bottom sheet with saved templates to apply
  void _loadTemplateDialog(BuildContext context) {
    final tProvider = context.read<TemplateProvider>();
    tProvider.load();
    final templates = tProvider.templates;
    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'No templates saved yet. Fill a prescription and tap "Save Template".'),
      ));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.85,
          builder: (_, scrollCtrl) => Column(
            children: [
              const SizedBox(height: 8),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.library_books, color: AppTheme.primary),
                    const SizedBox(width: 10),
                    Text('Select Template',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: templates.length,
                  itemBuilder: (_, i) {
                    final t = templates[i];
                    final itemCount = tProvider.getItems(t).length;
                    final labCount = tProvider.getLabTests(t).length;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            AppTheme.primary.withValues(alpha: 0.1),
                        child: const Icon(Icons.description_outlined,
                            color: AppTheme.primary, size: 20),
                      ),
                      title: Text(t.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${t.diagnosis.isNotEmpty ? t.diagnosis : "No diagnosis"}  •  $itemCount medicines${labCount > 0 ? "  •  $labCount tests" : ""}',
                        style: TextStyle(
                            color: context.textMutedColor, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppTheme.danger, size: 18),
                            tooltip: 'Delete template',
                            onPressed: () {
                              tProvider.delete(t.id);
                              Navigator.pop(context);
                            },
                          ),
                          TextButton(
                            onPressed: () {
                              _applyTemplate(t, tProvider);
                              Navigator.pop(context);
                            },
                            child: const Text('Apply'),
                          ),
                        ],
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

  /// Applies a template's content to the current form
  void _applyTemplate(dynamic t, TemplateProvider tProvider) {
    setState(() {
      if (t.diagnosis.isNotEmpty) _diagnosisCtrl.text = t.diagnosis;
      if (t.complaints.isNotEmpty) _complaintsCtrl.text = t.complaints;
      if (t.notes.isNotEmpty) _notesCtrl.text = t.notes;
      final templateItems = tProvider.getItems(t);
      if (templateItems.isNotEmpty) _items = List.from(templateItems);
      final templateTests = tProvider.getLabTests(t);
      if (templateTests.isNotEmpty) _labTests = List.from(templateTests);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Template "${t.name}" applied ✓'),
      backgroundColor: AppTheme.success,
    ));
  }

  /// Dialog to name and save the current form content as a template
  void _saveAsTemplateDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.bookmark_add_outlined, color: AppTheme.primary),
            SizedBox(width: 8),
            Text('Save as Template'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saves the current diagnosis, medicines, and lab tests as a reusable template.',
              style: TextStyle(color: context.textMutedColor, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Template Name *',
                hintText: 'e.g. Cold & Fever, Diabetes Follow-up',
                prefixIcon: Icon(Icons.label_outline),
                isDense: true,
              ),
              onSubmitted: (_) => _doSaveTemplate(ctx, nameCtrl),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => _doSaveTemplate(ctx, nameCtrl),
            child: const Text('Save Template'),
          ),
        ],
      ),
    );
  }

  void _doSaveTemplate(BuildContext ctx, TextEditingController nameCtrl) {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    context.read<TemplateProvider>().save(
          name: name,
          diagnosis: _diagnosisCtrl.text.trim(),
          complaints: _complaintsCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
          items: _items,
          labTests: _labTests,
          doctorId: widget.appointment.doctorId,
        );
    Navigator.pop(ctx);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Template "$name" saved!'),
      backgroundColor: AppTheme.success,
    ));
  }
}

class _MedicineAdder extends StatefulWidget {
  final TextEditingController searchCtrl;
  final TextEditingController dosageCtrl;
  final TextEditingController daysCtrl;
  final TextEditingController qtyCtrl;
  final ValueChanged<PrescriptionItem> onAdd;

  const _MedicineAdder({
    required this.searchCtrl,
    required this.dosageCtrl,
    required this.daysCtrl,
    required this.qtyCtrl,
    required this.onAdd,
  });

  @override
  State<_MedicineAdder> createState() => _MedicineAdderState();
}

class _MedicineAdderState extends State<_MedicineAdder> {
  String? _selectedId;
  String? _selectedName;

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Autocomplete<String>(
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) return const [];
                  final q = textEditingValue.text.toLowerCase();
                  return inv.medicines
                      .where((m) => m.name.toLowerCase().contains(q))
                      .map((m) => '${m.id}||${m.name}')
                      .take(8);
                },
                displayStringForOption: (opt) => opt.split('||').last,
                onSelected: (option) {
                  final parts = option.split('||');
                  setState(() {
                    _selectedId = parts[0];
                    _selectedName = parts[1];
                  });
                  widget.searchCtrl.text = parts[1];
                },
                fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextField(
                  controller: ctrl,
                  focusNode: focus,
                  decoration: const InputDecoration(
                    hintText: 'Search medicine...',
                    prefixIcon: Icon(Icons.medication_outlined),
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 70,
              child: TextField(
                controller: widget.qtyCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Qty', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 70,
              child: TextField(
                controller: widget.daysCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Days', isDense: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.dosageCtrl,
                decoration: const InputDecoration(
                  hintText: 'Dosage e.g. 1-0-1 after meals',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add'),
              onPressed: _selectedName != null ? _addItem : null,
            ),
          ],
        ),
      ],
    );
  }

  void _addItem() {
    if (_selectedName == null) return;
    final qty = int.tryParse(widget.qtyCtrl.text) ?? 1;
    final days = int.tryParse(widget.daysCtrl.text) ?? 3;
    final inv = context.read<InventoryProvider>();
    final med =
        inv.medicines.where((m) => m.id.toString() == _selectedId).firstOrNull;
    final isAvailable = med != null && med.storeStock > 0;

    widget.onAdd(PrescriptionItem(
      medicineId: int.tryParse(_selectedId ?? '0') ?? 0,
      medicineName: _selectedName!,
      qty: qty,
      dosage: widget.dosageCtrl.text.trim(),
      days: days,
      isAvailable: isAvailable,
    ));

    setState(() {
      _selectedId = null;
      _selectedName = null;
      widget.searchCtrl.clear();
      widget.dosageCtrl.clear();
      widget.qtyCtrl.text = '1';
      widget.daysCtrl.text = '3';
    });
  }
}

// ─── Section Header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 8),
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: context.borderColor)),
      ],
    );
  }
}

// ─── Vital Field ───────────────────────────────────────────────────────────────
class _VitalField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String hint;

  const _VitalField(
      {required this.ctrl, required this.label, required this.hint});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
        ),
      ),
    );
  }
}
