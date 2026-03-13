import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/models/appointment.dart';
import '../../../shared/providers/opd_provider.dart';
import '../../../shared/providers/prescription_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../shared/models/patient.dart';
import '../../../widgets/patient_dialogs.dart';
import '../../../shared/services/sync_service.dart';
import '../../opd/prescription_screen.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('OPD Queue — Today'),
      ),
      body: Column(
        children: [
          // Mobile-friendly stats bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _StatBadge(
                  label: '${opd.filteredPatientCount} Patients',
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                _StatBadge(
                  label: '${opd.filteredDoneCount} Done',
                  color: AppTheme.success,
                ),
                const SizedBox(width: 8),
                _StatBadge(
                  label:
                      '₹${opd.filteredConsultationRevenue.toStringAsFixed(0)} Fees',
                  color: AppTheme.accent,
                ),
              ],
            ),
          ),
          Expanded(
            child: queue.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.queue,
                            size: 72, color: context.textMutedColor),
                        const SizedBox(height: 16),
                        Text(
                          'No patients in queue today',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: context.textMutedColor),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add a patient using the + button below',
                          style: TextStyle(color: context.textMutedColor),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: queue.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) => _QueueCard(
                      appointment: queue[i],
                      onStatusChange: (newStatus) => context
                          .read<OpdProvider>()
                          .updateStatus(queue[i].id, newStatus,
                              context.read<SyncService>()),
                      onConsult: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PrescriptionScreen(appointment: queue[i]),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddPatientOptions(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Patient'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

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
              color: Colors.grey.withOpacity(0.3),
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

// ─── Queue Card ───────────────────────────────────────────────────────────────
class _QueueCard extends StatelessWidget {
  final Appointment appointment;
  final ValueChanged<String> onStatusChange;
  final VoidCallback onConsult;

  const _QueueCard({
    required this.appointment,
    required this.onStatusChange,
    required this.onConsult,
  });

  Color _statusColor(String status) {
    switch (status) {
      case kStatusWaiting:
        return AppTheme.warning;
      case kStatusWithDoctor:
        return AppTheme.primary;
      case kStatusPharmacy:
        return const Color(0xFF7C3AED);
      case kStatusDone:
        return AppTheme.success;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case kStatusWaiting:
        return 'Waiting';
      case kStatusWithDoctor:
        return 'With Doctor';
      case kStatusPharmacy:
        return 'At Pharmacy';
      case kStatusDone:
        return 'Done';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(appointment.status);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Token number
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '${appointment.tokenNumber}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Patient + doctor info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appointment.patientName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    'Dr. ${appointment.doctorName}  •  ₹${appointment.consultationFee.toStringAsFixed(0)}',
                    style:
                        TextStyle(color: context.textMutedColor, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusLabel(appointment.status),
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            // Action buttons
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (appointment.status == kStatusWaiting)
                  _ActionBtn(
                    label: '▶ Call In',
                    color: AppTheme.primary,
                    onTap: () => onStatusChange(kStatusWithDoctor),
                  ),
                if (appointment.status == kStatusWithDoctor) ...[
                  _ActionBtn(
                    label: '📋 Prescribe',
                    color: AppTheme.primary,
                    onTap: onConsult,
                  ),
                  const SizedBox(height: 6),
                  _ActionBtn(
                    label: '→ Pharmacy',
                    color: const Color(0xFF7C3AED),
                    onTap: () => onStatusChange(kStatusPharmacy),
                  ),
                ],
                if (appointment.status == kStatusPharmacy)
                  _ActionBtn(
                    label: '✓ Done',
                    color: AppTheme.success,
                    onTap: () => onStatusChange(kStatusDone),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
