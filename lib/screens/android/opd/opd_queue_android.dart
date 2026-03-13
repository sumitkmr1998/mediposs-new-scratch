import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/models/appointment.dart';
import '../../../shared/providers/opd_provider.dart';
import '../../../shared/providers/prescription_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../shared/models/patient.dart';
import '../../../widgets/android/patient_dialogs_android.dart';
import '../../../shared/services/sync_service.dart';
import '../../opd/prescription_screen.dart';

class OpdQueueAndroid extends StatefulWidget {
  const OpdQueueAndroid({super.key});

  @override
  State<OpdQueueAndroid> createState() => _OpdQueueAndroidState();
}

class _OpdQueueAndroidState extends State<OpdQueueAndroid>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OpdProvider>().loadAll();
      context.read<PrescriptionProvider>().load();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opd = context.watch<OpdProvider>();
    final allQueue = opd.todayQueue;
    final activeQueue = allQueue.where((a) => a.status != kStatusDone).toList();
    final completedQueue =
        allQueue.where((a) => a.status == kStatusDone).toList();

    return Scaffold(
      backgroundColor: context.surfaceColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddPatientOptions(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Patient'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: const Text('OPD Queue'),
            pinned: true,
            floating: true,
            forceElevated: innerBoxIsScrolled,
            elevation: innerBoxIsScrolled ? 4 : 0,
            bottom: TabBar(
              controller: _tabs,
              labelColor: AppTheme.primary,
              unselectedLabelColor: context.textMutedColor,
              indicatorColor: AppTheme.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              tabs: const [
                Tab(icon: Icon(Icons.people_alt), text: 'Active'),
                Tab(icon: Icon(Icons.check_circle_outline), text: 'Done'),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: SingleChildScrollView(
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
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            _QueueList(queue: activeQueue),
            _QueueList(queue: completedQueue),
          ],
        ),
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
              final patient =
                  await AndroidPatientDialogs.showRegistrationSheet(context);
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
              AndroidPatientDialogs.showSearchSheet(
                context,
                showSkip: false,
                onSelected: (p) => _showBookingDialog(context, p),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showBookingDialog(BuildContext context, Patient patient) {
    AndroidPatientDialogs.showBookingSheet(context, patient: patient);
  }
}

class _QueueList extends StatelessWidget {
  final List<Appointment> queue;
  const _QueueList({required this.queue});

  @override
  Widget build(BuildContext context) {
    if (queue.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.queue_play_next,
                size: 64, color: context.textMutedColor),
            const SizedBox(height: 16),
            Text('No patients in this list',
                style: TextStyle(
                    color: context.textMutedColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16).copyWith(bottom: 100),
      itemCount: queue.length,
      itemBuilder: (ctx, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _ModernQueueCard(
          appointment: queue[i],
          onStatusChange: (newStatus) => context
              .read<OpdProvider>()
              .updateStatus(
                  queue[i].id, newStatus, context.read<SyncService>()),
          onConsult: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PrescriptionScreen(appointment: queue[i]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Queue Card ───────────────────────────────────────────────────────────────
class _ModernQueueCard extends StatelessWidget {
  final Appointment appointment;
  final ValueChanged<String> onStatusChange;
  final VoidCallback onConsult;

  const _ModernQueueCard({
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

    return Container(
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
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Token number
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
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
                              fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                        'Dr. ${appointment.doctorName}  •  ₹${appointment.consultationFee.toStringAsFixed(0)}',
                        style: TextStyle(
                            color: context.textMutedColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: color),
                      const SizedBox(width: 6),
                      Text(
                        _statusLabel(appointment.status),
                        style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (appointment.status != kStatusDone) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                      color: context.borderColor.withValues(alpha: 0.3)),
                ),
              ),
              child: Row(
                children: [
                  if (appointment.status == kStatusWaiting)
                    Expanded(
                      child: _ActionBtn(
                        label: 'Call In',
                        icon: Icons.play_arrow_rounded,
                        color: AppTheme.primary,
                        onTap: () => onStatusChange(kStatusWithDoctor),
                      ),
                    ),
                  if (appointment.status == kStatusWithDoctor) ...[
                    Expanded(
                      child: _ActionBtn(
                        label: 'Prescribe',
                        icon: Icons.medical_information,
                        color: AppTheme.primary,
                        onTap: onConsult,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionBtn(
                        label: 'To Pharmacy',
                        icon: Icons.arrow_forward_rounded,
                        color: const Color(0xFF7C3AED),
                        onTap: () => onStatusChange(kStatusPharmacy),
                      ),
                    ),
                  ],
                  if (appointment.status == kStatusPharmacy)
                    Expanded(
                      child: _ActionBtn(
                        label: 'Mark Done',
                        icon: Icons.check_circle_outline,
                        color: AppTheme.success,
                        onTap: () => onStatusChange(kStatusDone),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
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
