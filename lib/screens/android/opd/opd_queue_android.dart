import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../../shared/models/appointment.dart';
import '../../../shared/providers/opd_provider.dart';
import '../../../shared/providers/prescription_provider.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../shared/models/patient.dart';
import '../../../widgets/android/patient_dialogs_android.dart';
import '../../../shared/services/sync_service.dart';
import '../../../shared/providers/patient_provider.dart';
import '../../opd/prescription_screen.dart';
import '../../../shared/widgets/app_status_badge.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/providers/cart_provider.dart';
import '../../../shared/providers/navigation_provider.dart';
import '../../../shared/providers/procedure_provider.dart';
import '../../../shared/providers/inventory_provider.dart';
import '../../../shared/providers/sales_provider.dart';

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
        elevation: 4,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final sync = context.read<SyncService>();
          await sync.syncAll();
          if (mounted) {
            context.read<OpdProvider>().loadAll();
            context.read<PatientProvider>().load();
            context.read<PrescriptionProvider>().load();
          }
        },
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
            title: const Text('OPD Queue'),
            pinned: true,
            floating: true,
            forceElevated: innerBoxIsScrolled,
            elevation: innerBoxIsScrolled ? 4 : 0,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: context.borderColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TabBar(
                  controller: _tabs,
                  labelColor: Colors.white,
                  unselectedLabelColor: context.textMutedColor,
                  indicator: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  tabs: const [
                    Tab(text: 'ACTIVE QUEUE'),
                    Tab(text: 'COMPLETED'),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.08),
                    AppTheme.accent.withValues(alpha: 0.03),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MetricColumn(
                    value: '${opd.filteredPatientCount}',
                    label: 'Patients',
                    icon: Icons.people_alt_outlined,
                    color: AppTheme.primary,
                  ),
                  const _MetricDivider(),
                  _MetricColumn(
                    value: '${opd.filteredDoneCount}',
                    label: 'Completed',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppTheme.success,
                  ),
                  const _MetricDivider(),
                  _MetricColumn(
                    value: '₹${opd.filteredConsultationRevenue.toStringAsFixed(0)}',
                    label: 'Fees',
                    icon: Icons.currency_rupee_rounded,
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
      return const AppEmptyState(
        icon: Icons.queue_play_next,
        title: 'No patients in this list',
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
          onCancel: () {
            final currentUser = context.read<AuthProvider>().currentUser;
            context.read<OpdProvider>().cancelAppointment(
                queue[i].id,
                context.read<SyncService>(),
                currentUser,
                context.read<SalesProvider>());
          },
        ),
      ),
    );
  }
}

class _ModernQueueCard extends StatefulWidget {
  final Appointment appointment;
  final ValueChanged<String> onStatusChange;
  final VoidCallback onConsult;
  final VoidCallback onCancel;

  const _ModernQueueCard({
    required this.appointment,
    required this.onStatusChange,
    required this.onConsult,
    required this.onCancel,
  });

  @override
  State<_ModernQueueCard> createState() => _ModernQueueCardState();
}

class _ModernQueueCardState extends State<_ModernQueueCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _ModernQueueCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.appointment.status != oldWidget.appointment.status) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _getDuration() {
    final now = DateTime.now();
    Duration diff;
    String prefix = "";

    switch (widget.appointment.status) {
      case kStatusWaiting:
        diff = now.difference(widget.appointment.scheduledAt);
        prefix = "Wait: ";
        break;
      case kStatusWithDoctor:
        if (widget.appointment.calledAt == null) return "Consulting";
        diff = now.difference(widget.appointment.calledAt!);
        prefix = "In Cabin: ";
        break;
      case kStatusPharmacy:
        if (widget.appointment.pharmacyAt == null) {
          return "Wait: ${_format(now.difference(widget.appointment.scheduledAt))}";
        }
        diff = now.difference(widget.appointment.pharmacyAt!);
        prefix = "Pharm: ";
        break;
      case kStatusDone:
        if (widget.appointment.completedAt == null) {
          return "Done";
        }
        diff = widget.appointment.completedAt!
            .difference(widget.appointment.scheduledAt);
        prefix = "Total: ";
        break;
      default:
        return "";
    }

    return "$prefix${_format(diff)}";
  }

  String _format(Duration d) {
    if (d.isNegative) return "0m";
    if (d.inMinutes < 60) return "${d.inMinutes}m";
    return "${d.inHours}h ${d.inMinutes % 60}m";
  }

  Color _statusColor(String status) {
    switch (status) {
      case kStatusWaiting:
        return AppTheme.warning;
      case kStatusWithDoctor:
        return AppTheme.primary;
      case kStatusPharmacy:
        return AppTheme.purple;
      case kStatusDone:
        return AppTheme.success;
      case kStatusCancelled:
        return AppTheme.danger;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case kStatusWaiting:
        return 'WAITING';
      case kStatusWithDoctor:
        return 'CONSULTING';
      case kStatusPharmacy:
        return 'PHARMACY';
      case kStatusDone:
        return 'DONE';
      case kStatusCancelled:
        return 'CANCELLED';
      default:
        return status.toUpperCase();
    }
  }

  void _confirmCancel(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Appointment?'),
        content: Text('Are you sure you want to cancel for ${widget.appointment.patientName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('KEEP')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            onPressed: () {
              widget.onCancel();
              Navigator.pop(ctx);
            },
            child: const Text('YES, CANCEL'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(widget.appointment.status);

    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: context.borderColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Token number - High Density Premium
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.2),
                        color.withValues(alpha: 0.05)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('TOKEN',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: Colors.grey)),
                      Text(
                        '${widget.appointment.tokenNumber}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: color,
                          letterSpacing: -1,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Patient + doctor info - Editorial Typo
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.appointment.patientName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 17,
                                        letterSpacing: -0.2)),
                                Text(
                                  'UHID: ${context.read<PatientProvider>().getById(widget.appointment.patientId)?.uhid ?? widget.appointment.patientId}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: context.textMutedColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _getDuration(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: color,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                              if (widget.appointment.status != kStatusDone)
                                PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert, color: context.textMutedColor, size: 20),
                                  padding: EdgeInsets.zero,
                                  onSelected: (value) {
                                    if (value == 'cancel') {
                                      _confirmCancel(context);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'cancel',
                                      child: Row(
                                        children: [
                                          Icon(Icons.cancel_outlined, color: AppTheme.danger, size: 18),
                                          SizedBox(width: 8),
                                          Text('Cancel Appointment', style: TextStyle(color: AppTheme.danger)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          AppStatusBadge(
                            label: _statusLabel(widget.appointment.status),
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'DR. ${widget.appointment.doctorName.toUpperCase()}',
                            style: TextStyle(
                                color: context.textMutedColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (widget.appointment.status != kStatusDone) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.textMutedColor.withValues(alpha: 0.03),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(24)),
                border: Border(
                    top: BorderSide(
                        color: context.borderColor.withValues(alpha: 0.2))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.appointment.status == kStatusWaiting)
                    _ActionBtn(
                      label: 'CALL PATIENT',
                      icon: Icons.play_arrow_rounded,
                      color: AppTheme.primary,
                      onTap: () => widget.onStatusChange(kStatusWithDoctor),
                      isFilled: true,
                    ),
                  if (widget.appointment.status == kStatusWithDoctor) ...[
                    if (context.read<AuthProvider>().canAccessMedicalRecords) ...[
                      _ActionBtn(
                        label: 'PRESCRIBE',
                        icon: Icons.medical_information_rounded,
                        color: AppTheme.primary,
                        onTap: widget.onConsult,
                        isFilled: true,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Builder(builder: (ctx) {
                      final prescription = ctx.read<PrescriptionProvider>().getPrescriptionForAppointment(widget.appointment.id);
                      if (ctx.read<AuthProvider>().canDispenseMedicines && prescription != null) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ActionBtn(
                            label: 'DISPENSE',
                            icon: Icons.medication_rounded,
                            color: AppTheme.success,
                            onTap: () {
                              ctx.read<CartProvider>().loadPrescriptionIntoCart(
                                prescription: prescription,
                                inv: ctx.read<InventoryProvider>(),
                                patientProv: ctx.read<PatientProvider>(),
                                pProvider: ctx.read<PrescriptionProvider>(),
                                procProv: ctx.read<ProcedureProvider>(),
                              );
                              ctx.read<NavigationProvider>().selectDestination('pos');
                            },
                            isFilled: true,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                    _ActionBtn(
                      label: 'TO PHARMACY',
                      icon: Icons.arrow_forward_rounded,
                      color: AppTheme.purple,
                      onTap: () => widget.onStatusChange(kStatusPharmacy),
                      isFilled: false,
                    ),
                  ],
                  if (widget.appointment.status == kStatusPharmacy) ...[
                    Builder(builder: (ctx) {
                      final prescription = ctx.read<PrescriptionProvider>().getPrescriptionForAppointment(widget.appointment.id);
                      if (ctx.read<AuthProvider>().canDispenseMedicines && prescription != null) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ActionBtn(
                            label: 'DISPENSE',
                            icon: Icons.medication_rounded,
                            color: AppTheme.success,
                            onTap: () {
                              ctx.read<CartProvider>().loadPrescriptionIntoCart(
                                prescription: prescription,
                                inv: ctx.read<InventoryProvider>(),
                                patientProv: ctx.read<PatientProvider>(),
                                pProvider: ctx.read<PrescriptionProvider>(),
                                procProv: ctx.read<ProcedureProvider>(),
                              );
                              ctx.read<NavigationProvider>().selectDestination('pos');
                            },
                            isFilled: true,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                    _ActionBtn(
                      label: 'MARK COMPLETED',
                      icon: Icons.check_circle_rounded,
                      color: AppTheme.success,
                      onTap: () => widget.onStatusChange(kStatusDone),
                      isFilled: true,
                    ),
                  ],
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
  final bool isFilled;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isFilled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isFilled ? color : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isFilled ? color : color.withValues(alpha: 0.15)),
            boxShadow: isFilled
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isFilled ? Colors.white : color),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: isFilled ? Colors.white : color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _MetricColumn({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: context.textMutedColor,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: context.borderColor.withValues(alpha: 0.2),
    );
  }
}
