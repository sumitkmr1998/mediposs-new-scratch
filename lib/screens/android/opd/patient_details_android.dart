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
import '../../../shared/providers/patient_provider.dart';
import '../../../shared/providers/sales_provider.dart';
import '../../../shared/providers/prescription_provider.dart';
import '../../../shared/providers/opd_provider.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/services/sync_service.dart';
import '../../../../theme/app_theme.dart';
import '../../opd/../../screens/opd/prescription_screen.dart';

class PatientDetailsAndroid extends StatefulWidget {
  final int patientId;

  const PatientDetailsAndroid({super.key, required this.patientId});

  @override
  State<PatientDetailsAndroid> createState() => _PatientDetailsAndroidState();
}

class _PatientDetailsAndroidState extends State<PatientDetailsAndroid>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final patient = context.watch<PatientProvider>().getById(widget.patientId);

    if (patient == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Patient Details')),
        body: const Center(child: Text('Patient not found')),
      );
    }

    return Scaffold(
      backgroundColor: context.surfaceColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patient.name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                Text(
                  patient.uhid,
                  style: TextStyle(
                      color: context.textMutedColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                tooltip: 'Delete Patient',
                onPressed: () => _confirmDelete(context, patient),
              ),
              const SizedBox(width: 8),
            ],
            pinned: true,
            floating: true,
            forceElevated: innerBoxIsScrolled,
            elevation: innerBoxIsScrolled ? 4 : 0,
            bottom: TabBar(
              controller: _tabController,
              labelColor: AppTheme.primary,
              unselectedLabelColor: context.textMutedColor,
              indicatorColor: AppTheme.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              tabs: const [
                Tab(icon: Icon(Icons.history), text: 'History'),
                Tab(icon: Icon(Icons.photo_library), text: 'Gallery'),
                Tab(icon: Icon(Icons.info_outline), text: 'Profile'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _HistoryTab(patient: patient),
            _GalleryTab(patient: patient),
            _ProfileTab(patient: patient),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Patient patient) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Patient?'),
        content: Text(
            'Are you sure you want to delete ${patient.name}? This will remove all their medical history and photographs. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<PatientProvider>().deletePatient(patient.id);
              Navigator.pop(ctx); // Close dialog
              Navigator.pop(context); // Back to list
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Patient ${patient.name} deleted'),
                  backgroundColor: AppTheme.danger,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// --- History Tab ---
class _HistoryTab extends StatelessWidget {
  final Patient patient;

  const _HistoryTab({required this.patient});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final sales = context.watch<SalesProvider>().getSalesForPatient(patient);
    final prescriptions = auth.canAccessMedicalRecords
        ? context
            .watch<PrescriptionProvider>()
            .getPrescriptionsForPatient(patient)
        : <Prescription>[];

    // Merge and sort by date
    final List<dynamic> history = [...sales, ...prescriptions]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_toggle_off,
              size: 64,
              color: context.textMutedColor,
            ),
            const SizedBox(height: 12),
            Text(
              'No history found for this patient',
              style: TextStyle(color: context.textMutedColor),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: history.length,
      itemBuilder: (ctx, i) {
        final item = history[i];
        if (item is Sale) {
          return _SaleHistoryTile(sale: item);
        } else if (item is Prescription) {
          return _PrescriptionHistoryTile(prescription: item);
        }
        return const SizedBox();
      },
    );
  }
}

class _SaleHistoryTile extends StatelessWidget {
  final Sale sale;
  const _SaleHistoryTile({required this.sale});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: context.borderColor.withValues(alpha: 0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            showDialog(
              context: context,
              builder: (ctx) => _SaleDetailDialog(sale: sale),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.shopping_cart_outlined,
                    color: AppTheme.success,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sale: ${sale.invoiceNo}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('dd MMM yyyy, hh:mm a')
                            .format(sale.createdAt),
                        style: TextStyle(
                            color: context.textMutedColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                Text('₹${sale.total.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppTheme.success)),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SaleDetailDialog extends StatelessWidget {
  final Sale sale;
  const _SaleDetailDialog({required this.sale});

  @override
  Widget build(BuildContext context) {
    final sProvider = context.read<SalesProvider>();
    final items = sProvider.getSaleItems(sale);

    return AlertDialog(
      title: Text('Invoice: ${sale.invoiceNo}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(sale.createdAt)}'),
            Text('Payment: ${sale.paymentMethod.toUpperCase()}'),
            const Divider(),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final item = items[i];
                  return ListTile(
                    dense: true,
                    title: Text(item.medicineName),
                    subtitle: Text(
                        '${item.qty} x ₹${item.unitPrice.toStringAsFixed(2)}' +
                        ((!item.isProcedure && item.batchNo.isNotEmpty) ? '\nBatch: ${item.batchNo} | Exp: ${item.expiryDate}' : '')),
                    trailing: Text('₹${item.lineTotal.toStringAsFixed(2)}'),
                  );
                },
              ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('₹${sale.total.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }
}

class _PrescriptionHistoryTile extends StatelessWidget {
  final Prescription prescription;
  const _PrescriptionHistoryTile({required this.prescription});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: context.borderColor.withValues(alpha: 0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            showDialog(
              context: context,
              builder: (ctx) =>
                  _PrescriptionDetailDialog(prescription: prescription),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.medical_services_outlined,
                    color: AppTheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dr. ${prescription.doctorName}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                        '${prescription.diagnosis.isNotEmpty ? "${prescription.diagnosis} • " : ""}${DateFormat('dd MMM yyyy').format(prescription.createdAt)}',
                        style: TextStyle(
                            color: context.textMutedColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                if (prescription.dispensed)
                  Container(
                    padding: const EdgeInsets.only(right: 8),
                    child: const Icon(Icons.check_circle,
                        color: AppTheme.success, size: 24),
                  ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrescriptionDetailDialog extends StatelessWidget {
  final Prescription prescription;
  const _PrescriptionDetailDialog({required this.prescription});

  @override
  Widget build(BuildContext context) {
    final pProvider = context.read<PrescriptionProvider>();
    final items = pProvider.getItems(prescription);
    final labTests = pProvider.getLabTests(prescription);
    final vitals = pProvider.getVitals(prescription);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Prescription Details',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        DateFormat('dd MMM yyyy, hh:mm a')
                            .format(prescription.createdAt),
                        style: TextStyle(
                            color: context.textMutedColor, fontSize: 12),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            color: AppTheme.primary),
                        onPressed: () => _edit(context),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: AppTheme.danger),
                        onPressed: () => _confirmDelete(context),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 24),
              if (vitals.weight.isNotEmpty || vitals.bp.isNotEmpty) ...[
                const Text('🩺 Vitals',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  children: [
                    if (vitals.bp.isNotEmpty) _v('BP', vitals.bp),
                    if (vitals.pulse.isNotEmpty) _v('Pulse', vitals.pulse),
                    if (vitals.temp.isNotEmpty) _v('Temp', vitals.temp),
                    if (vitals.weight.isNotEmpty) _v('Wt', vitals.weight),
                    if (vitals.spo2.isNotEmpty) _v('SpO2', vitals.spo2),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (prescription.complaints.isNotEmpty) ...[
                const Text('Complaints',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Text(prescription.complaints,
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
              ],
              if (prescription.diagnosis.isNotEmpty) ...[
                const Text('Diagnosis',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Text(prescription.diagnosis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
              ],
              if (items.isNotEmpty) ...[
                const Text('💊 Medicines',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...items.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${e.key + 1}. ',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.value.medicineName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                                Text(
                                  '${e.value.dosage}  •  ${e.value.days} days (Qty: ${e.value.qty})',
                                  style: TextStyle(
                                      color: context.textMutedColor,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),
              ],
              if (labTests.isNotEmpty) ...[
                const Text('🧪 Lab Tests',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: labTests
                      .map((t) => Chip(
                            label:
                                Text(t, style: const TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
              ],
              if (prescription.notes.isNotEmpty) ...[
                const Text('Notes',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Text(prescription.notes, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 16),
              ],

              // Procedures
              if (pProvider.getProcedures(prescription).isNotEmpty) ...[
                const Text('📋 Procedures',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...pProvider.getProcedures(prescription).map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $p', style: const TextStyle(fontSize: 13)),
                    )),
                const SizedBox(height: 16),
              ],

              // Images
              if (pProvider.getImages(prescription).isNotEmpty) ...[
                const Text('🖼️ Attachments',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: pProvider.getImages(prescription).map((path) {
                    return FutureBuilder<String>(
                      future: pProvider.resolveImagePath(path),
                      builder: (context, snapshot) {
                        final resolvedPath = snapshot.data ?? path;
                        return GestureDetector(
                          onTap: () => _viewImage(context, resolvedPath),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(resolvedPath),
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 80,
                                height: 80,
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.broken_image,
                                    size: 20, color: Colors.grey),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _viewImage(BuildContext context, String path) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: Center(child: Image.file(File(path))),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Widget _v(String l, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(v,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      );

  void _edit(BuildContext context) async {
    final opd = context.read<OpdProvider>();
    final appt = opd.getAppointmentById(prescription.appointmentId);
    if (appt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Appointment not found')),
      );
      return;
    }
    Navigator.pop(context);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrescriptionScreen(appointment: appt),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Prescription?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              context
                  .read<PrescriptionProvider>()
                  .deletePrescription(prescription.id, actor: context.read<AuthProvider>().currentUser);
              Navigator.pop(ctx);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Prescription deleted'),
                    backgroundColor: AppTheme.danger),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// --- Gallery Tab ---
class _GalleryTab extends StatefulWidget {
  final Patient patient;
  const _GalleryTab({required this.patient});

  @override
  State<_GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends State<_GalleryTab> {
  bool _loadingFromHub = false;

  @override
  void initState() {
    super.initState();
    // Lazy on-demand pull — fetch this patient's photos from Hub when
    // the Gallery tab first opens (NOT at login).
    WidgetsBinding.instance.addPostFrameCallback((_) => _pullPhotosFromHub());
  }

  Future<void> _pullPhotosFromHub() async {
    if (!Platform.isAndroid) return;
    final sync = context.read<SyncService>();
    if (!sync.isConnected) return;
    final uhid = widget.patient.uhid;
    if (uhid.isEmpty) return;

    setState(() => _loadingFromHub = true);
    await sync.pullPatientPhotosForPatient(uhid, widget.patient.id);
    if (mounted) {
      setState(() => _loadingFromHub = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final pProvider = context.watch<PatientProvider>();
    final photos = pProvider.getPatientPhotosRobust(widget.patient);

    return Scaffold(
      floatingActionButton: auth.canAccessMedicalRecords
          ? FloatingActionButton(
              onPressed: _addPhoto,
              backgroundColor: AppTheme.primary,
              child: const Icon(Icons.add_a_photo, color: Colors.white),
            )
          : null,
      body: !auth.canAccessMedicalRecords
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_person,
                      size: 64, color: context.textMutedColor),
                  const SizedBox(height: 12),
                  const Text('Medical records access required'),
                ],
              ),
            )
          : _loadingFromHub
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Loading photos from Hub...'),
                ],
              ),
            )
          : photos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.photo_album_outlined,
                        size: 64,
                        color: context.textMutedColor,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No photographs saved for this patient',
                        style: TextStyle(color: context.textMutedColor),
                      ),
                      if (Platform.isAndroid) ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _pullPhotosFromHub,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh from Hub'),
                        ),
                      ],
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (ctx, i) {
                    final photo = photos[i];
                    return GestureDetector(
                      onTap: () => _viewPhotos(photos, i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(File(photo.imagePath),
                                fit: BoxFit.cover),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 2, horizontal: 4),
                                color: Colors.black54,
                                child: Text(
                                  DateFormat('dd/MM/yy').format(photo.date),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 10),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  void _addPhoto() async {
    if (Platform.isAndroid || Platform.isIOS) {
      showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImages(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImages(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      );
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (result != null && result.paths.isNotEmpty) {
        final validPaths = result.paths.whereType<String>().toList();
        _saveCapturedPhotos(validPaths);
      }
    }
  }

  Future<void> _pickImages(ImageSource source) async {
    final picker = ImagePicker();
    if (source == ImageSource.camera) {
      final pickedFile = await picker.pickImage(source: source);
      if (pickedFile != null) {
        _saveCapturedPhotos([pickedFile.path]);
      }
    } else {
      final pickedFiles = await picker.pickMultiImage();
      if (pickedFiles.isNotEmpty) {
        _saveCapturedPhotos(pickedFiles.map((e) => e.path).toList());
      }
    }
  }

  Future<void> _saveCapturedPhotos(List<String> paths) async {
    final syncService = Platform.isAndroid ? context.read<SyncService>() : null;
    await context.read<PatientProvider>().savePatientPhotos(
          widget.patient.id,
          paths,
          syncService: syncService,
        );
    setState(() {});
  }

  void _viewPhotos(List<PatientImage> photos, int initialIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (ctx) => _EnhancedPhotoViewer(
        photos: photos,
        initialIndex: initialIndex,
        onDelete: (photo) {
          context.read<PatientProvider>().deletePatientPhoto(photo, syncService: context.read<SyncService>());
          setState(() {});
        },
      ),
    );
  }
}

class _EnhancedPhotoViewer extends StatefulWidget {
  final List<PatientImage> photos;
  final int initialIndex;
  final Function(PatientImage) onDelete;

  const _EnhancedPhotoViewer({
    required this.photos,
    required this.initialIndex,
    required this.onDelete,
  });

  @override
  State<_EnhancedPhotoViewer> createState() => _EnhancedPhotoViewerState();
}

class _EnhancedPhotoViewerState extends State<_EnhancedPhotoViewer> {
  late int _currentIndex;
  final _transformationCtrl = TransformationController();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _next() {
    if (_currentIndex < widget.photos.length - 1) {
      setState(() {
        _currentIndex++;
        _transformationCtrl.value = Matrix4.identity();
      });
    }
  }

  void _prev() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _transformationCtrl.value = Matrix4.identity();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_currentIndex];
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _next();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _prev();
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.pop(context);
          }
        }
      },
      child: Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                transformationController: _transformationCtrl,
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.file(
                  File(photo.imagePath),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
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
                        'Photo ${_currentIndex + 1} of ${widget.photos.length} • Category: ${photo.category}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppTheme.danger),
                      onPressed: () {
                        widget.onDelete(photo);
                        if (widget.photos.length <= 1) {
                          Navigator.pop(context);
                        } else {
                          Navigator.pop(context);
                        }
                      },
                    ),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
            ),
            if (_currentIndex > 0)
              Positioned(
                left: 20,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    icon: const Icon(Icons.chevron_left,
                        color: Colors.white, size: 48),
                    onPressed: _prev,
                  ),
                ),
              ),
            if (_currentIndex < widget.photos.length - 1)
              Positioned(
                right: 20,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    icon: const Icon(Icons.chevron_right,
                        color: Colors.white, size: 48),
                    onPressed: _next,
                  ),
                ),
              ),
            const Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Use mouse wheel/pinch to zoom • Arrow keys to navigate',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Profile Tab ---
class _ProfileTab extends StatelessWidget {
  final Patient patient;
  const _ProfileTab({required this.patient});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _ProfileInfoItem(
              label: 'UHID', value: patient.uhid, icon: Icons.badge_outlined),
          _ProfileInfoItem(
              label: 'Phone',
              value: patient.phone.isEmpty ? 'N/A' : patient.phone,
              icon: Icons.phone_outlined),
          _ProfileInfoItem(
              label: 'Gender',
              value: patient.gender,
              icon: Icons.person_outline),
          _ProfileInfoItem(
              label: 'Age',
              value: '${patient.ageYears} years',
              icon: Icons.cake_outlined),
          _ProfileInfoItem(
              label: 'Address',
              value: patient.address.isEmpty ? 'N/A' : patient.address,
              icon: Icons.location_on_outlined),
          _ProfileInfoItem(
              label: 'Registered On',
              value: DateFormat('dd MMM yyyy').format(patient.createdAt),
              icon: Icons.calendar_today_outlined),
        ],
      ),
    );
  }
}

class _ProfileInfoItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _ProfileInfoItem(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: context.borderColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: context.textMutedColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
