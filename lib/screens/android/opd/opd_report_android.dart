import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../shared/models/appointment.dart';
import '../../../shared/providers/opd_provider.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/providers/prescription_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../shared/widgets/app_status_badge.dart';
import '../../../shared/widgets/app_kpi_card.dart';
import '../../../shared/services/objectbox_service.dart';
import '../../../shared/models/sale.dart';
import '../../../objectbox.g.dart';

class OpdReportAndroid extends StatelessWidget {
  const OpdReportAndroid({super.key});

  @override
  Widget build(BuildContext context) {
    final opd = context.watch<OpdProvider>();
    final pProvider = context.watch<PrescriptionProvider>();

    final queue = opd.filteredQueue;

    // Top diagnoses from filtered prescriptions
    final Map<String, int> diagnosisCount = {};
    for (final p in pProvider.prescriptions) {
      final dt = p.createdAt;
      bool matchesFilter = true;
      if (opd.customStart != null && opd.customEnd != null) {
        matchesFilter =
            dt.isAfter(opd.customStart!.subtract(const Duration(seconds: 1))) &&
                dt.isBefore(opd.customEnd!.add(const Duration(seconds: 1)));
      }
      if (matchesFilter && p.diagnosis.isNotEmpty) {
        diagnosisCount[p.diagnosis] = (diagnosisCount[p.diagnosis] ?? 0) + 1;
      }
    }
    final sortedDiagnoses = diagnosisCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Summary Stats
    final totalPatients = opd.filteredPatientCount;
    final doneCount = opd.filteredDoneCount;
    final revenue = opd.filteredConsultationRevenue;
    final activeDocs = opd.activeDoctors.length;
    final avgWait = opd.filteredAverageWaitingTime;
    final avgDoctor = opd.filteredAverageDoctorTime;

    return Scaffold(
      backgroundColor: context.surfaceColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('OPD Report'),
                Text(
                  opd.activeFilter == OpdFilter.custom && opd.customStart != null && opd.customEnd != null
                      ? '${DateFormat('dd MMM').format(opd.customStart!)} - ${DateFormat('dd MMM yyyy').format(opd.customEnd!)}'
                      : DateFormat('dd MMM yyyy').format(DateTime.now()),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                ),
              ],
            ),
            floating: true,
            pinned: true,
            elevation: 4,
            forceElevated: true,
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date Filter Bar
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'Today',
                        isSelected: opd.activeFilter == OpdFilter.today || !(context.read<AuthProvider>().currentUser?.canViewHistoricalData ?? true),
                        onSelected: () => opd.setFilter(OpdFilter.today),
                      ),
                      if (context.watch<AuthProvider>().currentUser?.canViewHistoricalData ?? true) ...[
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Yesterday',
                          isSelected: opd.activeFilter == OpdFilter.yesterday,
                          onSelected: () => opd.setFilter(OpdFilter.yesterday),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: '7 Days',
                          isSelected: opd.activeFilter == OpdFilter.last7Days,
                          onSelected: () => opd.setFilter(OpdFilter.last7Days),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'All Time',
                          isSelected: opd.activeFilter == OpdFilter.allTime,
                          onSelected: () => opd.setFilter(OpdFilter.allTime),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Custom',
                          isSelected: opd.activeFilter == OpdFilter.custom,
                          onSelected: () async {
                            final range = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                              locale: const Locale('en', 'GB'),
                              initialEntryMode: DatePickerEntryMode.input,
                            );
                            if (range != null) {
                              opd.setFilter(OpdFilter.custom, range: range);
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),

                // KPI Summary Row (NEW)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SUMMARY OVERVIEW',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: AppTheme.primary)),
                      const SizedBox(height: 16),
                      GridView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 2.2,
                        ),
                        children: [
                          _CompactKpiCard(
                            label: 'Total Patients',
                            value: '$totalPatients',
                            icon: Icons.people_rounded,
                            color: AppTheme.primary,
                          ),
                          _CompactKpiCard(
                            label: 'Attended (Done)',
                            value: '$doneCount',
                            icon: Icons.check_circle_rounded,
                            color: AppTheme.success,
                          ),
                          _CompactKpiCard(
                            label: 'Cons. Revenue',
                            value: '₹${revenue.toStringAsFixed(0)}',
                            icon: Icons.currency_rupee_rounded,
                            color: AppTheme.accent,
                          ),
                          _CompactKpiCard(
                            label: 'Doctors',
                            value: '$activeDocs',
                            icon: Icons.medical_services_rounded,
                            color: AppTheme.purple,
                          ),
                          _CompactKpiCard(
                            label: 'Avg. Wait Time',
                            value: _formatDuration(avgWait),
                            icon: Icons.access_time_rounded,
                            color: AppTheme.warning,
                          ),
                          _CompactKpiCard(
                            label: 'Avg. Doctor Time',
                            value: _formatDuration(avgDoctor),
                            icon: Icons.healing_rounded,
                            color: AppTheme.primaryLight,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                if (sortedDiagnoses.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: AppTheme.subtleShadow,
                        border: Border.all(
                            color: context.borderColor.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.analytics_rounded,
                                      color: AppTheme.primary, size: 18),
                                ),
                                const SizedBox(width: 12),
                                const Text('TOP DIAGNOSES',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1,
                                        color: AppTheme.primary)),
                              ],
                            ),
                          ),
                          Container(
                              height: 1,
                              color: context.borderColor.withValues(alpha: 0.3)),
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: sortedDiagnoses
                                  .take(8)
                                  .map((entry) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(entry.key,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 14)),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primary
                                                    .withValues(alpha: 0.08),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                  '${entry.value} cases',
                                                  style: const TextStyle(
                                                      color: AppTheme.primary,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800)),
                                            ),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Per-doctor stats
                // We should iterate over ALL doctors who have activity in the range, 
                // but for now we'll match Windows logic which maps over all active doctors but shows activity.
                if (opd.doctors.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const Text('PER DOCTOR PERFORMANCE',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: AppTheme.primary)),
                  ),
                  const SizedBox(height: 16),
                  ...opd.doctors.where((d) {
                    // Show if active OR has appointments in filter
                    final count = queue.where((a) => a.doctorName == d.name).length;
                    return d.isActive || count > 0;
                  }).map((doc) {
                    final docAppts = queue
                        .where((a) => a.doctorName == doc.name)
                        .toList();
                    final attendedCount = docAppts
                        .where((a) => a.status == kStatusDone)
                        .length;
                    final docRevenue = docAppts.fold(
                        0.0, (s, a) => s + a.consultationFee);
                    
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: AppTheme.subtleShadow,
                        border: Border.all(
                            color: context.borderColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                            child: Text(doc.name[0], style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Dr. ${doc.name}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15)),
                                Text(doc.specialization,
                                    style: TextStyle(
                                        color: context.textMutedColor,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('$attendedCount Attended',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.primary,
                                      fontSize: 14)),
                              const SizedBox(height: 2),
                              Text('₹${docRevenue.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.success,
                                      fontSize: 14)),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 32),
                ],
              ],
            ),
          ),

          // Patient List
          if (queue.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: Text('Visit History (${queue.length})',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppTheme.primary)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final appt = queue[index];
                    final db = ObjectBoxService.instance;
                    final sales = db.saleBox
                        .query(Sale_.linkedAppointmentId.equals(appt.id))
                        .build()
                        .find();
                    
                    Sale? opdSale;
                    Sale? dispenseSale;
                    for (final s in sales) {
                      if (s.invoiceNo.startsWith('OPD-')) {
                        opdSale = s;
                      } else {
                        dispenseSale = s;
                      }
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: context.borderColor.withValues(alpha: 0.5)),
                        boxShadow: AppTheme.subtleShadow,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppTheme.primary.withValues(alpha: 0.1),
                          child: const Icon(Icons.person,
                              color: AppTheme.primary, size: 20),
                        ),
                        title: Text(appt.patientName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dr. ${appt.doctorName} • ${DateFormat('h:mm a').format(appt.scheduledAt)}',
                              style: TextStyle(
                                  color: context.textMutedColor, fontSize: 12),
                            ),
                            if (opdSale != null || dispenseSale != null) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 4,
                                runSpacing: 2,
                                children: [
                                  if (opdSale != null)
                                    Text('OPD ID: ${opdSale.invoiceNo}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: context.textMutedColor,
                                            fontWeight: FontWeight.w500)),
                                  if (opdSale != null && dispenseSale != null)
                                    Text('|',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: context.borderColor)),
                                  if (dispenseSale != null)
                                    Text('Receipt: ${dispenseSale.invoiceNo}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: context.textMutedColor,
                                            fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ],
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _buildStatusChip(appt.status),
                            const SizedBox(height: 4),
                            Text('₹${appt.consultationFee.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.success)),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: queue.length,
                ),
              ),
            ),
          ] else ...[
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('No records found for this period.',
                    style: TextStyle(color: context.textMutedColor)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color = Colors.grey;

    if (status == kStatusWaiting) {
      color = AppTheme.warningDark;
    } else if (status == kStatusWithDoctor) {
      color = AppTheme.primaryLight;
    } else if (status == kStatusPharmacy) {
      color = AppTheme.purple;
    } else if (status == kStatusDone) {
      color = AppTheme.success;
    }

    return AppStatusBadge(
      label: status.toUpperCase(),
      color: color,
      style: AppStatusBadgeStyle.text,
      fontSize: 9,
      fontWeight: FontWeight.w800,
    );
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds <= 0) return '--';
    final mins = d.inMinutes;
    if (mins < 1) {
      return '< 1m';
    }
    if (mins < 60) {
      return '${mins}m';
    }
    final hrs = d.inHours;
    final remainingMins = mins % 60;
    if (remainingMins == 0) return '${hrs}h';
    return '${hrs}h ${remainingMins}m';
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary
              : context.surfaceColor.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.primary
                : context.borderColor.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: isSelected ? Colors.white : context.textMutedColor,
            fontWeight: FontWeight.w800,
            fontSize: 10,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _CompactKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _CompactKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: context.textMutedColor,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
