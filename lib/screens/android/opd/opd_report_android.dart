import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../shared/models/appointment.dart';
import '../../../shared/providers/opd_provider.dart';
import '../../../shared/providers/prescription_provider.dart';
import '../../../theme/app_theme.dart';

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

    return Scaffold(
      backgroundColor: context.surfaceColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(
                'OPD Report — ${DateFormat('dd MMM yyyy').format(DateTime.now())}'),
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
                        isSelected: opd.activeFilter == OpdFilter.today,
                        onSelected: () => opd.setFilter(OpdFilter.today),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Yesterday',
                        isSelected: opd.activeFilter == OpdFilter.yesterday,
                        onSelected: () => opd.setFilter(OpdFilter.yesterday),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Last 7 Days',
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
                            builder: (ctx, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme:
                                      Theme.of(context).colorScheme.copyWith(
                                            primary: AppTheme.primary,
                                            onPrimary: Colors.white,
                                          ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (range != null) {
                            opd.setFilter(OpdFilter.custom, range: range);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                if (sortedDiagnoses.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
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
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.analytics_rounded,
                                      color: AppTheme.primary, size: 20),
                                ),
                                const SizedBox(width: 12),
                                const Text('TOP DIAGNOSES',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                        color: AppTheme.primaryLight)),
                              ],
                            ),
                          ),
                          Container(
                              height: 1,
                              color:
                                  context.borderColor.withValues(alpha: 0.3)),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: sortedDiagnoses
                                  .take(10)
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
                                                      fontSize: 15)),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 6),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primary
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                  '${entry.value} cases',
                                                  style: const TextStyle(
                                                      color: AppTheme.primary,
                                                      fontSize: 12,
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
                  const SizedBox(height: 8),
                ],

                // Per-doctor stats
                if (opd.activeDoctors.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
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
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.groups_rounded,
                                      color: AppTheme.primary, size: 20),
                                ),
                                const SizedBox(width: 12),
                                const Text('PER DOCTOR STATS',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                        color: AppTheme.primaryLight)),
                              ],
                            ),
                          ),
                          Container(
                              height: 1,
                              color:
                                  context.borderColor.withValues(alpha: 0.3)),
                          ...opd.activeDoctors.map((doc) {
                            final docAppts = queue
                                .where((a) => a.doctorId == doc.id)
                                .toList();
                            final docRevenue = docAppts.fold(
                                0.0, (s, a) => s + a.consultationFee);
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.person,
                                        color: AppTheme.primary),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Dr. ${doc.name}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15)),
                                        const SizedBox(height: 4),
                                        Text(doc.specialization,
                                            style: TextStyle(
                                                color: context.textMutedColor,
                                                fontWeight: FontWeight.w500,
                                                fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('${docAppts.length} tokens',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14)),
                                      const SizedBox(height: 4),
                                      Text('₹${docRevenue.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.success,
                                              fontSize: 14)),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ],
            ),
          ),

          // Patient List (SliverList to dynamically scroll below everything)
          if (queue.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: Text('Appointments in Range',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final appt = queue[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: context.borderColor.withValues(alpha: 0.5)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
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
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        subtitle: Text(
                          'Dr. ${appt.doctorName} • ${DateFormat('h:mm a').format(appt.scheduledAt)}',
                          style: TextStyle(
                              color: context.textMutedColor, fontSize: 13),
                        ),
                        trailing: _buildStatusChip(appt.status),
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
                child: Text('No appointments found for this period.',
                    style: TextStyle(color: context.textMutedColor)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color bg = Colors.grey.withValues(alpha: 0.1);
    Color fg = Colors.grey;

    if (status == kStatusWaiting) {
      bg = AppTheme.warning.withValues(alpha: 0.1);
      fg = AppTheme.warningDark;
    } else if (status == kStatusWithDoctor) {
      bg = AppTheme.primaryLight.withValues(alpha: 0.1);
      fg = AppTheme.primaryLight;
    } else if (status == kStatusPharmacy) {
      bg = const Color(0xFF7C3AED).withValues(alpha: 0.1);
      fg = const Color(0xFF7C3AED);
    } else if (status == kStatusDone) {
      bg = AppTheme.success.withValues(alpha: 0.1);
      fg = AppTheme.success;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withValues(alpha: 0.2)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
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
          color: isSelected ? AppTheme.primary : context.surfaceColor.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.primary
                : context.borderColor.withValues(alpha: 0.3),
          ),
          boxShadow: isSelected ? [
            BoxShadow(color: AppTheme.primary.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2))
          ] : null,
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: isSelected ? Colors.white : context.textMutedColor,
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
