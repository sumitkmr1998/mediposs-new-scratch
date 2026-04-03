import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../shared/providers/opd_provider.dart';
import '../../../shared/providers/prescription_provider.dart';
import '../../../shared/models/appointment.dart';
import '../../../theme/app_theme.dart';

class OpdReportWindows extends StatefulWidget {
  const OpdReportWindows({super.key});

  @override
  State<OpdReportWindows> createState() => _OpdReportWindowsState();
}

class _OpdReportWindowsState extends State<OpdReportWindows> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Appointment> _filtered(List<Appointment> items) {
    if (_searchQuery.isEmpty) return items;
    final q = _searchQuery.toLowerCase();
    return items.where((a) {
      return a.patientName.toLowerCase().contains(q) ||
          a.doctorName.toLowerCase().contains(q) ||
          a.status.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final opd = context.watch<OpdProvider>();
    final pProvider = context.watch<PrescriptionProvider>();

    final displayed = _filtered(opd.displayedQueue);

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

    final rangeLabel = _getRangeLabel(opd);
    final totalPatients = opd.filteredPatientCount;
    final doneCount = opd.filteredDoneCount;
    final revenue = opd.filteredConsultationRevenue;

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
              child: const Icon(Icons.local_hospital_rounded,
                  color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('OPD Report',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                Text('$rangeLabel overview',
                    style:
                        TextStyle(fontSize: 12, color: context.textMutedColor)),
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
            // KPI Cards
            LayoutBuilder(builder: (ctx, constraints) {
              final cols = constraints.maxWidth > 900
                  ? 4
                  : (constraints.maxWidth > 600 ? 2 : 1);
              const spacing = 16.0;
              final cardWidth =
                  (constraints.maxWidth - (cols - 1) * spacing) / cols;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  _KpiCard(
                    label: 'Total Patients',
                    value: '$totalPatients',
                    icon: Icons.people_rounded,
                    color: AppTheme.primary,
                    count: rangeLabel,
                    width: cardWidth,
                  ),
                  _KpiCard(
                    label: 'Completed',
                    value: '$doneCount',
                    icon: Icons.check_circle_rounded,
                    color: AppTheme.success,
                    count: totalPatients > 0
                        ? '${(doneCount / totalPatients * 100).toStringAsFixed(0)}% completion'
                        : 'No data',
                    width: cardWidth,
                  ),
                  _KpiCard(
                    label: 'Consultation Revenue',
                    value: '₹${revenue.toStringAsFixed(0)}',
                    icon: Icons.currency_rupee_rounded,
                    color: AppTheme.accent,
                    count: '$rangeLabel earnings',
                    width: cardWidth,
                  ),
                  _KpiCard(
                    label: 'Active Doctors',
                    value: '${opd.activeDoctors.length}',
                    icon: Icons.medical_services_rounded,
                    color: AppTheme.purple,
                    count: 'On duty',
                    width: cardWidth,
                  ),
                ],
              );
            }),

            const SizedBox(height: 24),

            // Filter + Search
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip(
                            opd, 'Today', Icons.today_rounded, OpdFilter.today),
                        const SizedBox(width: 8),
                        _buildFilterChip(opd, 'Yesterday',
                            Icons.history_rounded, OpdFilter.yesterday),
                        const SizedBox(width: 8),
                        _buildFilterChip(opd, 'Last 7 Days',
                            Icons.date_range_rounded, OpdFilter.last7Days),
                        const SizedBox(width: 8),
                        _buildFilterChip(opd, 'All Time',
                            Icons.all_inbox_rounded, OpdFilter.allTime),
                        const SizedBox(width: 8),
                        _buildFilterChip(opd, 'Custom',
                            Icons.calendar_month_rounded, OpdFilter.custom,
                            isCustom: true),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search patient, doctor...',
                      hintStyle: TextStyle(
                          fontSize: 13, color: context.textMutedColor),
                      prefixIcon: Icon(Icons.search_rounded,
                          size: 20, color: context.textMutedColor),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Top Diagnoses
            if (sortedDiagnoses.isNotEmpty) ...[
              Text('Top Diagnoses',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ...sortedDiagnoses.take(8).map((entry) {
                        final maxVal = sortedDiagnoses.first.value;
                        final ratio = entry.value / maxVal;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(entry.key,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13)),
                              ),
                              Expanded(
                                flex: 4,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: ratio,
                                    minHeight: 8,
                                    backgroundColor:
                                        AppTheme.primary.withValues(alpha: 0.1),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                            AppTheme.primary),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 80,
                                child: Text(
                                    '${entry.value} case${entry.value > 1 ? 's' : ''}',
                                    style: const TextStyle(
                                        color: AppTheme.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                    textAlign: TextAlign.end),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Per Doctor Stats
            if (opd.activeDoctors.isNotEmpty) ...[
              Text('Per Doctor',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (ctx, constraints) {
                final cols = constraints.maxWidth > 800
                    ? 3
                    : (constraints.maxWidth > 500 ? 2 : 1);
                const spacing = 12.0;
                final cardWidth =
                    (constraints.maxWidth - (cols - 1) * spacing) / cols;

                final queue = opd.filteredQueue;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: opd.activeDoctors.map((doc) {
                    final docAppts =
                        queue.where((a) => a.doctorId == doc.id).toList();
                    final docRevenue =
                        docAppts.fold(0.0, (s, a) => s + a.consultationFee);
                    return SizedBox(
                      width: cardWidth,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor:
                                    AppTheme.primary.withValues(alpha: 0.1),
                                child: Text(
                                  doc.name.isNotEmpty
                                      ? doc.name[0].toUpperCase()
                                      : 'D',
                                  style: const TextStyle(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Dr. ${doc.name}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14),
                                        overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 2),
                                    Text(doc.specialization,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: context.textMutedColor)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${docAppts.length}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 18,
                                          color: AppTheme.primary)),
                                  Text('₹${docRevenue.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.success)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              }),
              const SizedBox(height: 24),
            ],

            // Appointments List
            Text('Appointments',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Showing ${displayed.length} of ${opd.filteredPatientCount} records',
              style: TextStyle(fontSize: 12, color: context.textMutedColor),
            ),
            const SizedBox(height: 12),

            if (displayed.isEmpty)
              _EmptyState(hasQuery: _searchQuery.isNotEmpty)
            else ...[
              // Table header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.06),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                        width: 50,
                        child: Text('#',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: Colors.grey))),
                    const SizedBox(width: 12),
                    Expanded(
                        flex: 3,
                        child: Text('PATIENT', style: _headerStyle(context))),
                    Expanded(
                        flex: 2,
                        child: Text('DOCTOR', style: _headerStyle(context))),
                    SizedBox(
                        width: 120,
                        child: Text('TIME', style: _headerStyle(context))),
                    SizedBox(
                        width: 120,
                        child: Text('FEE', style: _headerStyle(context))),
                    SizedBox(
                        width: 120,
                        child: Text('STATUS', style: _headerStyle(context))),
                  ],
                ),
              ),
              // Rows
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: context.borderColor),
                    right: BorderSide(color: context.borderColor),
                    bottom: BorderSide(color: context.borderColor),
                  ),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: Column(
                  children: [
                    ...List.generate(
                      displayed.length,
                      (i) => Column(
                        children: [
                          _AppointmentRow(appt: displayed[i]),
                          if (i < displayed.length - 1)
                            Divider(height: 1, color: context.borderColor),
                        ],
                      ),
                    ),
                    // Load More
                    if (opd.hasMore)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Material(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => opd.loadMore(),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppTheme.primary
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.expand_more_rounded,
                                      color: AppTheme.primary, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Load More (${opd.filteredPatientCount - displayed.length} remaining)',
                                    style: const TextStyle(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
      OpdProvider opd, String label, IconData icon, OpdFilter filter,
      {bool isCustom = false}) {
    final isSelected = opd.activeFilter == filter;
    return Material(
      color: isSelected ? AppTheme.primary : context.surfaceColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          if (isCustom) {
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
              builder: (ctx, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: Theme.of(context).colorScheme.copyWith(
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
          } else {
            opd.setFilter(filter);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppTheme.primary : context.borderColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color: isSelected ? Colors.white : context.textMutedColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : context.textMutedColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _headerStyle(BuildContext context) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: context.textMutedColor,
        letterSpacing: 1,
      );

  String _getRangeLabel(OpdProvider opd) {
    switch (opd.activeFilter) {
      case OpdFilter.today:
        return "Today's";
      case OpdFilter.yesterday:
        return "Yesterday's";
      case OpdFilter.last7Days:
        return "7 Days'";
      case OpdFilter.allTime:
        return "All-time";
      case OpdFilter.custom:
        return "Custom";
    }
  }
}

// ── KPI Card ────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String count;
  final double width;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.count,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: color)),
                    const SizedBox(height: 2),
                    Text(label,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 2),
                    Text(count,
                        style: TextStyle(
                            fontSize: 11, color: context.textMutedColor)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Appointment Row ─────────────────────────────────────────────────────────

class _AppointmentRow extends StatelessWidget {
  final Appointment appt;
  const _AppointmentRow({required this.appt});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Token number
          SizedBox(
            width: 50,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '#${appt.tokenNumber}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.primary),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Patient
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  child: Text(
                    appt.patientName.isNotEmpty
                        ? appt.patientName[0].toUpperCase()
                        : 'P',
                    style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(appt.patientName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          // Doctor
          Expanded(
            flex: 2,
            child: Text('Dr. ${appt.doctorName}',
                style: TextStyle(fontSize: 13, color: context.textMutedColor),
                overflow: TextOverflow.ellipsis),
          ),
          // Time
          SizedBox(
            width: 120,
            child: Text(
              DateFormat('h:mm a').format(appt.scheduledAt),
              style: TextStyle(fontSize: 12, color: context.textMutedColor),
            ),
          ),
          // Fee
          SizedBox(
            width: 120,
            child: Text(
              '₹${appt.consultationFee.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppTheme.success),
            ),
          ),
          // Status
          SizedBox(width: 120, child: _StatusBadge(status: appt.status)),
        ],
      ),
    );
  }
}

// ── Status Badge ────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (status) {
      kStatusWaiting => (AppTheme.warningDark, Icons.hourglass_top_rounded),
      kStatusWithDoctor => (AppTheme.primaryLight, Icons.healing_rounded),
      kStatusPharmacy => (AppTheme.purple, Icons.local_pharmacy_rounded),
      kStatusDone => (AppTheme.success, Icons.check_circle_rounded),
      _ => (Colors.grey, Icons.circle_outlined),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            status.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}

// ── Empty State ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasQuery;
  const _EmptyState({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(60),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: context.borderColor),
          right: BorderSide(color: context.borderColor),
          bottom: BorderSide(color: context.borderColor),
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasQuery
                  ? Icons.search_off_rounded
                  : Icons.local_hospital_rounded,
              size: 40,
              color: AppTheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasQuery
                ? 'No matching appointments found'
                : 'No appointments in this period',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasQuery
                ? 'Try adjusting your search query'
                : 'Appointments will appear here once booked',
            style: TextStyle(fontSize: 13, color: context.textMutedColor),
          ),
        ],
      ),
    );
  }
}
