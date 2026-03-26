import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/models/appointment.dart';
import '../../../shared/providers/opd_provider.dart';
import '../../../shared/providers/prescription_provider.dart';
import '../../../shared/providers/patient_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../shared/models/patient.dart';
import '../../../widgets/patient_dialogs.dart';
import '../../../shared/services/sync_service.dart';
import '../../opd/prescription_screen.dart';
import '../../opd/patient_details_screen.dart';

class OpdQueueWindows extends StatefulWidget {
  const OpdQueueWindows({super.key});

  @override
  State<OpdQueueWindows> createState() => _OpdQueueWindowsState();
}

class _OpdQueueWindowsState extends State<OpdQueueWindows> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OpdProvider>().loadAll();
      context.read<PrescriptionProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final opd = context.watch<OpdProvider>();
    final queue = opd.todayQueue;

    final waiting = queue.where((a) => a.status == kStatusWaiting).toList();
    final withDoctor =
        queue.where((a) => a.status == kStatusWithDoctor).toList();
    final pharmacy = queue.where((a) => a.status == kStatusPharmacy).toList();
    final done = queue.where((a) => a.status == kStatusDone).toList();

    // Sequential order: 1, 2, 3... by token number
    final sortedQueue = List<Appointment>.from(queue)
      ..sort((a, b) => a.tokenNumber.compareTo(b.tokenNumber));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.people_alt_rounded,
                  color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('OPD Queue',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                Text('Today\'s live queue',
                    style: TextStyle(fontSize: 12, color: context.textMutedColor)),
              ],
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats Row
            LayoutBuilder(builder: (ctx, constraints) {
              final cols = constraints.maxWidth > 800
                  ? 4
                  : (constraints.maxWidth > 500 ? 2 : 1);
              const spacing = 12.0;
              final cardWidth =
                  (constraints.maxWidth - (cols - 1) * spacing) / cols;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  _StatCard(
                    label: 'OPD Today',
                    value: '${queue.length}',
                    icon: Icons.groups_rounded,
                    color: AppTheme.primary,
                    width: cardWidth,
                  ),
                  _StatCard(
                    label: 'Tokens Left',
                    value:
                        '${waiting.length + withDoctor.length + pharmacy.length}',
                    icon: Icons.hourglass_top_rounded,
                    color: AppTheme.warning,
                    width: cardWidth,
                  ),
                  _StatCard(
                    label: 'With Doctor',
                    value: '${withDoctor.length}',
                    icon: Icons.healing_rounded,
                    color: AppTheme.primaryLight,
                    width: cardWidth,
                  ),
                  _StatCard(
                    label: 'Completed',
                    value: '${done.length}',
                    icon: Icons.check_circle_rounded,
                    color: AppTheme.success,
                    width: cardWidth,
                  ),
                ],
              );
            }),

            const SizedBox(height: 24),

            // Bento Queue Table
            Container(
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: context.borderColor.withValues(alpha: 0.5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Table Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    child: Row(
                      children: [
                        SizedBox(
                            width: 60,
                            child: Text('TOKEN', style: _headerStyle(context))),
                        const SizedBox(width: 12),
                        const Expanded(
                            flex: 2,
                            child: Text('PATIENT DETAILS',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                    color: Color(0xFF94A3B8)))),
                        const Expanded(
                            flex: 2,
                            child: Text('ASSIGNED CONSULTANT',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                    color: Color(0xFF94A3B8)))),
                        const SizedBox(
                            width: 180,
                            child: Center(
                                child: Text('WAIT DURATION',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.5,
                                        color: Color(0xFF94A3B8))))),
                        const SizedBox(
                            width: 180,
                            child: Center(
                                child: Text('CURRENT STATUS',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.5,
                                        color: Color(0xFF94A3B8))))),
                        const SizedBox(
                            width: 180,
                            child: Align(
                                alignment: Alignment.centerRight,
                                child: Text('ACTIONS',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.5,
                                        color: Color(0xFF94A3B8))))),
                      ],
                    ),
                  ),

                  Divider(height: 1, color: context.borderColor),

                  const SizedBox(height: 4),

                  // Queue Rows (sequential 1, 2, 3...)
                  if (sortedQueue.isEmpty)
                    const _EmptyQueue()
                  else
                    ...sortedQueue.map((appt) => _QueueRow(
                          appointment: appt,
                          onStatusChangeWithPayment:
                              (newStatus, paymentMethod) {
                            context.read<OpdProvider>().updateStatusWithPayment(
                                appt.id,
                                newStatus,
                                paymentMethod,
                                context.read<SyncService>());
                            if (newStatus == kStatusDone) {
                              context
                                  .read<PrescriptionProvider>()
                                  .markDispensedByAppointment(appt.id,
                                      syncService: context.read<SyncService>());
                            }
                          },
                          onStatusChange: (newStatus) {
                            context.read<OpdProvider>().updateStatus(
                                appt.id, newStatus, context.read<SyncService>());
                            if (newStatus == kStatusDone) {
                              context
                                  .read<PrescriptionProvider>()
                                  .markDispensedByAppointment(appt.id,
                                      syncService: context.read<SyncService>());
                            }
                          },
                          onConsult: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PrescriptionScreen(appointment: appt),
                            ),
                          ),
                          onViewPatient: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PatientDetailsScreen(
                                  patientId: appt.patientId),
                            ),
                          ),
                          onEditPatient: () async {
                            final patientProvider =
                                context.read<PatientProvider>();
                            final patient =
                                patientProvider.getById(appt.patientId);
                            if (patient != null) {
                              showDialog(
                                context: context,
                                builder: (ctx) =>
                                    PatientDialog(patient: patient),
                              );
                            }
                          },
                        )),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddPatientOptions(context),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Patient'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  TextStyle _headerStyle(BuildContext context) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: context.textMutedColor,
      );

  void _showAddPatientOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading:
                const Icon(Icons.app_registration, color: AppTheme.primary),
            title: const Text('Register New Patient'),
            subtitle: const Text('For first-time clinic visit'),
            onTap: () async {
              Navigator.pop(ctx);
              final patient = await showDialog<Patient>(
                context: context,
                builder: (ctx) => const PatientDialog(),
              );
              if (patient != null && context.mounted) {
                _showBookingDialog(context, patient);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_search, color: AppTheme.primary),
            title: const Text('Existing Patient'),
            subtitle: const Text('Search by name, phone or UHID'),
            onTap: () {
              Navigator.pop(ctx);
              showDialog(
                context: context,
                builder: (ctx) => PatientSearchDialog(
                  showSkip: false,
                  onSelected: (p) => _showBookingDialog(context, p),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showBookingDialog(BuildContext context, Patient patient) {
    showDialog(
      context: context,
      builder: (ctx) => BookAppointmentDialog(patient: patient),
    );
  }
}

// ── Stat Card ───────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final double width;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: color)),
                  Text(label,
                      style: TextStyle(
                          fontSize: 12, color: context.textMutedColor)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Queue Row ───────────────────────────────────────────────────────────────

class _QueueRow extends StatefulWidget {
  final Appointment appointment;
  final Function(String status, String paymentMethod) onStatusChangeWithPayment;
  final Function(String status) onStatusChange;
  final VoidCallback onConsult;
  final VoidCallback onViewPatient;
  final VoidCallback onEditPatient;

  const _QueueRow({
    required this.appointment,
    required this.onStatusChangeWithPayment,
    required this.onStatusChange,
    required this.onConsult,
    required this.onViewPatient,
    required this.onEditPatient,
  });

  @override
  State<_QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends State<_QueueRow> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initTimer();
  }

  void _initTimer() {
    _timer?.cancel();
    _timer = null;

    final status = widget.appointment.status;
    if (status == kStatusWithDoctor && widget.appointment.calledAt != null) {
      _elapsed = DateTime.now().difference(widget.appointment.calledAt!);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && widget.appointment.calledAt != null) {
          setState(() {
            _elapsed = DateTime.now().difference(widget.appointment.calledAt!);
          });
        }
      });
    } else if (status == kStatusWaiting || status == kStatusPharmacy) {
      // Refresh UI every 5 seconds for other active statuses
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _QueueRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.appointment.status != oldWidget.appointment.status) {
      _initTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return '00:00';
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  String _waitTime() {
    final now = DateTime.now();
    final scheduled = widget.appointment.scheduledAt;
    final diff = now.difference(scheduled);
    final minutes = diff.inMinutes;

    if (minutes < 0) return 'Just now';
    if (minutes == 0) return '< 1 min';
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}m';
  }

  void _handleComplete(BuildContext context) {
    widget.onStatusChange(kStatusDone);
    // Fulfill prescription automatically if exists
    context.read<PrescriptionProvider>().markDispensedByAppointment(
        widget.appointment.id,
        syncService: context.read<SyncService>());
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final isWithDoctor = a.status == kStatusWithDoctor;
    final isDone = a.status == kStatusDone;
    final isPharmacy = a.status == kStatusPharmacy;

    // ── DONE: Faded ──
    if (isDone) {
      return Opacity(
        opacity: 0.4,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: context.cardColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: Text('#${a.tokenNumber.toString().padLeft(2, '0')}',
                    style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.textMutedColor)),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.onViewPatient,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.patientName,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: context.textMutedColor)),
                        Text('ID: P-${a.patientId}',
                            style: TextStyle(
                                fontSize: 10, color: context.textMutedColor.withValues(alpha: 0.7))),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text('Dr. ${a.doctorName}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: context.textMutedColor)),
              ),
              SizedBox(
                width: 180,
                child: Center(
                  child: Text('-- : --',
                      style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          color: context.textMutedColor)),
                ),
              ),
              SizedBox(
                width: 180,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: context.borderColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('DONE',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: context.textMutedColor)),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Icon(Icons.more_vert_rounded,
                      color: context.textMutedColor.withValues(alpha: 0.5), size: 20),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── WITH DOCTOR: Strong highlight ──
    if (isWithDoctor) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: const Border(
            left: BorderSide(color: AppTheme.primary, width: 6),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              child: Text('#${a.tokenNumber.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  _EditPatientBtn(onTap: widget.onEditPatient),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: widget.onViewPatient,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.patientName,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primary)),
                            const SizedBox(height: 2),
                            Text('ID: P-${a.patientId}',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.primary
                                        .withValues(alpha: 0.7))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  const Icon(Icons.medical_services_rounded,
                      size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text('Dr. ${a.doctorName}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary)),
                ],
              ),
            ),
            SizedBox(
              width: 180,
              child: Column(
                children: [
                  Text('ELAPSED',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: AppTheme.primary.withValues(alpha: 0.6))),
                  const SizedBox(height: 4),
                  Text(_formatDuration(_elapsed),
                      style: const TextStyle(
                          fontSize: 20,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary)),
                ],
              ),
            ),
            SizedBox(
              width: 180,
              child: Column(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Text('WITH DOCTOR',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: Colors.white)),
                  ),
                  const SizedBox(height: 4),
                  Text('Active',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary.withValues(alpha: 0.5))),
                ],
              ),
            ),
            SizedBox(
              width: 180,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _ActionBtn(
                    label: 'Prescribe',
                    icon: Icons.edit_note_rounded,
                    color: AppTheme.primary,
                    onTap: widget.onConsult,
                    filled: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── AT PHARMACY: Light highlight ──
    if (isPharmacy) {
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: const Border(
            left: BorderSide(color: AppTheme.success, width: 3),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              child: Text('#${a.tokenNumber.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  _EditPatientBtn(onTap: widget.onEditPatient),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: widget.onViewPatient,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.patientName,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primary)),
                            const SizedBox(height: 2),
                            Text('ID: P-${a.patientId}',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: context.textMutedColor)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text('Pharmacy Unit',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.textMutedColor)),
            ),
            SizedBox(
              width: 180,
              child: Center(
                child: Text(_waitTime(),
                    style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: AppTheme.success)),
              ),
            ),
            SizedBox(
              width: 180,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('AT PHARMACY',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: AppTheme.success)),
                ),
              ),
            ),
            SizedBox(
              width: 180,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _ActionBtn(
                    label: 'Complete',
                    icon: Icons.check_circle_rounded,
                    color: AppTheme.success,
                    onTap: () => _handleComplete(context),
                    filled: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── WAITING: Normal ──
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text('#${a.tokenNumber.toString().padLeft(2, '0')}',
                style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                _EditPatientBtn(onTap: widget.onEditPatient),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: widget.onViewPatient,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.patientName,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary)),
                          const SizedBox(height: 2),
                          Text('ID: P-${a.patientId}',
                              style: TextStyle(
                                  fontSize: 10, color: context.textMutedColor)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('Dr. ${a.doctorName}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.textMutedColor)),
          ),
          SizedBox(
            width: 180,
            child: Center(
              child: Text(_waitTime(),
                  style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: AppTheme.warning)),
            ),
          ),
          SizedBox(
            width: 180,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('WAITING',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: AppTheme.warningDark)),
              ),
            ),
          ),
          SizedBox(
            width: 180,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ActionBtn(
                  label: 'Call In',
                  icon: Icons.play_arrow_rounded,
                  color: AppTheme.primary,
                  onTap: () => widget.onStatusChange(kStatusWithDoctor),
                  filled: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action Button ───────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return Material(
        color: color,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 5),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}


// ── Payment Mode Dialog ──────────────────────────────────────────────────────

class _PaymentModeDialog extends StatefulWidget {
  final Appointment appointment;
  final Function(String paymentMethod) onConfirm;

  const _PaymentModeDialog({
    required this.appointment,
    required this.onConfirm,
  });

  @override
  State<_PaymentModeDialog> createState() => _PaymentModeDialogState();
}

class _PaymentModeDialogState extends State<_PaymentModeDialog> {
  String _selected = 'cash';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.payment_rounded,
                color: AppTheme.success, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Complete Appointment',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Select payment mode for consultation',
                    style:
                        TextStyle(fontSize: 12, color: context.textMutedColor)),
              ],
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.lightBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  child: Text(
                    widget.appointment.patientName.isNotEmpty
                        ? widget.appointment.patientName[0].toUpperCase()
                        : 'P',
                    style: const TextStyle(
                        color: AppTheme.primary, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.appointment.patientName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      Text(
                        'Token #${widget.appointment.tokenNumber} • ₹${widget.appointment.consultationFee.toStringAsFixed(0)}',
                        style: TextStyle(
                            color: context.textMutedColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _PaymentOption(
            icon: Icons.payments_rounded,
            label: 'Cash',
            value: 'cash',
            color: AppTheme.success,
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v),
          ),
          const SizedBox(height: 10),
          _PaymentOption(
            icon: Icons.qr_code_2_rounded,
            label: 'UPI',
            value: 'upi',
            color: AppTheme.primary,
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v),
          ),
          const SizedBox(height: 10),
          _PaymentOption(
            icon: Icons.credit_card_rounded,
            label: 'Card',
            value: 'card',
            color: AppTheme.accent,
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.success,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () {
            Navigator.pop(context);
            widget.onConfirm(_selected);
          },
          icon: const Icon(Icons.check_circle_rounded, size: 18),
          label: const Text('Complete'),
        ),
      ],
    );
  }
}

class _PaymentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String groupValue;
  final ValueChanged<String> onChanged;

  const _PaymentOption({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = groupValue == value;
    return Material(
      color: isSelected ? color.withValues(alpha: 0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: isSelected ? color : Colors.black87,
                  ),
                ),
              ),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 14),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty Queue ─────────────────────────────────────────────────────────────

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(60),
      child: Column(
        children: [
          Icon(Icons.people_outline_rounded,
              size: 48, color: context.textMutedColor),
          const SizedBox(height: 16),
          Text('No patients in queue today',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.textMutedColor)),
          const SizedBox(height: 4),
          Text('Add a patient using the button below',
              style: TextStyle(fontSize: 13, color: context.textMutedColor)),
        ],
      ),
    );
  }
}

class _EditPatientBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _EditPatientBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppTheme.primary.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: const Icon(Icons.edit_rounded,
            size: 14, color: AppTheme.primary),
      ),
    );
  }
}
