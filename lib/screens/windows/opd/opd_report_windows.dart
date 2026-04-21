import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../shared/providers/opd_provider.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/providers/prescription_provider.dart';
import '../../../shared/models/appointment.dart';
import '../../../theme/app_theme.dart';
import '../../../shared/widgets/app_kpi_card.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_status_badge.dart';

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
      appBar: _buildAppBar(rangeLabel),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildKpiSection(
                totalPatients, doneCount, revenue, opd, rangeLabel),
            const SizedBox(height: 24),
            _buildFilterSearchCard(context, opd),
            const SizedBox(height: 24),
            if (sortedDiagnoses.isNotEmpty) ...[
              _buildDiagnosesSection(sortedDiagnoses),
              const SizedBox(height: 24),
            ],
            if (opd.activeDoctors.isNotEmpty) ...[
              _buildDoctorSection(opd, displayed),
              const SizedBox(height: 24),
            ],
            _buildAppointmentsTable(context, displayed, opd),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(String rangeLabel) {
    return AppBar(
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
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text('$rangeLabel overview',
                  style:
                      TextStyle(fontSize: 12, color: context.textMutedColor)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiSection(int totalPatients, int doneCount, double revenue,
      OpdProvider opd, String rangeLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('OVERVIEW',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: context.textMutedColor)),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (ctx, constraints) {
          final cols = constraints.maxWidth > 1000
              ? 4
              : (constraints.maxWidth > 700 ? 2 : 1);
          const spacing = 16.0;
          final cardWidth =
              (constraints.maxWidth - (cols - 1) * spacing) / cols;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              AppKpiCard(
                label: 'Total Patients',
                value: '$totalPatients',
                icon: Icons.people_rounded,
                color: AppTheme.primary,
                subtitle: rangeLabel,
                width: cardWidth,
              ),
              AppKpiCard(
                label: 'Completed',
                value: '$doneCount',
                icon: Icons.check_circle_rounded,
                color: AppTheme.success,
                subtitle: totalPatients > 0
                    ? '${(doneCount / totalPatients * 100).toStringAsFixed(0)}% completion'
                    : 'No data',
                width: cardWidth,
              ),
              AppKpiCard(
                label: 'Consultation Revenue',
                value: '₹${revenue.toStringAsFixed(0)}',
                icon: Icons.currency_rupee_rounded,
                color: AppTheme.accent,
                subtitle: '$rangeLabel earnings',
                width: cardWidth,
              ),
              AppKpiCard(
                label: 'Active Doctors',
                value: '${opd.activeDoctors.length}',
                icon: Icons.medical_services_rounded,
                color: AppTheme.purple,
                subtitle: 'On duty',
                width: cardWidth,
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildFilterSearchCard(BuildContext context, OpdProvider opd) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  AppFilterChip(
                    label: 'Today',
                    icon: Icons.today_rounded,
                    isSelected: opd.activeFilter == OpdFilter.today,
                    onTap: () => opd.setFilter(OpdFilter.today),
                    style: AppFilterChipStyle.filled,
                  ),
                  if (context.watch<AuthProvider>().currentUser?.canViewHistoricalData ?? true) ...[
                    const SizedBox(width: 8),
                    AppFilterChip(
                      label: 'Yesterday',
                      icon: Icons.history_rounded,
                      isSelected: opd.activeFilter == OpdFilter.yesterday,
                      onTap: () => opd.setFilter(OpdFilter.yesterday),
                      style: AppFilterChipStyle.filled,
                    ),
                    const SizedBox(width: 8),
                    AppFilterChip(
                      label: 'Last 7 Days',
                      icon: Icons.date_range_rounded,
                      isSelected: opd.activeFilter == OpdFilter.last7Days,
                      onTap: () => opd.setFilter(OpdFilter.last7Days),
                      style: AppFilterChipStyle.filled,
                    ),
                    const SizedBox(width: 8),
                    AppFilterChip(
                      label: 'All Time',
                      icon: Icons.all_inbox_rounded,
                      isSelected: opd.activeFilter == OpdFilter.allTime,
                      onTap: () => opd.setFilter(OpdFilter.allTime),
                      style: AppFilterChipStyle.filled,
                    ),
                  ],
                  const SizedBox(width: 8),
                  AppFilterChip(
                    label: 'Custom',
                    icon: Icons.calendar_month_rounded,
                    isSelected: opd.activeFilter == OpdFilter.custom,
                    onTap: () async {
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
                    style: AppFilterChipStyle.filled,
                  ),
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
                hintText: 'Search OPD...',
                hintStyle:
                    TextStyle(fontSize: 13, color: context.textMutedColor),
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosesSection(List<MapEntry<String, int>> sortedDiagnoses) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Top Diagnoses',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: context.textMutedColor)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: context.borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
            ],
          ),
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
                                fontWeight: FontWeight.w500, fontSize: 13)),
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
                            valueColor: const AlwaysStoppedAnimation<Color>(
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
      ],
    );
  }

  Widget _buildDoctorSection(OpdProvider opd, List<Appointment> displayed) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Per Doctor',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: context.textMutedColor)),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (ctx, constraints) {
          final cols = constraints.maxWidth > 800
              ? 3
              : (constraints.maxWidth > 500 ? 2 : 1);
          const spacing = 16.0;
          final cardWidth =
              (constraints.maxWidth - (cols - 1) * spacing) / cols;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: opd.activeDoctors.map((doc) {
              final docAppts =
                  displayed.where((a) => a.doctorId == doc.id).toList();
              final docRevenue =
                  docAppts.fold(0.0, (s, a) => s + a.consultationFee);
              return SizedBox(
                width: cardWidth,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(color: context.borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                            AppTheme.primary.withValues(alpha: 0.1),
                        child: Text(
                          doc.name.isNotEmpty ? doc.name[0].toUpperCase() : 'D',
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
                                    fontWeight: FontWeight.w600, fontSize: 14),
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
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  Widget _buildAppointmentsTable(
      BuildContext context, List<Appointment> displayed, OpdProvider opd) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 4),
          child: Text(
            'FOUND ${displayed.length} OF ${opd.filteredPatientCount} RECORDS',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: context.textMutedColor,
                letterSpacing: 1.5),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border:
                Border.all(color: context.borderColor.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: displayed.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(40),
                  child: AppEmptyState(
                    icon: _searchQuery.isNotEmpty
                        ? Icons.search_off_rounded
                        : Icons.local_hospital_rounded,
                    title: _searchQuery.isNotEmpty
                        ? 'No matching appointments found'
                        : 'No appointments in this period',
                    subtitle: _searchQuery.isNotEmpty
                        ? 'Try adjusting your search query'
                        : 'Appointments will appear here once booked',
                    iconColor: AppTheme.primary,
                  ),
                )
              : Column(
                  children: [
                    _buildTableHeader(),
                    Divider(height: 1, color: context.borderColor),
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
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusCard)),
      ),
      child: Row(
        children: [
          SizedBox(width: 50, child: Text('#', style: _headerStyle())),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: Text('PATIENT', style: _headerStyle())),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: Text('DOCTOR', style: _headerStyle())),
          const SizedBox(width: 12),
          SizedBox(
              width: 120,
              child: Center(child: Text('TIME', style: _headerStyle()))),
          const SizedBox(width: 12),
          SizedBox(
              width: 120,
              child: Center(child: Text('FEE', style: _headerStyle()))),
          const SizedBox(width: 12),
          SizedBox(
              width: 120,
              child: Center(child: Text('STATUS', style: _headerStyle()))),
        ],
      ),
    );
  }

  TextStyle _headerStyle() => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: context.textMutedColor);

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
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text('Dr. ${appt.doctorName}',
                style: TextStyle(fontSize: 13, color: context.textMutedColor),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Text(
              DateFormat('h:mm a').format(appt.scheduledAt),
              style: TextStyle(fontSize: 12, color: context.textMutedColor),
            ),
          ),
          const SizedBox(width: 12),
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
          const SizedBox(width: 12),
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

    return AppStatusBadge(
      label: status.toUpperCase(),
      color: color,
      icon: icon,
      style: AppStatusBadgeStyle.icon,
      fontSize: 10,
      fontWeight: FontWeight.w700,
    );
  }
}
