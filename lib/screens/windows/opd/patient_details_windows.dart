import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import '../../../shared/models/patient.dart';
import '../../../shared/models/patient_image.dart';
import '../../../shared/models/sale.dart';
import '../../../shared/models/prescription.dart';
import '../../../shared/models/appointment.dart';
import '../../../shared/providers/patient_provider.dart';
import '../../../shared/providers/sales_provider.dart';
import '../../../shared/providers/prescription_provider.dart';
import '../../../shared/providers/opd_provider.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/services/sync_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/patient_dialogs.dart';
import '../../opd/prescription_screen.dart';

class PatientDetailsWindows extends StatefulWidget {
  final int patientId;
  final int? fromAppointmentId;

  const PatientDetailsWindows({
    super.key,
    required this.patientId,
    this.fromAppointmentId,
  });

  @override
  State<PatientDetailsWindows> createState() => _PatientDetailsWindowsState();
}

class _PatientDetailsWindowsState extends State<PatientDetailsWindows> {
  @override
  Widget build(BuildContext context) {
    final patientById = context.watch<PatientProvider>().getById(widget.patientId);
    
    // Fallback for ID mismatch (common after sync)
    Patient? resolvedPatient = patientById;
    if (resolvedPatient == null && widget.fromAppointmentId != null) {
      final appt = context.read<OpdProvider>().getAppointmentById(widget.fromAppointmentId!);
      if (appt != null) {
        resolvedPatient = context.read<PatientProvider>().getByInfo(appt.patientName, appt.patientPhone);
      }
    }

    if (resolvedPatient == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Patient Details')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_off_rounded, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Patient not found',
                  style: TextStyle(fontSize: 18, color: Colors.grey)),
              const SizedBox(height: 8),
              Text('ID: ${widget.patientId}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 24),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back')),
            ],
          ),
        ),
      );
    }

    final Patient patient = resolvedPatient;

    final sales = context.watch<SalesProvider>().getSalesForPatient(patient);
    final appts = context.watch<OpdProvider>().getAppointmentsForPatient(patient);
    final auth = context.read<AuthProvider>();
    final prescriptions = auth.canAccessMedicalRecords
        ? context
            .watch<PrescriptionProvider>()
            .getPrescriptionsForPatient(patient)
        : <Prescription>[];
        
    final photos = auth.canAccessMedicalRecords
        ? context.watch<PatientProvider>().getPatientPhotosRobust(patient)
        : <PatientImage>[];
        
    final totalSpent =
        sales.fold(0.0, (sum, s) => sum + (s.isReturn ? -s.total : s.total));

    return Scaffold(
      body: Column(
        children: [
          // ── Hero Header ──
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
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 3),
                      ),
                      child: Center(
                        child: Text(
                          patient.name.isNotEmpty
                              ? patient.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontSize: 28,
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
                          Text(patient.name,
                              style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.5)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _HeroBadge(
                                  text: patient.uhid,
                                  icon: Icons.badge_outlined),
                              _HeroBadge(
                                  text: patient.gender,
                                  icon: patient.gender == 'Male'
                                      ? Icons.male_rounded
                                      : Icons.female_rounded),
                              if (patient.ageYears > 0)
                                _HeroBadge(
                                    text: '${patient.ageYears} yrs',
                                    icon: Icons.cake_outlined),
                              if (patient.bloodGroup.isNotEmpty)
                                _HeroBadge(
                                    text: patient.bloodGroup,
                                    icon: Icons.bloodtype_outlined),
                              if (patient.phone.isNotEmpty)
                                _HeroBadge(
                                    text: patient.phone,
                                    icon: Icons.phone_rounded),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        if (auth.canAccessMedicalRecords)
                          _HeroStat(
                              value: '${prescriptions.length}',
                              label: 'Prescriptions',
                              icon: Icons.medical_services_rounded),
                        const SizedBox(width: 16),
                        _HeroStat(
                            value: '${sales.length}',
                            label: 'Transactions',
                            icon: Icons.receipt_long_rounded),
                        const SizedBox(width: 16),
                        _HeroStat(
                            value: '₹${totalSpent.toStringAsFixed(0)}',
                            label: 'Total Spent',
                            icon: Icons.currency_rupee_rounded),
                      ],
                    ),
                    const SizedBox(width: 12),
                    // Edit Button
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.edit_rounded,
                            color: Colors.white, size: 20),
                      ),
                      tooltip: 'Edit Patient',
                      onPressed: () => _showEditPatientDialog(context, patient),
                    ),
                    // Delete Button
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.delete_outline_rounded,
                            color: Colors.white, size: 20),
                      ),
                      tooltip: 'Delete Patient',
                      onPressed: () => _confirmDelete(context, patient),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Full Screen 2x2 Grid ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _SectionCard(
                            title: 'Patient Information',
                            icon: Icons.person_rounded,
                            accentColor: AppTheme.primary,
                            child: _PatientDetailsContent(patient: patient),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: auth.canAccessMedicalRecords
                              ? _SectionCard(
                                  title: 'Gallery',
                                  icon: Icons.photo_library_rounded,
                                  accentColor: AppTheme.purple,
                                  badge: photos.isNotEmpty
                                      ? '${photos.length}'
                                      : null,
                                  trailing: _AddPhotoBtn(
                                      onTap: () => _addPhoto(context, patient)),
                                  child: _GalleryContent(
                                    photos: photos,
                                    onView: (i) =>
                                        _viewPhotos(context, photos, i),
                                  ),
                                )
                              : const _RestrictedSectionCard(
                                  title: 'Gallery',
                                  icon: Icons.photo_library_rounded,
                                  accentColor: AppTheme.purple,
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: auth.canAccessMedicalRecords
                              ? _SectionCard(
                                  title: 'Prescriptions',
                                  icon: Icons.medical_services_rounded,
                                  accentColor: AppTheme.primaryLight,
                                  badge: prescriptions.isNotEmpty
                                      ? '${prescriptions.length}'
                                      : null,
                                  trailing: _AddPrescriptionBtn(
                                    onTap: () =>
                                        _addPrescription(context, patient),
                                    isResume: widget.fromAppointmentId != null,
                                  ),
                                  child: _PrescriptionsContent(
                                    prescriptions: prescriptions,
                                    pProvider:
                                        context.watch<PrescriptionProvider>(),
                                  ),
                                )
                              : const _RestrictedSectionCard(
                                  title: 'Prescriptions',
                                  icon: Icons.medical_services_rounded,
                                  accentColor: AppTheme.primaryLight,
                                ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _SectionCard(
                            title: 'Sales History',
                            icon: Icons.receipt_long_rounded,
                            accentColor: AppTheme.success,
                            badge: sales.isNotEmpty ? '${sales.length}' : null,
                            child: _SalesContent(
                              sales: sales,
                              salesProvider: context.watch<SalesProvider>(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditPatientDialog(BuildContext context, Patient patient) {
    showDialog(
      context: context,
      builder: (ctx) => PatientDialog(patient: patient),
    );
  }

  void _confirmDelete(BuildContext context, Patient patient) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.warning_rounded,
                color: AppTheme.danger, size: 22),
          ),
          const SizedBox(width: 12),
          const Text('Delete Patient?',
              style: TextStyle(color: AppTheme.danger)),
        ]),
        content: Text(
            'Permanently delete ${patient.name}? All medical history will be removed.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: context.textMutedColor))),
          ElevatedButton.icon(
            onPressed: () {
              context.read<PatientProvider>().deletePatient(patient.id);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white),
            icon: const Icon(Icons.delete_rounded, size: 18),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _addPhoto(BuildContext context, Patient patient) async {
    if (Platform.isAndroid || Platform.isIOS) {
      showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                leading: const Icon(Icons.camera_alt, color: AppTheme.primary),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImages(patient, ImageSource.camera);
                }),
            ListTile(
                leading:
                    const Icon(Icons.photo_library, color: AppTheme.primary),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImages(patient, ImageSource.gallery);
                }),
          ]),
        ),
      );
    } else {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.image, allowMultiple: true);
      if (result != null && result.paths.isNotEmpty) {
        if (!context.mounted) return;
        final validPaths = result.paths.whereType<String>().toList();
        await context.read<PatientProvider>().savePatientPhotos(
            patient.id, validPaths,
            syncService: context.read<SyncService>());
      }
    }
  }

  Future<void> _pickImages(Patient patient, ImageSource source) async {
    if (source == ImageSource.camera) {
      final picked = await ImagePicker().pickImage(source: source);
      if (picked != null && mounted) {
        final sync = Platform.isAndroid ? context.read<SyncService>() : null;
        await context
            .read<PatientProvider>()
            .savePatientPhotos(patient.id, [picked.path], syncService: sync);
      }
    } else {
      final pickedList = await ImagePicker().pickMultiImage();
      if (pickedList.isNotEmpty && mounted) {
        final sync = Platform.isAndroid ? context.read<SyncService>() : null;
        await context
            .read<PatientProvider>()
            .savePatientPhotos(patient.id, pickedList.map((e) => e.path).toList(), syncService: sync);
      }
    }
  }

  void _viewPhotos(BuildContext context, List<PatientImage> photos, int index) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (ctx) => _PhotoViewer(
        photos: photos,
        initialIndex: index,
        onDelete: (p) => context.read<PatientProvider>().deletePatientPhoto(p),
      ),
    );
  }

  void _addPrescription(BuildContext context, Patient patient) async {
    final opd = context.read<OpdProvider>();

    // 1. Check if patient is in today's active queue
    // Active means: waiting, with_doctor, or pharmacy (not done/cancelled)
    final activeAppt = opd.todayQueue.where((a) =>
        a.patientId == patient.id &&
        (a.status == kStatusWaiting ||
            a.status == kStatusWithDoctor ||
            a.status == kStatusPharmacy)).firstOrNull;

    // 1.5. If we came from a prescription page and this is the same appointment
    // Just go back instead of pushing a new screen
    if (activeAppt != null && activeAppt.id == widget.fromAppointmentId) {
      if (context.mounted) Navigator.pop(context);
      return;
    }

    if (activeAppt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add the patient to the OPD queue first'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    // 2. Navigate directly to PrescriptionScreen with the EXISTING appointment
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PrescriptionScreen(appointment: activeAppt),
        ),
      );
    }
  }
}

// ── Add Prescription Button ───────────────────────────────────────────────────

class _AddPrescriptionBtn extends StatelessWidget {
  final VoidCallback onTap;
  final bool isResume;
  const _AddPrescriptionBtn({required this.onTap, this.isResume = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.primaryLight.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded,
                  size: 18, color: AppTheme.primaryLight),
              const SizedBox(width: 6),
              Text(
                isResume ? 'Resume' : 'Add',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HERO COMPONENTS
// ═══════════════════════════════════════════════════════════════════════════

class _HeroBadge extends StatelessWidget {
  final String text;
  final IconData icon;
  const _HeroBadge({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: Colors.white70),
        const SizedBox(width: 5),
        Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  const _HeroStat(
      {required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(value,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white60)),
      ]),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION CARD
// ═══════════════════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final String? badge;
  final Widget? trailing;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.accentColor,
    this.badge,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: accentColor.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                  bottom:
                      BorderSide(color: accentColor.withValues(alpha: 0.1))),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: accentColor),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: accentColor)),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(badge!,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ],
              const Spacer(),
              if (trailing != null) trailing!,
            ]),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _AddPhotoBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _AddPhotoBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.purple.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.add_photo_alternate_rounded,
              size: 18, color: AppTheme.purple),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PATIENT DETAILS CONTENT
// ═══════════════════════════════════════════════════════════════════════════

class _PatientDetailsContent extends StatelessWidget {
  final Patient patient;
  const _PatientDetailsContent({required this.patient});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('UHID', patient.uhid, Icons.badge_outlined),
      (
        'Phone',
        patient.phone.isEmpty ? 'Not provided' : patient.phone,
        Icons.phone_outlined
      ),
      ('Gender', patient.gender, Icons.wc_outlined),
      (
        'Age',
        patient.ageYears > 0 ? '${patient.ageYears} years' : 'Not set',
        Icons.cake_outlined
      ),
      (
        'Blood Group',
        patient.bloodGroup.isEmpty ? 'Not set' : patient.bloodGroup,
        Icons.bloodtype_outlined
      ),
      (
        'Address',
        patient.address.isEmpty ? 'Not provided' : patient.address,
        Icons.location_on_outlined
      ),
      (
        'Registered',
        DateFormat('dd MMM yyyy').format(patient.createdAt),
        Icons.calendar_today_outlined
      ),
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final (label, value, icon) = items[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: i.isEven
                ? context.borderColor.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 90,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.textMutedColor,
                      letterSpacing: 0.3)),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.textColor)),
            ),
          ]),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GALLERY CONTENT
// ═══════════════════════════════════════════════════════════════════════════

class _GalleryContent extends StatelessWidget {
  final List<PatientImage> photos;
  final ValueChanged<int> onView;
  const _GalleryContent({required this.photos, required this.onView});

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.purple.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.add_a_photo_rounded,
                size: 32, color: AppTheme.purple.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 12),
          Text('No photos yet',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.textMutedColor)),
          const SizedBox(height: 4),
          Text('Click + to add photos',
              style: TextStyle(fontSize: 11, color: context.textMutedColor)),
        ]),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: photos.length,
      itemBuilder: (ctx, i) {
        final photo = photos[i];
        return GestureDetector(
          onTap: () => onView(i),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(fit: StackFit.expand, children: [
                Image.file(File(photo.imagePath), fit: BoxFit.cover),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black54, Colors.transparent]),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(DateFormat('dd/MM/yy').format(photo.date),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w600)),
                        if (photo.category != 'General')
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(4)),
                            child: Text(photo.category,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 8)),
                          ),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PRESCRIPTIONS CONTENT (Expandable)
// ═══════════════════════════════════════════════════════════════════════════

class _PrescriptionsContent extends StatelessWidget {
  final List<Prescription> prescriptions;
  final PrescriptionProvider pProvider;
  const _PrescriptionsContent(
      {required this.prescriptions, required this.pProvider});

  @override
  Widget build(BuildContext context) {
    if (prescriptions.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.medical_services_outlined,
                size: 32, color: AppTheme.primaryLight.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 12),
          const Text('No prescriptions',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B))),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: prescriptions.length,
      itemBuilder: (ctx, i) => _ExpandablePrescription(
          prescription: prescriptions[i], pProvider: pProvider),
    );
  }
}

class _ExpandablePrescription extends StatefulWidget {
  final Prescription prescription;
  final PrescriptionProvider pProvider;
  const _ExpandablePrescription(
      {required this.prescription, required this.pProvider});

  @override
  State<_ExpandablePrescription> createState() =>
      _ExpandablePrescriptionState();
}

class _ExpandablePrescriptionState extends State<_ExpandablePrescription> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.prescription;
    final items = widget.pProvider.getItems(p);
    final vitals = widget.pProvider.getVitals(p);
    final labTests = widget.pProvider.getLabTests(p);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _expanded
            ? AppTheme.primaryLight.withValues(alpha: 0.06)
            : AppTheme.primaryLight.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color:
                AppTheme.primaryLight.withValues(alpha: _expanded ? 0.2 : 0.1)),
        boxShadow: _expanded
            ? [
                BoxShadow(
                    color: AppTheme.primaryLight.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ]
            : [],
      ),
      child: Column(
        children: [
          // Summary row (always visible)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: IntrinsicHeight(
              child: Row(children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color:
                        p.dispensed ? AppTheme.success : AppTheme.primaryLight,
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        bottomLeft: Radius.circular(14)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.medical_services_rounded,
                            color: AppTheme.primaryLight, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Dr. ${p.doctorName}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13)),
                            const SizedBox(height: 3),
                            Text(
                              p.diagnosis.isNotEmpty
                                  ? p.diagnosis
                                  : p.complaints.isNotEmpty
                                      ? p.complaints
                                      : 'No diagnosis',
                              style: TextStyle(
                                  fontSize: 12, color: context.textMutedColor),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(DateFormat('dd MMM').format(p.createdAt),
                              style: TextStyle(
                                  fontSize: 11, color: context.textMutedColor)),
                          const SizedBox(height: 6),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: p.dispensed
                                      ? AppTheme.success.withValues(alpha: 0.1)
                                      : AppTheme.warning.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                    p.dispensed ? 'DISPENSED' : 'PENDING',
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: p.dispensed
                                            ? AppTheme.success
                                            : AppTheme.warningDark)),
                              ),
                              if (widget.pProvider.getImages(p).isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.image_rounded,
                                    size: 14,
                                    color: AppTheme.primaryLight
                                        .withValues(alpha: 0.6)),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: context.textMutedColor,
                        size: 22,
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),

          // Expanded details
          if (_expanded)
            Container(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: AppTheme.primaryLight.withValues(alpha: 0.1))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vitals
                  if (vitals.bp.isNotEmpty ||
                      vitals.weight.isNotEmpty ||
                      vitals.temp.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Vitals',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryLight,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        if (vitals.bp.isNotEmpty)
                          _VitalChip(label: 'BP', value: vitals.bp),
                        if (vitals.pulse.isNotEmpty)
                          _VitalChip(label: 'Pulse', value: vitals.pulse),
                        if (vitals.temp.isNotEmpty)
                          _VitalChip(label: 'Temp', value: vitals.temp),
                        if (vitals.weight.isNotEmpty)
                          _VitalChip(label: 'Weight', value: vitals.weight),
                        if (vitals.spo2.isNotEmpty)
                          _VitalChip(label: 'SpO2', value: vitals.spo2),
                      ],
                    ),
                  ],
                  // Medicines
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('Medicines',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryLight,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 8),
                    ...items.asMap().entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 20,
                                child: Text('${e.key + 1}.',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.primaryLight)),
                              ),
                              Expanded(
                                child: Text(e.value.medicineName,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ),
                              Text(
                                  '${e.value.dosage} \u2022 ${e.value.days}d \u2022 Qty:${e.value.qty}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: context.textMutedColor)),
                            ],
                          ),
                        )),
                  ],
                  // Lab tests
                  if (labTests.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('Lab Tests',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryLight,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: labTests
                          .map((t) => Chip(
                              label:
                                  Text(t, style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: AppTheme.primaryLight
                                  .withValues(alpha: 0.08)))
                          .toList(),
                    ),
                  ],
                  // Notes
                  if (p.notes.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('Notes',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryLight,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Text(p.notes,
                        style: TextStyle(
                            fontSize: 12, color: context.textMutedColor)),
                  ],
                  // Procedures
                  if (widget.pProvider.getProcedures(p).isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('Procedures',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryLight,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    ...widget.pProvider.getProcedures(p).map((proc) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_outline,
                                  size: 12, color: AppTheme.primaryLight),
                              const SizedBox(width: 6),
                              Text(proc, style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        )),
                  ],
                  // Images
                  if (widget.pProvider.getImages(p).isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('Attachments',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryLight,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.pProvider
                            .getImages(p)
                            .map((path) => FutureBuilder<String>(
                                  future: widget.pProvider.resolveImagePath(path),
                                  builder: (context, snapshot) {
                                    final resolvedPath = snapshot.data ?? path;
                                    return GestureDetector(
                                      onTap: () => _viewPrescriptionImage(
                                          context, resolvedPath),
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                                color: AppTheme.primaryLight
                                                    .withValues(alpha: 0.2)),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.file(
                                              File(resolvedPath),
                                              width: 60,
                                              height: 60,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                width: 60,
                                                height: 60,
                                                color: Colors.grey.shade200,
                                                child: const Icon(
                                                    Icons.broken_image,
                                                    size: 20,
                                                    color: Colors.grey),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ))
                            .toList(),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _viewPrescriptionImage(BuildContext context, String path) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(path), fit: BoxFit.contain),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
            ),
          ],
        ),
      ),
    );
  }
}

class _VitalChip extends StatelessWidget {
  final String label;
  final String value;
  const _VitalChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11, color: Color(0xFF1A2332)),
          children: [
            TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SALES CONTENT (Expandable)
// ═══════════════════════════════════════════════════════════════════════════

class _SalesContent extends StatelessWidget {
  final List<Sale> sales;
  final SalesProvider salesProvider;
  const _SalesContent({required this.sales, required this.salesProvider});

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.receipt_long_outlined,
                size: 32, color: AppTheme.success.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 12),
          const Text('No sales recorded',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B))),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: sales.length,
      itemBuilder: (ctx, i) =>
          _ExpandableSale(sale: sales[i], salesProvider: salesProvider),
    );
  }
}

class _ExpandableSale extends StatefulWidget {
  final Sale sale;
  final SalesProvider salesProvider;
  const _ExpandableSale({required this.sale, required this.salesProvider});

  @override
  State<_ExpandableSale> createState() => _ExpandableSaleState();
}

class _ExpandableSaleState extends State<_ExpandableSale> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.sale;
    final isReturn = s.isReturn;
    final color = isReturn ? AppTheme.danger : AppTheme.success;
    final items = widget.salesProvider.getSaleItems(s);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _expanded
            ? color.withValues(alpha: 0.06)
            : color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: color.withValues(alpha: _expanded ? 0.25 : 0.1)),
        boxShadow: _expanded
            ? [
                BoxShadow(
                    color: color.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ]
            : [],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: IntrinsicHeight(
              child: Row(children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        bottomLeft: Radius.circular(14)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isReturn
                              ? Icons.keyboard_return_rounded
                              : Icons.receipt_rounded,
                          color: color,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(s.invoiceNo,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    fontFamily: 'monospace')),
                            const SizedBox(height: 3),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(s.paymentMethod.toUpperCase(),
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: context.textMutedColor)),
                              ),
                              if (s.opdInvoiceNo.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('OPD ID: ${s.opdInvoiceNo}',
                                      style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.primary)),
                                ),
                              ],
                              if (isReturn) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        AppTheme.danger.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('REFUND',
                                      style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.danger)),
                                ),
                              ],
                            ]),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('₹${s.total.toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: color)),
                          const SizedBox(height: 3),
                          Text(DateFormat('dd MMM, h:mm a').format(s.createdAt),
                              style: TextStyle(
                                  fontSize: 11, color: context.textMutedColor)),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: context.textMutedColor,
                        size: 22,
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),

          // Expanded item details
          if (_expanded)
            Container(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(color: color.withValues(alpha: 0.1))),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  // Items header
                  Row(children: [
                    Expanded(
                        child: Text('ITEM',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: context.textMutedColor))),
                    SizedBox(
                        width: 80,
                        child: Text('QTY',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: context.textMutedColor),
                            textAlign: TextAlign.center)),
                    SizedBox(
                        width: 90,
                        child: Text('PRICE',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: context.textMutedColor),
                            textAlign: TextAlign.end)),
                    SizedBox(
                        width: 90,
                        child: Text('SUBTOTAL',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: context.textMutedColor),
                            textAlign: TextAlign.end)),
                  ]),
                  Divider(height: 14, color: color.withValues(alpha: 0.1)),
                  // Items
                  ...items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.medicineName,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500)),
                                  if (!item.isProcedure && item.batchNo.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'Batch: ${item.batchNo} | Exp: ${item.expiryDate}',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: context.textMutedColor,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                ],
                              )),
                          SizedBox(
                              width: 80,
                              child: Text('${item.qty}',
                                  style: const TextStyle(fontSize: 12),
                                  textAlign: TextAlign.center)),
                          SizedBox(
                              width: 90,
                              child: Text(
                                  '₹${item.unitPrice.toStringAsFixed(2)}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: context.textMutedColor),
                                  textAlign: TextAlign.end)),
                          SizedBox(
                              width: 90,
                              child: Text(
                                  '₹${item.lineTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.end)),
                        ]),
                      )),
                  Divider(height: 14, color: color.withValues(alpha: 0.1)),
                  // Totals
                  if (s.discount > 0)
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text('Discount',
                          style: TextStyle(
                              fontSize: 12, color: context.textMutedColor)),
                      const SizedBox(width: 32),
                      SizedBox(
                          width: 90,
                          child: Text('-₹${s.discount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  color: AppTheme.danger,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12),
                              textAlign: TextAlign.end)),
                    ]),
                  if (s.discount > 0) const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    const Text('Total',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A2332))),
                    const SizedBox(width: 32),
                    SizedBox(
                        width: 90,
                        child: Text('₹${s.total.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: color),
                            textAlign: TextAlign.end)),
                  ]),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PHOTO VIEWER
// ═══════════════════════════════════════════════════════════════════════════

class _PhotoViewer extends StatefulWidget {
  final List<PatientImage> photos;
  final int initialIndex;
  final Function(PatientImage) onDelete;
  const _PhotoViewer(
      {required this.photos,
      required this.initialIndex,
      required this.onDelete});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late int _idx;
  final _ctrl = TransformationController();

  @override
  void initState() {
    super.initState();
    _idx = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_idx];
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (e) {
        if (e is KeyDownEvent) {
          if (e.logicalKey == LogicalKeyboardKey.arrowRight &&
              _idx < widget.photos.length - 1) {
            setState(() {
              _idx++;
              _ctrl.value = Matrix4.identity();
            });
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowLeft && _idx > 0) {
            setState(() {
              _idx--;
              _ctrl.value = Matrix4.identity();
            });
          }
          if (e.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.pop(context);
          }
        }
      },
      child: Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(children: [
          Center(
            child: InteractiveViewer(
              transformationController: _ctrl,
              minScale: 0.5,
              maxScale: 4,
              child: Image.file(File(photo.imagePath),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black45,
              child: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                foregroundColor: Colors.white,
                title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat('dd MMM yyyy').format(photo.date)),
                      Text(
                          '${_idx + 1} of ${widget.photos.length} \u2022 ${photo.category}',
                          style: const TextStyle(fontSize: 12)),
                    ]),
                actions: [
                  IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppTheme.danger),
                      onPressed: () {
                        widget.onDelete(photo);
                        Navigator.pop(context);
                      }),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
          ),
          if (_idx > 0)
            Positioned(
                left: 20,
                top: 0,
                bottom: 0,
                child: Center(
                    child: IconButton(
                        icon: const Icon(Icons.chevron_left,
                            color: Colors.white, size: 48),
                        onPressed: () => setState(() {
                              _idx--;
                              _ctrl.value = Matrix4.identity();
                            })))),
          if (_idx < widget.photos.length - 1)
            Positioned(
                right: 20,
                top: 0,
                bottom: 0,
                child: Center(
                    child: IconButton(
                        icon: const Icon(Icons.chevron_right,
                            color: Colors.white, size: 48),
                        onPressed: () => setState(() {
                              _idx++;
                              _ctrl.value = Matrix4.identity();
                            })))),
        ]),
      ),
    );
  }
}

class _RestrictedSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;

  const _RestrictedSectionCard({
    required this.title,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: title,
      icon: icon,
      accentColor: accentColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_person_rounded,
                size: 48, color: context.textMutedColor.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              'Access Restricted',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.textMutedColor),
            ),
            const SizedBox(height: 4),
            Text(
              'Doctor or Admin privilege required',
              style: TextStyle(fontSize: 11, color: context.textMutedColor),
            ),
          ],
        ),
      ),
    );
  }
}
