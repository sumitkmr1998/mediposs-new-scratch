import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../shared/providers/opd_provider.dart';
import '../../../shared/providers/prescription_provider.dart';
import '../../../shared/models/appointment.dart';
import '../../../theme/app_theme.dart';

class OpdReportWindows extends StatelessWidget {
  const OpdReportWindows({super.key});

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
      appBar: AppBar(
        title: Text(
            'OPD Report — ${DateFormat('dd MMM yyyy').format(DateTime.now())}'),
      ),
      body: Column(
        children: [
          // Date Filter Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              border: Border(
                  bottom: BorderSide(
                      color: context.borderColor.withValues(alpha: 0.5))),
            ),
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
                    );
                    if (range != null) {
                      opd.setFilter(OpdFilter.custom, range: range);
                    }
                  },
                ),
              ],
            ),
          ),

          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (sortedDiagnoses.isNotEmpty) ...[
                        Text('Top Diagnoses Today',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        ...sortedDiagnoses.take(10).map((entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(entry.key,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text('${entry.value} cases',
                                        style: const TextStyle(
                                            color: AppTheme.primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            )),
                        const SizedBox(height: 24),
                      ],

                      // Per-doctor stats
                      if (opd.activeDoctors.isNotEmpty) ...[
                        Text('Per Doctor',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        ...opd.activeDoctors.map((doc) {
                          final docAppts =
                              queue.where((a) => a.doctorId == doc.id).toList();
                          final docRevenue = docAppts.fold(
                              0.0, (s, a) => s + a.consultationFee);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(Icons.person,
                                  color: AppTheme.primary),
                              title: Text('Dr. ${doc.name}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(doc.specialization,
                                  style:
                                      TextStyle(color: context.textMutedColor)),
                              trailing: Text(
                                '${docAppts.length} patients  •  ₹${docRevenue.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.success),
                              ),
                            ),
                          );
                        }),
                      ],
                    ]),
                  ),
                ),

                // Patient List
                if (queue.isNotEmpty) ...[
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverToBoxAdapter(
                      child: Text('Appointments in Range',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.all(20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final appt = queue[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.person, size: 20),
                              ),
                              title: Text(appt.patientName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  'Dr. ${appt.doctorName} • ${DateFormat('h:mm a').format(appt.scheduledAt)}'),
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
          ),
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
      bg = Color(0xFF7C3AED).withValues(alpha: 0.1);
      fg = const Color(0xFF7C3AED);
    } else if (status == kStatusDone) {
      bg = AppTheme.success.withValues(alpha: 0.1);
      fg = AppTheme.success;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w800,
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
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onSelected(),
        selectedColor: AppTheme.primary.withValues(alpha: 0.2),
        checkmarkColor: AppTheme.primary,
        labelStyle: TextStyle(
          color: isSelected ? AppTheme.primary : context.textMutedColor,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
