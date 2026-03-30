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
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: TextStyle(color: context.textMutedColor, fontWeight: FontWeight.w600, fontSize: 13),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: AppTheme.primaryLight, size: 20)
            : null,
        suffixText: suffixText,
        suffixStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppTheme.primaryLight),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: context.borderColor.withValues(alpha: 0.3))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: context.borderColor.withValues(alpha: 0.3))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
        filled: true,
        fillColor: context.textMutedColor.withValues(alpha: 0.03),
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
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
                color: context.borderColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('SELECT PATIENT',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        color: AppTheme.primaryLight)),
                if (widget.showSkip)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('SKIP / WALK-IN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: context.textMutedColor)),
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
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Search by Name, Phone, UHID...',
                hintStyle: TextStyle(color: context.textMutedColor, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.primaryLight, size: 22),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                        color: context.borderColor.withValues(alpha: 0.3))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                        color: context.borderColor.withValues(alpha: 0.3))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide:
                        const BorderSide(color: AppTheme.primary, width: 2)),
                filled: true,
                fillColor: context.textMutedColor.withValues(alpha: 0.03),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_search_rounded,
                            size: 64, color: context.borderColor.withValues(alpha: 0.2)),
                        const SizedBox(height: 24),
                        const Text('NO MATCHING RECORDS',
                            style: TextStyle(
                                color: Colors.grey,
                                letterSpacing: 1,
                                fontSize: 11,
                                fontWeight: FontWeight.w900)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final p = filtered[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: context.surfaceColor.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))
                          ],
                          border: Border.all(
                              color:
                                  context.borderColor.withValues(alpha: 0.2)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          leading: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(p.name[0].toUpperCase(),
                                  style: const TextStyle(
                                      color: AppTheme.primary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900)),
                            ),
                          ),
                          title: Text(p.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          subtitle: Text('${p.phone} • ${p.address}'.toUpperCase(),
                              style: TextStyle(color: context.textMutedColor, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: context.textMutedColor.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(p.uhid,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: context.textMutedColor,
                                    fontWeight: FontWeight.w900)),
                          ),
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

class _AndroidPaymentChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String selected;
  final Color color;
  final VoidCallback onTap;

  const _AndroidPaymentChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return Expanded(
      child: Material(
        color: isSelected ? color.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? color : context.borderColor.withValues(alpha: 0.3),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(icon, color: isSelected ? color : Colors.grey, size: 24),
                const SizedBox(height: 8),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w900,
                    color: isSelected ? color : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BookAppointmentSheetState extends State<_BookAppointmentSheet> {
  Doctor? _selectedDoctor;
  String _paymentMethod = 'cash';

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

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
                  color: context.borderColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.surfaceColor.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 8))
              ],
              border:
                  Border.all(color: context.borderColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(widget.patient.name[0].toUpperCase(),
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 22)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('APPOINTMENT FOR',
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1,
                              color: AppTheme.primaryLight,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(widget.patient.name,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.textMutedColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(widget.patient.uhid,
                      style: TextStyle(
                          fontSize: 11,
                          color: context.textMutedColor,
                          fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (doctors.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text('NO ACTIVE DOCTORS AVAILABLE'.toUpperCase(),
                    style: const TextStyle(
                        color: AppTheme.danger, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
              ),
            )
          else
            DropdownButtonFormField<Doctor>(
              value: resolvedDoctor,
              decoration: InputDecoration(
                labelText: 'ASSIGN DOCTOR',
                labelStyle: TextStyle(color: context.textMutedColor, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1),
                prefixIcon: const Icon(Icons.medical_services_rounded,
                    color: AppTheme.primaryLight, size: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                        color: context.borderColor.withValues(alpha: 0.3))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                        color: context.borderColor.withValues(alpha: 0.3))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide:
                        const BorderSide(color: AppTheme.primary, width: 2)),
                filled: true,
                fillColor: context.textMutedColor.withValues(alpha: 0.03),
                isDense: true,
              ),
              dropdownColor: context.surfaceColor,
              items: doctors
                  .map((d) =>
                      DropdownMenuItem(value: d, child: Text('Dr. ${d.name}', style: const TextStyle(fontWeight: FontWeight.w700))))
                  .toList(),
              onChanged: (d) => setState(() => _selectedDoctor = d),
            ),
          if (resolvedDoctor != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.05),
                  border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SPECIALIZATION',
                          style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text(resolvedDoctor.specialization.toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('CONSULTATION FEE',
                          style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text(
                          '₹${resolvedDoctor.consultationFee.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppTheme.primary,
                              fontSize: 22)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('PAYMENT INSTRUMENT',
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w900,
                    color: Colors.grey)),
            const SizedBox(height: 12),
            Row(
              children: [
                _AndroidPaymentChip(
                  icon: Icons.payments_rounded,
                  label: 'Cash',
                  value: 'cash',
                  selected: _paymentMethod,
                  color: AppTheme.success,
                  onTap: () => setState(() => _paymentMethod = 'cash'),
                ),
                const SizedBox(width: 12),
                _AndroidPaymentChip(
                  icon: Icons.qr_code_2_rounded,
                  label: 'UPI',
                  value: 'upi',
                  selected: _paymentMethod,
                  color: AppTheme.primary,
                  onTap: () => setState(() => _paymentMethod = 'upi'),
                ),
                const SizedBox(width: 12),
                _AndroidPaymentChip(
                  icon: Icons.credit_card_rounded,
                  label: 'Card',
                  value: 'card',
                  selected: _paymentMethod,
                  color: AppTheme.accent,
                  onTap: () => setState(() => _paymentMethod = 'card'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            height: 60,
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
                        paymentMethod: _paymentMethod,
                        syncService: context.read<SyncService>(),
                      );
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                '✅ Token #${appt.tokenNumber} issued for ${widget.patient.name}'),
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
              child: const Text('CONFIRM & ISSUE TOKEN',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
