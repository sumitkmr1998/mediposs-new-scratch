import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/models/patient.dart';
import '../../../shared/providers/patient_provider.dart';
import '../../../shared/services/sync_service.dart';
import '../../../theme/app_theme.dart';
import '../../opd/patient_details_screen.dart';
import '../../../widgets/patient_dialogs.dart';

class PatientListWindows extends StatefulWidget {
  const PatientListWindows({super.key});

  @override
  State<PatientListWindows> createState() => _PatientListWindowsState();
}

class _PatientListWindowsState extends State<PatientListWindows> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PatientProvider>().load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final patients = context.watch<PatientProvider>();
    final list = patients.filtered;
    final allPatients = patients.patients;

    final maleCount = allPatients.where((p) => p.gender == 'Male').length;
    final femaleCount = allPatients.where((p) => p.gender == 'Female').length;

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
              child: const Icon(Icons.people_rounded,
                  color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Patients',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                Text('${allPatients.length} registered',
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
            // Stats Row
            LayoutBuilder(builder: (ctx, constraints) {
              final cols = constraints.maxWidth > 800
                  ? 3
                  : (constraints.maxWidth > 500 ? 2 : 1);
              const spacing = 12.0;
              final cardWidth =
                  (constraints.maxWidth - (cols - 1) * spacing) / cols;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  _StatCard(
                    label: 'Total Patients',
                    value: '${allPatients.length}',
                    icon: Icons.groups_rounded,
                    color: AppTheme.primary,
                    width: cardWidth,
                  ),
                  _StatCard(
                    label: 'Male',
                    value: '$maleCount',
                    icon: Icons.male_rounded,
                    color: AppTheme.primaryLight,
                    width: cardWidth,
                  ),
                  _StatCard(
                    label: 'Female',
                    value: '$femaleCount',
                    icon: Icons.female_rounded,
                    color: AppTheme.danger,
                    width: cardWidth,
                  ),
                ],
              );
            }),

            const SizedBox(height: 24),

            // Search
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => patients.setSearch(v),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search by name, phone, or UHID...',
                      hintStyle: TextStyle(
                          fontSize: 13, color: context.textMutedColor),
                      prefixIcon: Icon(Icons.search_rounded,
                          size: 20, color: context.textMutedColor),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                patients.setSearch('');
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${list.length} results',
                  style: TextStyle(fontSize: 12, color: context.textMutedColor),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Bento Table
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
                            width: 140,
                            child: Text('UHID', style: _headerStyle(context))),
                        const SizedBox(width: 12),
                        const Expanded(
                            flex: 3,
                            child: Text('NAME',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                    color: AppTheme.primaryLight))),
                        const SizedBox(
                            width: 80,
                            child: Center(
                                child: Text('GENDER',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.5,
                                        color: AppTheme.primaryLight)))),
                        const SizedBox(
                            width: 70,
                            child: Center(
                                child: Text('AGE',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.5,
                                        color: AppTheme.primaryLight)))),
                        const SizedBox(
                            width: 140,
                            child: Text('PHONE',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                    color: AppTheme.primaryLight))),
                        const SizedBox(
                            width: 140,
                            child: Align(
                                alignment: Alignment.centerRight,
                                child: Text('ACTIONS',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.5,
                                        color: AppTheme.primaryLight)))),
                      ],
                    ),
                  ),

                  Divider(height: 1, color: context.borderColor),

                  const SizedBox(height: 4),

                  // Patient Rows
                  if (list.isEmpty)
                    _EmptyState(hasSearch: _searchCtrl.text.isNotEmpty)
                  else
                    ...list.map((p) => _PatientRow(
                          patient: p,
                          onEdit: () => _showPatientDialog(context, patient: p),
                          onBook: () => _showBookAppointmentDialog(context, p),
                          onView: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (ctx) =>
                                  PatientDetailsScreen(patientId: p.id),
                            ),
                          ),
                        )),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPatientDialog(context),
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
      color: context.textMutedColor);

  void _showPatientDialog(BuildContext context, {Patient? patient}) {
    showDialog(
      context: context,
      builder: (ctx) => PatientDialog(patient: patient),
    );
  }

  void _showBookAppointmentDialog(BuildContext context, Patient p) {
    showDialog(
      context: context,
      builder: (ctx) => BookAppointmentDialog(patient: p),
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

// ── Patient Row ─────────────────────────────────────────────────────────────

class _PatientRow extends StatelessWidget {
  final Patient patient;
  final VoidCallback onEdit;
  final VoidCallback onBook;
  final VoidCallback onView;

  const _PatientRow({
    required this.patient,
    required this.onEdit,
    required this.onBook,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          // UHID
          SizedBox(
            width: 140,
            child: Text(patient.uhid,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    color: AppTheme.primary)),
          ),
          const SizedBox(width: 12),
          // Name + avatar
          Expanded(
            flex: 3,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onView,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                      child: Text(
                        patient.name.isNotEmpty
                            ? patient.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(patient.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Gender
          SizedBox(
            width: 80,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: patient.gender == 'Male'
                      ? AppTheme.primary.withValues(alpha: 0.1)
                      : patient.gender == 'Female'
                          ? AppTheme.danger.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  patient.gender,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: patient.gender == 'Male'
                        ? AppTheme.primary
                        : patient.gender == 'Female'
                            ? AppTheme.danger
                            : Colors.grey,
                  ),
                ),
              ),
            ),
          ),
          // Age
          SizedBox(
            width: 70,
            child: Center(
              child: Text(
                patient.ageYears > 0 ? '${patient.ageYears}y' : '--',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.textMutedColor),
              ),
            ),
          ),
          // Phone
          SizedBox(
            width: 140,
            child: Text(
              patient.phone.isNotEmpty ? patient.phone : '--',
              style: TextStyle(
                  fontSize: 13,
                  color: context.textMutedColor,
                  fontFamily: patient.phone.isNotEmpty ? 'monospace' : null),
            ),
          ),
          // Actions
          SizedBox(
            width: 140,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ActionBtn(
                  icon: Icons.visibility_rounded,
                  color: AppTheme.primary,
                  onTap: onView,
                  tooltip: 'View',
                ),
                const SizedBox(width: 4),
                _ActionBtn(
                  icon: Icons.calendar_month_rounded,
                  color: AppTheme.primaryLight,
                  onTap: onBook,
                  tooltip: 'Book',
                ),
                const SizedBox(width: 4),
                _ActionBtn(
                  icon: Icons.edit_rounded,
                  color: AppTheme.warning,
                  onTap: onEdit,
                  tooltip: 'Edit',
                ),
                const SizedBox(width: 4),
                _ActionBtn(
                  icon: Icons.delete_rounded,
                  color: AppTheme.danger,
                  onTap: () => _confirmDelete(context),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_rounded,
                  color: AppTheme.danger, size: 22),
            ),
            const SizedBox(width: 12),
            const Text('Delete Patient?',
                style: TextStyle(color: AppTheme.danger)),
          ],
        ),
        content: Text(
            'Are you sure you want to delete ${patient.name}? This will remove all their medical history.'),
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text('Cancel', style: TextStyle(color: context.textMutedColor)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final sync = context.read<SyncService>();
              context
                  .read<PatientProvider>()
                  .deletePatient(patient.id, syncService: sync);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text('Patient ${patient.name} deleted'),
                    ],
                  ),
                  backgroundColor: AppTheme.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white),
            icon: const Icon(Icons.delete_rounded, size: 18),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Action Button ───────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}

// ── Empty State ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasSearch;
  const _EmptyState({required this.hasSearch});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(60),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasSearch
                  ? Icons.search_off_rounded
                  : Icons.people_outline_rounded,
              size: 40,
              color: AppTheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch ? 'No patients found' : 'No patients registered yet',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.textColor),
          ),
          const SizedBox(height: 6),
          Text(
            hasSearch
                ? 'Try adjusting your search query'
                : 'Add a patient using the button below',
            style: TextStyle(fontSize: 13, color: context.textMutedColor),
          ),
        ],
      ),
    );
  }
}
