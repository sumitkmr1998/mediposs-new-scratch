import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/models/patient.dart';
import '../../../shared/providers/patient_provider.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/services/sync_service.dart';
import '../../../theme/app_theme.dart';
import '../../../shared/widgets/app_kpi_card.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_status_badge.dart';
import '../../opd/patient_details_screen.dart';
import '../../../widgets/patient_dialogs.dart';

class PatientListWindows extends StatefulWidget {
  const PatientListWindows({super.key});

  @override
  State<PatientListWindows> createState() => _PatientListWindowsState();
}

class _PatientListWindowsState extends State<PatientListWindows> {
  final _searchCtrl = TextEditingController();
  String _filter = 'all';
  int _currentPage = 1;
  int _pageSize = 10;

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
    final otherCount = allPatients.length - maleCount - femaleCount;

    final filteredList = _filter == 'all'
        ? list
        : _filter == 'male'
            ? list.where((p) => p.gender == 'Male').toList()
            : _filter == 'female'
                ? list.where((p) => p.gender == 'Female').toList()
                : list
                    .where((p) => p.gender != 'Male' && p.gender != 'Female')
                    .toList();

    final totalItems = filteredList.length;
    final totalPages = (totalItems / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages > 0 ? totalPages : 1);
    final startIndex = (currentPage - 1) * _pageSize;
    final endIndex = (startIndex + _pageSize).clamp(0, totalItems);
    final paginatedList = filteredList.isEmpty ? <Patient>[] : filteredList.sublist(startIndex, endIndex);

    return Scaffold(
      appBar: _buildAppBar(allPatients.length),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildKpiSection(allPatients.length, maleCount, femaleCount),
            const SizedBox(height: 24),
            _buildFilterSearchCard(context, patients),
            const SizedBox(height: 24),
            _buildDataTable(
              context,
              paginatedList,
              patients,
              currentPage,
              totalPages,
              totalItems,
              startIndex,
              endIndex,
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

  PreferredSizeWidget _buildAppBar(int total) {
    return AppBar(
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
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text('$total registered',
                  style:
                      TextStyle(fontSize: 12, color: context.textMutedColor)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiSection(int total, int male, int female) {
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
          final cols = constraints.maxWidth > 800
              ? 3
              : (constraints.maxWidth > 500 ? 2 : 1);
          const spacing = 16.0;
          final cardWidth =
              (constraints.maxWidth - (cols - 1) * spacing) / cols;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              AppKpiCard(
                label: 'Total Patients',
                value: '$total',
                icon: Icons.groups_rounded,
                color: AppTheme.primary,
                width: cardWidth,
              ),
              AppKpiCard(
                label: 'Male',
                value: '$male',
                icon: Icons.male_rounded,
                color: AppTheme.primaryLight,
                width: cardWidth,
              ),
              AppKpiCard(
                label: 'Female',
                value: '$female',
                icon: Icons.female_rounded,
                color: AppTheme.danger,
                width: cardWidth,
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildFilterSearchCard(
      BuildContext context, PatientProvider patients) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: context.borderColor),
        boxShadow: AppTheme.subtleShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  AppFilterChip(
                    label: 'All',
                    icon: Icons.groups_rounded,
                    isSelected: _filter == 'all',
                    onTap: () => setState(() {
                      _filter = 'all';
                      _currentPage = 1;
                    }),
                  ),
                  const SizedBox(width: 8),
                  AppFilterChip(
                    label: 'Male',
                    icon: Icons.male_rounded,
                    isSelected: _filter == 'male',
                    onTap: () => setState(() {
                      _filter = 'male';
                      _currentPage = 1;
                    }),
                    activeColor: AppTheme.primaryLight,
                  ),
                  const SizedBox(width: 8),
                  AppFilterChip(
                    label: 'Female',
                    icon: Icons.female_rounded,
                    isSelected: _filter == 'female',
                    onTap: () => setState(() {
                      _filter = 'female';
                      _currentPage = 1;
                    }),
                    activeColor: AppTheme.danger,
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
              onChanged: (v) {
                patients.setSearch(v);
                setState(() => _currentPage = 1);
              },
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search patients...',
                hintStyle:
                    TextStyle(fontSize: 13, color: context.textMutedColor),
                prefixIcon: Icon(Icons.search_rounded,
                    size: 20, color: context.textMutedColor),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          patients.setSearch('');
                          setState(() => _currentPage = 1);
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

  Widget _buildDataTable(
    BuildContext context,
    List<Patient> list,
    PatientProvider patients,
    int currentPage,
    int totalPages,
    int totalItems,
    int startIndex,
    int endIndex,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 4),
          child: Text(
            'FOUND $totalItems PATIENTS',
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
          child: Column(
            children: [
              _buildTableHeader(),
              Divider(height: 1, color: context.borderColor),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: AppEmptyState(
                    icon: _searchCtrl.text.isNotEmpty
                        ? Icons.search_off_rounded
                        : Icons.people_outline_rounded,
                    title: _searchCtrl.text.isNotEmpty
                        ? 'No patients found'
                        : 'No patients registered yet',
                    subtitle: _searchCtrl.text.isNotEmpty
                        ? 'Try adjusting your search query'
                        : 'Add a patient using the button below',
                    iconColor: AppTheme.primary,
                  ),
                )
              else ...[
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
                Divider(height: 1, color: context.borderColor),
                _buildPaginationFooter(currentPage, totalPages, totalItems, startIndex, endIndex),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaginationFooter(
    int currentPage,
    int totalPages,
    int totalItems,
    int startIndex,
    int endIndex,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 13, color: context.textMutedColor),
              children: [
                const TextSpan(text: 'Showing '),
                TextSpan(
                  text: '${totalItems == 0 ? 0 : startIndex + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' to '),
                TextSpan(
                  text: '$endIndex',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' of '),
                TextSpan(
                  text: '$totalItems',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' patients'),
              ],
            ),
          ),
          Row(
            children: [
              Text(
                'Rows per page: ',
                style: TextStyle(fontSize: 13, color: context.textMutedColor),
              ),
              const SizedBox(width: 4),
              DropdownButtonHideUnderline(
                child: SizedBox(
                  height: 32,
                  child: DropdownButton<int>(
                    value: _pageSize,
                    items: [10, 25, 50, 100].map((size) {
                      return DropdownMenuItem<int>(
                        value: size,
                        child: Text('$size', style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _pageSize = val;
                          _currentPage = 1;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                onPressed: currentPage > 1
                    ? () => setState(() => _currentPage = currentPage - 1)
                    : null,
                tooltip: 'Previous Page',
              ),
              ..._buildPageNumbers(currentPage, totalPages),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                onPressed: currentPage < totalPages
                    ? () => setState(() => _currentPage = currentPage + 1)
                    : null,
                tooltip: 'Next Page',
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPageNumbers(int currentPage, int totalPages) {
    List<Widget> buttons = [];
    final List<int> pagesToShow = [];
    if (totalPages <= 5) {
      for (int i = 1; i <= totalPages; i++) {
        pagesToShow.add(i);
      }
    } else {
      pagesToShow.add(1);
      for (int i = currentPage - 1; i <= currentPage + 1; i++) {
        if (i > 1 && i < totalPages) {
          pagesToShow.add(i);
        }
      }
      pagesToShow.add(totalPages);
    }

    int lastPage = 0;
    for (var page in pagesToShow) {
      if (lastPage > 0 && page - lastPage > 1) {
        buttons.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('...', style: TextStyle(color: context.textMutedColor)),
          ),
        );
      }
      
      final isSelected = page == currentPage;
      buttons.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _currentPage = page),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? AppTheme.primary : Colors.transparent,
                ),
              ),
              child: Center(
                child: Text(
                  '$page',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : context.textMutedColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      lastPage = page;
    }
    
    return buttons;
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
          SizedBox(
              width: 140, child: Text('UHID', style: _headerStyle(context))),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: Text('NAME', style: _headerStyle(context))),
          const SizedBox(width: 12),
          SizedBox(
              width: 80,
              child:
                  Center(child: Text('GENDER', style: _headerStyle(context)))),
          const SizedBox(width: 12),
          SizedBox(
              width: 70,
              child: Center(child: Text('AGE', style: _headerStyle(context)))),
          const SizedBox(width: 12),
          SizedBox(
              width: 140, child: Text('PHONE', style: _headerStyle(context))),
          const SizedBox(width: 12),
          SizedBox(
              width: 140,
              child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('ACTIONS', style: _headerStyle(context)))),
        ],
      ),
    );
  }

  TextStyle _headerStyle([BuildContext? ctx]) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: ctx?.textMutedColor ?? context.textMutedColor);

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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.02),
      ),
      child: Row(
        children: [
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
          SizedBox(
            width: 80,
            child: Center(
              child: AppStatusBadge(
                label: patient.gender,
                color: patient.gender == 'Male'
                    ? AppTheme.primary
                    : patient.gender == 'Female'
                        ? AppTheme.danger
                        : Colors.grey,
                style: AppStatusBadgeStyle.text,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
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
                if (context.read<AuthProvider>().currentUser?.canDeletePatients == true)
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
