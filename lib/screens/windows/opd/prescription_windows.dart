import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../shared/models/appointment.dart';
import '../../../shared/models/prescription.dart';
import '../../../shared/providers/prescription_provider.dart';
import '../../../shared/providers/inventory_provider.dart';
import '../../../shared/providers/template_provider.dart';
import '../../../shared/providers/patient_provider.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/services/sync_service.dart';
import '../../../theme/app_theme.dart';
import '../../../shared/providers/procedure_provider.dart';
import 'patient_details_windows.dart';
import '../../../widgets/windows_camera_dialog.dart';
import '../../../widgets/phone_camera_dialog.dart';
import '../../../shared/services/objectbox_service.dart';
import 'package:lucide_icons/lucide_icons.dart';

class PrescriptionWindows extends StatefulWidget {
  final Appointment appointment;

  const PrescriptionWindows({super.key, required this.appointment});

  @override
  State<PrescriptionWindows> createState() => _PrescriptionWindowsState();
}

class _PrescriptionWindowsState extends State<PrescriptionWindows> {
  // Session-based draft system: persists data even if navigating away and back
  static final Map<int, Map<String, dynamic>> _sessionDrafts = {};

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
  List<String> _procedures = [];
  final _procedureCtrl = TextEditingController();

  // Attached images
  final List<String> _imagePaths = [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 1. Check if a session draft exists for this appointment
      if (_sessionDrafts.containsKey(widget.appointment.id)) {
        final draft = _sessionDrafts[widget.appointment.id]!;
        _diagnosisCtrl.text = draft['diagnosis'] ?? '';
        _complaintsCtrl.text = draft['complaints'] ?? '';
        _notesCtrl.text = draft['notes'] ?? '';
        _bpCtrl.text = draft['bp'] ?? '';
        _weightCtrl.text = draft['weight'] ?? '';
        _tempCtrl.text = draft['temp'] ?? '';
        _spo2Ctrl.text = draft['spo2'] ?? '';
        _pulseCtrl.text = draft['pulse'] ?? '';
        setState(() {
          _items = draft['items'] ?? [];
          _labTests = draft['labTests'] ?? [];
          _procedures = draft['procedures'] ?? [];
          _imagePaths.addAll(draft['imagePaths'] ?? []);
        });
        return;
      }

      // 2. If no draft, check for existing saved prescription in DB
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
          _procedures = pProvider.getProcedures(existing);
          _imagePaths.addAll(pProvider.getImages(existing));
        });
      }
    });
  }

  void _updateDraft() {
    _sessionDrafts[widget.appointment.id] = {
      'diagnosis': _diagnosisCtrl.text,
      'complaints': _complaintsCtrl.text,
      'notes': _notesCtrl.text,
      'bp': _bpCtrl.text,
      'weight': _weightCtrl.text,
      'temp': _tempCtrl.text,
      'spo2': _spo2Ctrl.text,
      'pulse': _pulseCtrl.text,
      'items': _items,
      'labTests': _labTests,
      'procedures': _procedures,
      'imagePaths': _imagePaths,
    };
  }

  @override
  void dispose() {
    _updateDraft(); // Save draft before disposal
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
    _procedureCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inv = context.watch<InventoryProvider>();

    final patient =
        context.watch<PatientProvider>().getById(widget.appointment.patientId);

    return Scaffold(
      body: Column(
        children: [
          // ── Premium Hero Header (Matching Patient Details style) ──
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0A5D5F),
                  AppTheme.primary,
                  AppTheme.primaryLight
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white, size: 20),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 2.5),
                      ),
                      child: Center(
                        child: Text(
                          patient?.name.isNotEmpty == true
                              ? patient!.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(widget.appointment.patientName,
                                  style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: -0.5)),
                              const SizedBox(width: 12),
                              _HeaderMiniBadge(
                                text: 'Token #${widget.appointment.tokenNumber}',
                                color: Colors.orangeAccent,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _HeroBadge(
                                  text: patient?.uhid ?? widget.appointment.patientId.toString(),
                                  icon: Icons.badge_outlined),
                              if (patient != null) ...[
                                _HeroBadge(
                                    text: '${patient.ageYears} yrs / ${patient.gender}',
                                    icon: Icons.person_search_outlined),
                              ],
                              _HeroBadge(
                                  text: 'Dr. ${widget.appointment.doctorName}',
                                  icon: Icons.medical_services_outlined),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Action Buttons (Integrated into Header)
                    Row(
                      children: [
                        _HeaderActionBtn(
                          icon: Icons.history_rounded,
                          tooltip: 'Import Previous',
                          onTap: () => _showImportPreviousDialog(context),
                        ),
                        const SizedBox(width: 8),
                        _HeaderActionBtn(
                          icon: Icons.auto_stories_outlined,
                          tooltip: 'Templates',
                          onTap: () => _loadTemplateDialog(context),
                        ),
                        const SizedBox(width: 8),
                        _HeaderActionBtn(
                          icon: Icons.contact_page_outlined,
                          tooltip: 'View History',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PatientDetailsWindows(
                                  patientId: widget.appointment.patientId,
                                  fromAppointmentId: widget.appointment.id,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        _HeaderActionBtn(
                          icon: Icons.bookmark_add_outlined,
                          tooltip: 'Save Template',
                          onTap: () => _saveAsTemplateDialog(context),
                        ),
                        const SizedBox(width: 12),
                        Container(width: 1.5, height: 32, color: Colors.white24),
                        const SizedBox(width: 12),
                        _SaveButtonUI(saving: _saving, onTap: _save),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // ── Vitals Section ──────────────────────────
            _buildCard(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionBadge(
                    icon: Icons.monitor_heart_outlined,
                    label: 'Vitals Monitor',
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _VitalField(
                            ctrl: _bpCtrl,
                            label: 'Blood Pressure',
                            unit: 'mmHg'),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _VitalField(
                            ctrl: _pulseCtrl, label: 'Pulse', unit: 'BPM'),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _VitalField(
                            ctrl: _tempCtrl, label: 'Temperature', unit: '°F'),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _VitalField(
                            ctrl: _weightCtrl, label: 'Weight', unit: 'kg'),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _VitalField(
                            ctrl: _spo2Ctrl, label: 'SpO2', unit: '%'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Two Column: Consultation + Medications ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Consultation Notes
                Expanded(
                  flex: 5,
                  child: _buildCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionBadge(
                          icon: Icons.edit_note,
                          label: 'Consultation Notes',
                        ),
                        const SizedBox(height: 24),
                        const _FormLabel('Chief Complaints'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _complaintsCtrl,
                          maxLines: 3,
                          style: const TextStyle(fontSize: 13, height: 1.5),
                          decoration: InputDecoration(
                            hintText: 'e.g. Severe headache for 2 days...',
                            filled: true,
                            fillColor:
                                isDark ? AppTheme.darkBg : AppTheme.inputBg,
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
                        const SizedBox(height: 20),
                        const _FormLabel('Diagnosis / Impression'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _diagnosisCtrl,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText: 'e.g. Viral Syndrome',
                            filled: true,
                            fillColor:
                                isDark ? AppTheme.darkBg : AppTheme.inputBg,
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
                        const SizedBox(height: 20),
                        const _FormLabel("Doctor's Clinical Notes"),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _notesCtrl,
                          maxLines: 5,
                          style: const TextStyle(fontSize: 13, height: 1.5),
                          decoration: InputDecoration(
                            hintText: 'Additional observations...',
                            filled: true,
                            fillColor:
                                isDark ? AppTheme.darkBg : AppTheme.inputBg,
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
                ),
                const SizedBox(width: 20),

                // Right: Medications + Lab Tests
                Expanded(
                  flex: 7,
                  child: Column(
                    children: [
                      // Prescribed Medications
                      _buildCard(
                        isDark: isDark,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionBadge(
                              icon: Icons.medication_outlined,
                              label: 'Prescribed Medications',
                            ),
                            const SizedBox(height: 20),
                            // Medicine adder area
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: _MedicineAdder(
                                searchCtrl: _medSearchCtrl,
                                dosageCtrl: _dosageCtrl,
                                daysCtrl: _daysCtrl,
                                qtyCtrl: _qtyCtrl,
                                onAdd: (item) =>
                                    setState(() => _items.add(item)),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Medicine list
                            ..._items.asMap().entries.map((entry) {
                              final i = entry.key;
                              final item = entry.value;
                              final med = inv.medicines.where((m) => m.id == item.medicineId).firstOrNull;
                              final stockText = med != null ? '  •  Stock: ${med.storeStock}' : '';
                              return _MedicineListItem(
                                index: i + 1,
                                name: item.medicineName,
                                details:
                                    'Qty: ${item.qty}  •  ${item.dosage.isNotEmpty ? item.dosage : "No dosage"}  •  ${item.days} days$stockText',
                                onDelete: () =>
                                    setState(() => _items.removeAt(i)),
                                isDark: isDark,
                                isLowStock: med?.isLowStock ?? false,
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Lab Tests
                      _buildCard(
                        isDark: isDark,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionBadge(
                              icon: Icons.science_outlined,
                              label: 'Diagnostic Lab Orders',
                            ),
                            const SizedBox(height: 20),
                            // Search field
                            TextField(
                              controller: _labTestCtrl,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText:
                                    'Search and add lab tests (e.g., CBC, Glucose)...',
                                hintStyle: TextStyle(
                                    color: context.textMutedColor,
                                    fontSize: 13),
                                prefixIcon: Icon(Icons.search,
                                    color: context.textMutedColor, size: 20),
                                filled: true,
                                fillColor:
                                    isDark ? AppTheme.darkBg : AppTheme.inputBg,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(
                                    color:
                                        AppTheme.primary.withValues(alpha: 0.2),
                                    width: 2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                              ),
                              onSubmitted: (_) => _addLabTest(),
                            ),
                            const SizedBox(height: 16),
                            // Lab test chips
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                ..._labTests.asMap().entries.map((entry) {
                                  return _LabTestChip(
                                    label: entry.value,
                                    onDelete: () => setState(
                                        () => _labTests.removeAt(entry.key)),
                                  );
                                }),
                                // Add custom test button
                                InkWell(
                                  borderRadius: BorderRadius.circular(24),
                                  onTap: () => _addLabTest(),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: context.borderColor,
                                        style: BorderStyle.solid,
                                        width: 1.5,
                                      ),
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.add,
                                            size: 16,
                                            color: context.textMutedColor),
                                        const SizedBox(width: 6),
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
                      const SizedBox(height: 20),

                      // ── Cosmetic Procedures ─────────────────────
                      _buildCard(
                        isDark: isDark,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionBadge(
                              icon: Icons.auto_awesome_outlined,
                              label: 'Cosmetic Procedures',
                            ),
                            const SizedBox(height: 20),
                            Consumer<ProcedureProvider>(
                              builder: (context, procProv, _) {
                                return Autocomplete<String>(
                                  optionsBuilder: (textEditingValue) {
                                    final query =
                                        textEditingValue.text.toLowerCase();
                                    return procProv.procedures
                                        .where((p) => p.name
                                            .toLowerCase()
                                            .contains(query))
                                        .map((p) => p.name)
                                        .toList();
                                  },
                                  onSelected: (selection) {
                                    _onProcedureSelected(selection);
                                  },
                                  fieldViewBuilder: (context, controller,
                                      focusNode, onFieldSubmitted) {
                                    return TextField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: InputDecoration(
                                        hintText:
                                            'Search procedures (Laser, Peel, etc.)...',
                                        hintStyle: TextStyle(
                                            color: context.textMutedColor,
                                            fontSize: 13),
                                        prefixIcon: Icon(Icons.search,
                                            color: context.textMutedColor,
                                            size: 20),
                                        filled: true,
                                        fillColor: isDark
                                            ? AppTheme.darkBg
                                            : AppTheme.inputBg,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(24),
                                          borderSide: BorderSide(
                                            color: AppTheme.primary
                                                .withValues(alpha: 0.2),
                                            width: 2,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 20, vertical: 14),
                                      ),
                                      onSubmitted: (val) {
                                        if (val.trim().isNotEmpty) {
                                          _onProcedureSelected(val.trim());
                                        }
                                        controller.clear();
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                ..._procedures.asMap().entries.map((entry) {
                                  final parts = entry.value.split('||');
                                  final name = parts[0];
                                  final priceText = parts.length > 1 ? ' (₹${parts[1]})' : '';
                                  return _LabTestChip(
                                    label: '$name$priceText',
                                    onDelete: () => setState(() =>
                                        _procedures.removeAt(entry.key)),
                                  );
                                }),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Attach Images ──────────────────────────
                      _buildCard(
                        isDark: isDark,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionBadge(
                              icon: Icons.attach_file_outlined,
                              label: 'Attach Prescription Images',
                            ),
                            const SizedBox(height: 20),
                            if (_imagePaths.isNotEmpty) ...[
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children:
                                    _imagePaths.asMap().entries.map((entry) {
                                  return _ImageThumbnail(
                                    path: entry.value,
                                    onDelete: () => setState(
                                        () => _imagePaths.removeAt(entry.key)),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 16),
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
              ],
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    ),
  ],
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
              : AppTheme.lightBorder,
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

  void _addProcedure(String name) {
    final proc = name.trim();
    if (proc.isNotEmpty) {
      setState(() {
        // Prevent duplicate adds of the same procedure name (ignoring price values)
        _procedures.removeWhere((p) => p.split('||')[0].toLowerCase() == proc.split('||')[0].toLowerCase());
        _procedures.add(proc);
        _procedureCtrl.clear();
      });
    }
  }

  void _onProcedureSelected(String name) {
    final procProv = context.read<ProcedureProvider>();
    final proc = procProv.procedures.where((p) => p.name.toLowerCase() == name.toLowerCase()).firstOrNull;
    final defaultPrice = proc?.basePrice ?? 0.0;
    _showProcedurePriceDialog(name, defaultPrice);
  }

  void _showProcedurePriceDialog(String procedureName, double defaultPrice) {
    final priceCtrl = TextEditingController(text: defaultPrice.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Procedure Price/Value'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter recommended price/value for "$procedureName":',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Price (₹)',
                isDense: true,
              ),
              onSubmitted: (val) {
                final price = double.tryParse(val) ?? defaultPrice;
                _addProcedure('$procedureName||${price.toStringAsFixed(2)}');
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final price = double.tryParse(priceCtrl.text) ?? defaultPrice;
              _addProcedure('$procedureName||${price.toStringAsFixed(2)}');
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    if (source == ImageSource.camera && Platform.isWindows) {
      // Show menu to choose between Windows Camera (Webcam) or Phone Camera
      final result = await showMenu<String>(
        context: context,
        position:
            const RelativeRect.fromLTRB(100, 100, 100, 100), // Approximate
        items: [
          const PopupMenuItem(
            value: 'webcam',
            child: Row(
              children: [
                Icon(LucideIcons.camera, size: 18),
                SizedBox(width: 12),
                Text('Use Web Camera'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'phone',
            child: Row(
              children: [
                Icon(LucideIcons.smartphone, size: 18),
                SizedBox(width: 12),
                Text('Use Phone Camera'),
              ],
            ),
          ),
        ],
      );

      if (result == 'webcam') {
        final path = await showDialog<String>(
          context: context,
          builder: (ctx) => const WindowsCameraDialog(),
        );
        if (path != null) setState(() => _imagePaths.add(path));
      } else if (result == 'phone') {
        // Resolve UHID from Patient box
        final patient = ObjectBoxService.instance.patientBox
            .get(widget.appointment.patientId);
        final uhid = patient?.uhid ?? 'UNKNOWN';

        final receivedPath = await showDialog<String>(
          context: context,
          builder: (ctx) => PhoneCameraDialog(
            patientUhid: uhid,
            patientName: widget.appointment.patientName,
          ),
        );
        if (receivedPath != null) {
          if (mounted) {
            setState(() {
              if (!_imagePaths.contains(receivedPath)) {
                _imagePaths.add(receivedPath);
              }
            });
          }
        }
      }
      return;
    }
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
      await context.read<PrescriptionProvider>().savePrescription(
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
            procedures: _procedures,
            images: _imagePaths,
            vitals: vitals,
            syncService: syncService,
            context: context,
            actor: context.read<AuthProvider>().currentUser,
          );

      _sessionDrafts.remove(widget.appointment.id);
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

  void _applyPrescription(Prescription p) {
    final pProvider = context.read<PrescriptionProvider>();
    setState(() {
      if (p.diagnosis.isNotEmpty) _diagnosisCtrl.text = p.diagnosis;
      if (p.complaints.isNotEmpty) _complaintsCtrl.text = p.complaints;
      if (p.notes.isNotEmpty) _notesCtrl.text = p.notes;
      final pItems = pProvider.getItems(p);
      if (pItems.isNotEmpty) _items = List.from(pItems);
      final pTests = pProvider.getLabTests(p);
      if (pTests.isNotEmpty) _labTests = List.from(pTests);

      final vitals = pProvider.getVitals(p);
      if (vitals.bp.isNotEmpty) _bpCtrl.text = vitals.bp;
      if (vitals.weight.isNotEmpty) _weightCtrl.text = vitals.weight;
      if (vitals.temp.isNotEmpty) _tempCtrl.text = vitals.temp;
      if (vitals.spo2.isNotEmpty) _spo2Ctrl.text = vitals.spo2;
      if (vitals.pulse.isNotEmpty) _pulseCtrl.text = vitals.pulse;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Record from ${DateFormat('dd MMM yyyy').format(p.createdAt)} imported'),
      backgroundColor: AppTheme.success,
    ));
  }

  void _showImportPreviousDialog(BuildContext context) {
    final pProvider = context.read<PrescriptionProvider>();
    final patient = context.read<PatientProvider>().getById(widget.appointment.patientId);
    if (patient == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Error: Patient record not found.'),
      ));
      return;
    }
    
    final past = pProvider
        .getPrescriptionsForPatient(patient)
        .where((p) => p.appointmentId != widget.appointment.id)
        .toList();

    if (past.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No previous medical records found for this patient.'),
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
                    const Icon(Icons.history, color: AppTheme.primary),
                    const SizedBox(width: 10),
                    Text('Import Previous Prescription',
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
                  itemCount: past.length,
                  itemBuilder: (_, i) {
                    final p = past[i];
                    final date = DateFormat('dd MMM yyyy').format(p.createdAt);
                    final itemCount = pProvider.getItems(p).length;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            AppTheme.primary.withValues(alpha: 0.1),
                        child: const Icon(Icons.history_edu_rounded,
                            color: AppTheme.primary, size: 20),
                      ),
                      title: Text(date,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${p.diagnosis.isNotEmpty ? p.diagnosis : "No diagnosis"} • $itemCount medicines',
                        style: TextStyle(
                            color: context.textMutedColor, fontSize: 12),
                      ),
                      trailing: TextButton(
                        onPressed: () {
                          _applyPrescription(p);
                          Navigator.pop(context);
                        },
                        child: const Text('Import'),
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
                fontSize: 17,
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
        const SizedBox(height: 8),
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
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 12),
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

  final _searchFocus = FocusNode();
  final _qtyFocus = FocusNode();
  final _daysFocus = FocusNode();
  final _dosageFocus = FocusNode();
  final _addBtnFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    _qtyFocus.dispose();
    _daysFocus.dispose();
    _dosageFocus.dispose();
    _addBtnFocus.dispose();
    super.dispose();
  }

  /// Format dosage: "101" → "1-0-1", "211" → "2-1-1"
  /// Already formatted like "1-0-1" stays as-is
  String _formatDosage(String raw) {
    final trimmed = raw.trim();
    if (trimmed.contains('-')) return trimmed;
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 2) {
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
    // Move focus to Qty field with a slight delay to allow Autocomplete to close
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _qtyFocus.requestFocus();
    });
  }

  void _onQtyEditingComplete() {
    _daysFocus.requestFocus();
  }

  void _onDaysEditingComplete() {
    _dosageFocus.requestFocus();
  }

  void _onDosageEditingComplete() {
    // Auto-format on Tab/Enter
    final formatted = _formatDosage(widget.dosageCtrl.text);
    widget.dosageCtrl.text = formatted;
    _addBtnFocus.requestFocus();
  }

  void _addItem() {
    if (_selectedName == null) return;
    // Format dosage before adding
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
      widget.searchCtrl.clear();
      widget.dosageCtrl.clear();
      widget.qtyCtrl.text = '1';
      widget.daysCtrl.text = '3';
    });
    // Return focus to search field for the next medicine
    _searchFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Search row
        Row(
          children: [
            Expanded(
              flex: 3,
              child: RawAutocomplete<String>(
                focusNode: _searchFocus,
                textEditingController: widget.searchCtrl,
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) return const [];
                  final q = textEditingValue.text.toLowerCase();
                  return inv.medicines
                      .where((m) => m.name.toLowerCase().contains(q))
                      .map((m) => '${m.id}||${m.name}||${m.storeStock}||${m.isLowStock}')
                      .take(8);
                },
                displayStringForOption: (opt) {
                  final parts = opt.split('||');
                  if (parts.length > 1) return parts[1];
                  return opt;
                },
                onSelected: _onMedicineSelected,
                fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
                  return TextField(
                    controller: ctrl,
                    focusNode: focus,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search medicine, Enter to select...',
                      hintStyle: TextStyle(
                          color: context.textMutedColor, fontSize: 13),
                      filled: true,
                      fillColor: isDark ? AppTheme.darkBg : Colors.white,
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
                          horizontal: 20, vertical: 12),
                    ),
                    onSubmitted: (value) => onSubmit(),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4.0,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 400, // Fixed width for visibility on Windows
                        constraints: const BoxConstraints(maxHeight: 300),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (BuildContext context, int index) {
                            final String option = options.elementAt(index);
                            final bool isHovered =
                                AutocompleteHighlightedOption.of(context) ==
                                    index;
                            final parts = option.split('||');
                            final name = parts.length > 1 ? parts[1] : option;
                            final stock = parts.length > 2 ? parts[2] : '0';
                            final isLow = parts.length > 3 ? parts[3] == 'true' : false;
                            return ListTile(
                              tileColor: isHovered
                                  ? AppTheme.primary.withValues(alpha: 0.1)
                                  : null,
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(name,
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isHovered
                                              ? FontWeight.w700
                                              : FontWeight.normal,
                                          color: isHovered
                                              ? AppTheme.primary
                                              : (isDark ? Colors.white : Colors.black))),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isLow) ...[
                                        const Icon(Icons.warning_amber_rounded,
                                            color: Colors.amber, size: 14),
                                        const SizedBox(width: 4),
                                        Text('Stock: $stock (Low)',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.amber,
                                                fontWeight: FontWeight.w600)),
                                      ] else ...[
                                        Text('Stock: $stock',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: isHovered
                                                    ? AppTheme.primary.withValues(alpha: 0.8)
                                                    : context.textMutedColor)),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              onTap: () => onSelected(option),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Qty → Days → Dosage → Add (Tab flow)
        Row(
          children: [
            SizedBox(
              width: 72,
              child: _SmallField(
                controller: widget.qtyCtrl,
                label: 'Qty',
                isDark: Theme.of(context).brightness == Brightness.dark,
                focusNode: _qtyFocus,
                onEditingComplete: _onQtyEditingComplete,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 72,
              child: _SmallField(
                controller: widget.daysCtrl,
                label: 'Days',
                isDark: Theme.of(context).brightness == Brightness.dark,
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
                      fillColor: isDark ? AppTheme.darkBg : Colors.white,
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
                          horizontal: 20, vertical: 12),
                    ),
                    onEditingComplete: _onDosageEditingComplete,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              children: [
                const SizedBox(height: 18), // Align with fields
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
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: _selectedName != null
                          ? AppTheme.primary
                          : Colors.grey.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                      boxShadow: _selectedName != null
                          ? [
                              BoxShadow(
                                color: AppTheme.primary.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : null,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: _selectedName != null ? _addItem : null,
                        child: Icon(Icons.add_rounded,
                            color: _selectedName != null
                                ? Colors.white
                                : Colors.grey.shade600,
                            size: 28),
                      ),
                    ),
                  ),
                ),
              ],
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
  final bool isDark;
  final FocusNode? focusNode;
  final VoidCallback? onEditingComplete;

  const _SmallField({
    required this.controller,
    required this.label,
    required this.isDark,
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
            fillColor: isDark ? AppTheme.darkBg : Colors.white,
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
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
  final bool isLowStock;

  const _MedicineListItem({
    required this.index,
    required this.name,
    required this.details,
    required this.onDelete,
    required this.isDark,
    this.isLowStock = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkBg : AppTheme.inputBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.borderColor),
            ),
            child: const Icon(Icons.medication_outlined,
                size: 18, color: AppTheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (isLowStock) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 1),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 12),
                            SizedBox(width: 4),
                            Text(
                              'LOW STOCK',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.amber,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
          const SizedBox(width: 8),
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
            width: 100,
            height: 100,
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
            Icon(icon, size: 20, color: AppTheme.primary),
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

// ── Supportive Header Widgets ──────────────────────────────────────────────────

class _HeroBadge extends StatelessWidget {
  final String text;
  final IconData icon;
  const _HeroBadge({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white70),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _HeaderMiniBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _HeaderMiniBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }
}

class _HeaderActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _HeaderActionBtn(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _SaveButtonUI extends StatelessWidget {
  final bool saving;
  final VoidCallback onTap;
  const _SaveButtonUI({required this.saving, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: saving ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (saving)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.primary))
                else
                  const Icon(Icons.check_circle_outline,
                      color: AppTheme.primary, size: 18),
                const SizedBox(width: 10),
                Text(saving ? 'SAVING...' : 'SAVE & PRINT',
                    style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
