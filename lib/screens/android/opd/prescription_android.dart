import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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

  // Attached images
  final List<String> _imagePaths = [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          IconButton(
            onPressed: () => _loadTemplateDialog(context),
            icon: const Icon(Icons.auto_stories_outlined, size: 20),
            tooltip: 'Templates',
          ),
          IconButton(
            onPressed: () => _saveAsTemplateDialog(context),
            icon: const Icon(Icons.bookmark_add_outlined, size: 20),
            tooltip: 'Save Template',
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primary, AppTheme.primaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: _saving ? null : _save,
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_outlined, color: Colors.white),
          label: Text(
            _saving ? 'Saving...' : 'Save & Send',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Vitals Section ──────────────────────────
            _buildCard(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionBadge(
                    icon: Icons.monitor_heart_outlined,
                    label: 'Vitals Monitor',
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _VitalField(
                            ctrl: _bpCtrl,
                            label: 'Blood Pressure',
                            unit: 'mmHg'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _VitalField(
                            ctrl: _pulseCtrl, label: 'Pulse', unit: 'BPM'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _VitalField(
                            ctrl: _tempCtrl, label: 'Temperature', unit: '°F'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _VitalField(
                            ctrl: _weightCtrl, label: 'Weight', unit: 'kg'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _VitalField(
                            ctrl: _spo2Ctrl, label: 'SpO2', unit: '%'),
                      ),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Consultation Notes ──────────────────────
            _buildCard(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionBadge(
                    icon: Icons.edit_note,
                    label: 'Consultation Notes',
                  ),
                  const SizedBox(height: 20),
                  _FormLabel('Chief Complaints'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _complaintsCtrl,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                    decoration: InputDecoration(
                      hintText: 'e.g. Severe headache for 2 days...',
                      filled: true,
                      fillColor:
                          isDark ? AppTheme.darkBg : const Color(0xFFF7F9FB),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.primary.withValues(alpha: 0.2),
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FormLabel('Diagnosis / Impression'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _diagnosisCtrl,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'e.g. Viral Syndrome',
                      filled: true,
                      fillColor:
                          isDark ? AppTheme.darkBg : const Color(0xFFF7F9FB),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.primary.withValues(alpha: 0.2),
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FormLabel("Doctor's Clinical Notes"),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 4,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                    decoration: InputDecoration(
                      hintText: 'Additional observations...',
                      filled: true,
                      fillColor:
                          isDark ? AppTheme.darkBg : const Color(0xFFF7F9FB),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.primary.withValues(alpha: 0.2),
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Prescribed Medications ──────────────────
            _buildCard(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionBadge(
                    icon: Icons.medication_outlined,
                    label: 'Prescribed Medications',
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _MedicineAdder(
                      searchCtrl: _medSearchCtrl,
                      dosageCtrl: _dosageCtrl,
                      daysCtrl: _daysCtrl,
                      qtyCtrl: _qtyCtrl,
                      onAdd: (item) => setState(() => _items.add(item)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._items.asMap().entries.map((entry) {
                    final i = entry.key;
                    final item = entry.value;
                    return _MedicineListItem(
                      index: i + 1,
                      name: item.medicineName,
                      details:
                          'Qty: ${item.qty}  •  ${item.dosage.isNotEmpty ? item.dosage : "No dosage"}  •  ${item.days} days',
                      onDelete: () => setState(() => _items.removeAt(i)),
                      isDark: isDark,
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Lab Tests ──────────────────────────────
            _buildCard(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionBadge(
                    icon: Icons.science_outlined,
                    label: 'Diagnostic Lab Orders',
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _labTestCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search and add lab tests...',
                      hintStyle: TextStyle(
                          color: context.textMutedColor, fontSize: 13),
                      prefixIcon: Icon(Icons.search,
                          color: context.textMutedColor, size: 20),
                      filled: true,
                      fillColor:
                          isDark ? AppTheme.darkBg : const Color(0xFFF7F9FB),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: AppTheme.primary.withValues(alpha: 0.2),
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                    onSubmitted: (_) => _addLabTest(),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ..._labTests.asMap().entries.map((entry) {
                        return _LabTestChip(
                          label: entry.value,
                          onDelete: () =>
                              setState(() => _labTests.removeAt(entry.key)),
                        );
                      }),
                      InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => _addLabTest(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: context.borderColor,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add,
                                  size: 16, color: context.textMutedColor),
                              const SizedBox(width: 4),
                              Text(
                                'Custom Test',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: context.textMutedColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Attach Images ──────────────────────────
            _buildCard(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionBadge(
                    icon: Icons.attach_file_outlined,
                    label: 'Attach Prescription Images',
                  ),
                  const SizedBox(height: 20),
                  if (_imagePaths.isNotEmpty) ...[
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _imagePaths.asMap().entries.map((entry) {
                        return _ImageThumbnail(
                          path: entry.value,
                          onDelete: () =>
                              setState(() => _imagePaths.removeAt(entry.key)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    children: [
                      _UploadButton(
                        icon: Icons.photo_library_outlined,
                        label: 'Gallery',
                        onTap: () => _pickImage(ImageSource.gallery),
                      ),
                      const SizedBox(width: 12),
                      _UploadButton(
                        icon: Icons.camera_alt_outlined,
                        label: 'Camera',
                        onTap: () => _pickImage(ImageSource.camera),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required bool isDark, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppTheme.darkBorder.withValues(alpha: 0.5)
              : const Color(0xFFE8ECF0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
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

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 80);
    if (picked != null) {
      setState(() => _imagePaths.add(picked.path));
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
      content: Text('Template "${t.name}" applied'),
      backgroundColor: AppTheme.success,
    ));
  }

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

// ─── Section Badge ─────────────────────────────────────────────────────────
class _SectionBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: AppTheme.primary),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
        ),
      ],
    );
  }
}

// ─── Form Label ────────────────────────────────────────────────────────────
class _FormLabel extends StatelessWidget {
  final String text;
  const _FormLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: context.textMutedColor,
      ),
    );
  }
}

// ─── Vital Field ───────────────────────────────────────────────────────────
class _VitalField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String unit;

  const _VitalField({
    required this.ctrl,
    required this.label,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormLabel(label),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            filled: true,
            fillColor: isDark ? AppTheme.darkBg : const Color(0xFFF7F9FB),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppTheme.primary.withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                unit,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: context.textMutedColor.withValues(alpha: 0.5),
                  letterSpacing: 0.5,
                ),
              ),
            ),
            suffixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
          ),
        ),
      ],
    );
  }
}

// ─── Medicine Adder (Keyboard-driven workflow) ─────────────────────────────
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

  final _qtyFocus = FocusNode();
  final _daysFocus = FocusNode();
  final _dosageFocus = FocusNode();
  final _addBtnFocus = FocusNode();

  @override
  void dispose() {
    _qtyFocus.dispose();
    _daysFocus.dispose();
    _dosageFocus.dispose();
    _addBtnFocus.dispose();
    super.dispose();
  }

  /// Format dosage: "101" → "1-0-1", "211" → "2-1-1"
  String _formatDosage(String raw) {
    final trimmed = raw.trim();
    if (trimmed.contains('-')) return trimmed;
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 2 && digits.length <= 3) {
      return digits.split('').join('-');
    }
    return trimmed;
  }

  void _onMedicineSelected(String option) {
    final parts = option.split('||');
    setState(() {
      _selectedId = parts[0];
      _selectedName = parts[1];
    });
    widget.searchCtrl.text = parts[1];
    _qtyFocus.requestFocus();
  }

  void _onQtyEditingComplete() => _daysFocus.requestFocus();

  void _onDaysEditingComplete() => _dosageFocus.requestFocus();

  void _onDosageEditingComplete() {
    widget.dosageCtrl.text = _formatDosage(widget.dosageCtrl.text);
    _addBtnFocus.requestFocus();
  }

  void _addItem() {
    if (_selectedName == null) return;
    final formattedDosage = _formatDosage(widget.dosageCtrl.text.trim());
    widget.dosageCtrl.text = formattedDosage;

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
      dosage: formattedDosage,
      days: days,
      isAvailable: isAvailable,
    ));

    setState(() {
      _selectedId = null;
      _selectedName = null;
    });
    widget.searchCtrl.clear();
    widget.dosageCtrl.clear();
    widget.qtyCtrl.text = '1';
    widget.daysCtrl.text = '3';
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();

    return Column(
      children: [
        Autocomplete<String>(
          optionsBuilder: (textEditingValue) {
            if (textEditingValue.text.isEmpty) return const [];
            final q = textEditingValue.text.toLowerCase();
            return inv.medicines
                .where((m) => m.name.toLowerCase().contains(q))
                .map((m) => '${m.id}||${m.name}')
                .take(8);
          },
          displayStringForOption: (opt) => opt.split('||').last,
          onSelected: _onMedicineSelected,
          fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextField(
            controller: ctrl,
            focusNode: focus,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search medicine, Enter to select...',
              hintStyle: TextStyle(color: context.textMutedColor, fontSize: 13),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(color: context.borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(color: context.borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide:
                    const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 64,
              child: _SmallField(
                controller: widget.qtyCtrl,
                label: 'Qty',
                focusNode: _qtyFocus,
                onEditingComplete: _onQtyEditingComplete,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 64,
              child: _SmallField(
                controller: widget.daysCtrl,
                label: 'Days',
                focusNode: _daysFocus,
                onEditingComplete: _onDaysEditingComplete,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FormLabel('Dosage'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: widget.dosageCtrl,
                    focusNode: _dosageFocus,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '1-0-1 or just type 101',
                      hintStyle: TextStyle(
                          color: context.textMutedColor, fontSize: 13),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: context.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: context.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(
                            color: AppTheme.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    onEditingComplete: _onDosageEditingComplete,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Focus(
              focusNode: _addBtnFocus,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  if (_selectedName != null) _addItem();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: _selectedName != null
                      ? AppTheme.primary
                      : AppTheme.primary.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(21),
                    onTap: _selectedName != null ? _addItem : null,
                    child: const Icon(Icons.add, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Small Field (Qty / Days) ──────────────────────────────────────────────
class _SmallField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final VoidCallback? onEditingComplete;

  const _SmallField({
    required this.controller,
    required this.label,
    this.focusNode,
    this.onEditingComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormLabel(label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: context.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: context.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          ),
          onEditingComplete: onEditingComplete,
        ),
      ],
    );
  }
}

// ─── Medicine List Item ────────────────────────────────────────────────────
class _MedicineListItem extends StatelessWidget {
  final int index;
  final String name;
  final String details;
  final VoidCallback onDelete;
  final bool isDark;

  const _MedicineListItem({
    required this.index,
    required this.name,
    required this.details,
    required this.onDelete,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkBg : const Color(0xFFF7F9FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.borderColor),
            ),
            child: const Icon(Icons.medication_outlined,
                size: 18, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  details,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: context.textMutedColor,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onDelete,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.cancel_outlined,
                  size: 20,
                  color: context.textMutedColor.withValues(alpha: 0.3)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Lab Test Chip ─────────────────────────────────────────────────────────
class _LabTestChip extends StatelessWidget {
  final String label;
  final VoidCallback onDelete;

  const _LabTestChip({required this.label, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onDelete,
            child: Icon(
              Icons.close,
              size: 14,
              color: AppTheme.primary.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Image Thumbnail ───────────────────────────────────────────────────────
class _ImageThumbnail extends StatelessWidget {
  final String path;
  final VoidCallback onDelete;

  const _ImageThumbnail({required this.path, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(path),
            width: 90,
            height: 90,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onDelete,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppTheme.danger,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Upload Button ─────────────────────────────────────────────────────────
class _UploadButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _UploadButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.primary.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
