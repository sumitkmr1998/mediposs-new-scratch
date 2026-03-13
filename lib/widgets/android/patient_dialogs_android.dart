import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/models/patient.dart';
import '../../shared/models/doctor.dart';
import '../../shared/providers/patient_provider.dart';
import '../../shared/providers/opd_provider.dart';
import '../../shared/services/sync_service.dart';
import '../../theme/app_theme.dart';

class AndroidPatientDialogs {
  // ─── 1. Patient Registration / Edit Bottom Sheet ───────────────────────────
  static Future<Patient?> showRegistrationSheet(BuildContext context,
      {Patient? patient}) {
    return showModalBottomSheet<Patient>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PatientRegistrationSheet(patient: patient),
    );
  }

  // ─── 2. Patient Search Bottom Sheet ────────────────────────────────────────
  static Future<void> showSearchSheet(
    BuildContext context, {
    required Function(Patient) onSelected,
    bool showSkip = true,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PatientSearchSheet(
        onSelected: onSelected,
        showSkip: showSkip,
      ),
    );
  }

  // ─── 3. Book Appointment Bottom Sheet ──────────────────────────────────────
  static Future<void> showBookingSheet(BuildContext context,
      {required Patient patient}) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _BookAppointmentSheet(patient: patient),
    );
  }
}

// ─── Internal Sheet Implementations ───

class _PatientRegistrationSheet extends StatefulWidget {
  final Patient? patient;
  const _PatientRegistrationSheet({this.patient});

  @override
  State<_PatientRegistrationSheet> createState() =>
      _PatientRegistrationSheetState();
}

class _PatientRegistrationSheetState extends State<_PatientRegistrationSheet> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String _gender = 'Male';
  final List<String> _genders = ['Male', 'Female', 'Other'];

  @override
  void initState() {
    super.initState();
    if (widget.patient != null) {
      _nameCtrl.text = widget.patient!.name;
      _phoneCtrl.text = widget.patient!.phone;
      _addressCtrl.text = widget.patient!.address;
      _gender = widget.patient!.gender;
      _ageCtrl.text = widget.patient!.age.toString();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _ageCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Widget _buildField({
    required TextEditingController controller,
    required String labelText,
    IconData? prefixIcon,
    TextInputType? keyboardType,
    String? suffixText,
    bool autofocus = false,
    int maxLines = 1,
    TextInputAction textInputAction = TextInputAction.next,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: TextStyle(color: context.textMutedColor),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: AppTheme.primaryLight)
            : null,
        suffixText: suffixText,
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

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.patient != null;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grab Handle
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
                    isEdit ? 'Edit Patient' : 'Register New Patient',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryLight),
                  ),
                  if (isEdit)
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              _buildField(
                controller: _nameCtrl,
                autofocus: !isEdit,
                labelText: 'Full Name *',
                prefixIcon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                labelText: 'Phone Number',
                prefixIcon: Icons.phone_outlined,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _gender,
                      decoration: InputDecoration(
                        labelText: 'Gender',
                        labelStyle: TextStyle(color: context.textMutedColor),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: context.borderColor
                                    .withValues(alpha: 0.5))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: context.borderColor
                                    .withValues(alpha: 0.5))),
                        filled: true,
                        fillColor: Theme.of(context).scaffoldBackgroundColor,
                        isDense: true,
                      ),
                      dropdownColor: context.surfaceColor,
                      items: _genders
                          .map(
                              (g) => DropdownMenuItem(value: g, child: Text(g)))
                          .toList(),
                      onChanged: (v) => setState(() => _gender = v!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: _buildField(
                      controller: _ageCtrl,
                      keyboardType: TextInputType.number,
                      labelText: 'Age',
                      suffixText: 'yrs',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _addressCtrl,
                maxLines: 2,
                textInputAction: TextInputAction.done,
                labelText: 'Address',
                prefixIcon: Icons.location_on_outlined,
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    if (_nameCtrl.text.trim().isEmpty) return;
                    final provider = context.read<PatientProvider>();
                    final p = widget.patient ??
                        Patient(uhid: '', name: '', gender: 'Male');
                    p.name = _nameCtrl.text.trim();
                    p.phone = _phoneCtrl.text.trim();
                    p.gender = _gender;
                    p.age = int.tryParse(_ageCtrl.text) ?? 0;
                    p.address = _addressCtrl.text.trim();

                    final saved =
                        provider.savePatient(p, context.read<SyncService>());
                    Navigator.pop(context, saved);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            isEdit ? 'Patient updated' : 'Patient registered'),
                        backgroundColor: AppTheme.success,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: Text(isEdit ? 'Save Changes' : 'Register Patient',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
              if (!isEdit)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.grey)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatientSearchSheet extends StatefulWidget {
  final Function(Patient) onSelected;
  final bool showSkip;

  const _PatientSearchSheet({required this.onSelected, this.showSkip = true});

  @override
  State<_PatientSearchSheet> createState() => _PatientSearchSheetState();
}

class _PatientSearchSheetState extends State<_PatientSearchSheet> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final patients = context.watch<PatientProvider>().patients;
    final query = _searchCtrl.text.toLowerCase();
    final filtered = patients.where((p) {
      return p.name.toLowerCase().contains(query) ||
          p.phone.contains(query) ||
          p.address.toLowerCase().contains(query) ||
          p.uhid.toLowerCase().contains(query);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Select Patient',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryLight)),
                if (widget.showSkip)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Skip / Walk-in'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by Name, Phone, Address...',
                hintStyle: TextStyle(color: context.textMutedColor),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.primaryLight),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                        color: context.borderColor.withValues(alpha: 0.5))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                        color: context.borderColor.withValues(alpha: 0.5))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide:
                        const BorderSide(color: AppTheme.primary, width: 2)),
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_off_outlined,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No matching patient found.',
                            style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final p = filtered[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color:
                                  context.borderColor.withValues(alpha: 0.5)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor:
                                AppTheme.primary.withValues(alpha: 0.1),
                            child: Text(p.name[0].toUpperCase(),
                                style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.bold)),
                          ),
                          title: Text(p.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${p.phone} • ${p.address}',
                              style: TextStyle(color: context.textMutedColor)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(p.uhid,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: context.textMutedColor,
                                    fontWeight: FontWeight.w600)),
                          ),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          onTap: () {
                            Navigator.pop(context);
                            widget.onSelected(p);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _BookAppointmentSheet extends StatefulWidget {
  final Patient patient;
  const _BookAppointmentSheet({required this.patient});

  @override
  State<_BookAppointmentSheet> createState() => _BookAppointmentSheetState();
}

class _BookAppointmentSheetState extends State<_BookAppointmentSheet> {
  Doctor? _selectedDoctor;

  @override
  Widget build(BuildContext context) {
    final opd = context.watch<OpdProvider>();
    final doctors = opd.activeDoctors;

    if (_selectedDoctor != null &&
        !doctors.any((d) => d.id == _selectedDoctor!.id)) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => setState(() => _selectedDoctor = null));
    }
    final resolvedDoctor = _selectedDoctor == null
        ? null
        : doctors.where((d) => d.id == _selectedDoctor!.id).firstOrNull;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: context.borderColor.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  radius: 24,
                  child: Text(widget.patient.name[0].toUpperCase(),
                      style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 20)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Book Appointment for',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.primaryLight,
                              fontWeight: FontWeight.bold)),
                      Text(widget.patient.name,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(widget.patient.uhid,
                      style: TextStyle(
                          fontSize: 12,
                          color: context.textMutedColor,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (doctors.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No active doctors available.',
                    style: TextStyle(
                        color: AppTheme.danger, fontWeight: FontWeight.bold)),
              ),
            )
          else
            DropdownButtonFormField<Doctor>(
              value: resolvedDoctor,
              decoration: InputDecoration(
                labelText: 'Select Doctor',
                labelStyle: TextStyle(color: context.textMutedColor),
                prefixIcon: const Icon(Icons.medical_services_outlined,
                    color: AppTheme.primaryLight),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                        color: context.borderColor.withValues(alpha: 0.5))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                        color: context.borderColor.withValues(alpha: 0.5))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide:
                        const BorderSide(color: AppTheme.primary, width: 2)),
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
                isDense: true,
              ),
              dropdownColor: context.surfaceColor,
              items: doctors
                  .map((d) =>
                      DropdownMenuItem(value: d, child: Text('Dr. ${d.name}')))
                  .toList(),
              onChanged: (d) => setState(() => _selectedDoctor = d),
            ),
          if (resolvedDoctor != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.05),
                  border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Specialization',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(resolvedDoctor.specialization,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Fee',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                          '₹${resolvedDoctor.consultationFee.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppTheme.primary,
                              fontSize: 18)),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: resolvedDoctor == null
                  ? null
                  : () async {
                      final appt = await opd.createAppointment(
                        patientId: widget.patient.id,
                        patientName: widget.patient.name,
                        patientPhone: widget.patient.phone,
                        doctorId: resolvedDoctor.id,
                        doctorName: resolvedDoctor.name,
                        consultationFee: resolvedDoctor.consultationFee,
                        syncService: context.read<SyncService>(),
                      );
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                'Token #${appt.tokenNumber} booked for ${widget.patient.name}'),
                            backgroundColor: AppTheme.success),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text('Confirm Booking',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
