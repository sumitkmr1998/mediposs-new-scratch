import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../shared/models/patient.dart';
import '../../../shared/providers/patient_provider.dart';
import '../../../shared/services/sync_service.dart';
import '../../../theme/app_theme.dart';
import '../../opd/patient_details_screen.dart';
import '../../../widgets/android/patient_dialogs_android.dart';
import '../../../shared/widgets/app_empty_state.dart';

class PatientListAndroid extends StatefulWidget {
  const PatientListAndroid({super.key});

  @override
  State<PatientListAndroid> createState() => _PatientListAndroidState();
}

class _PatientListAndroidState extends State<PatientListAndroid> {
  final _searchCtrl = TextEditingController();
  int _currentPage = 1;
  final int _pageSize = 10;

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
    final totalItems = list.length;
    final totalPages = (totalItems / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages > 0 ? totalPages : 1);
    final startIndex = (currentPage - 1) * _pageSize;
    final endIndex = (startIndex + _pageSize).clamp(0, totalItems);
    final paginatedList = list.isEmpty ? <Patient>[] : list.sublist(startIndex, endIndex);

    return Scaffold(
      backgroundColor: context.surfaceColor,
      body: RefreshIndicator(
        onRefresh: () async {
          final sync = context.read<SyncService>();
          if (sync.isCloudMode) {
            await sync.syncAllFromCloud();
          } else {
            await sync.syncAll();
          }
          if (mounted) {
            context.read<PatientProvider>().load();
          }
        },
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
            title: const Text('Patients'),
            pinned: true,
            floating: true,
            forceElevated: innerBoxIsScrolled,
            elevation: innerBoxIsScrolled ? 4 : 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.person_add),
                tooltip: 'Add Patient',
                onPressed: () => _showPatientDialog(context),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: context.borderColor.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) {
                    patients.setSearch(v);
                    setState(() => _currentPage = 1);
                  },
                  decoration: InputDecoration(
                    hintText: 'Search by name, phone, or UHID...',
                    hintStyle: TextStyle(color: context.textMutedColor),
                    prefixIcon:
                        const Icon(Icons.search, color: AppTheme.primary),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ),
            ),
          ),
        ],
        body: paginatedList.isEmpty
            ? const AppEmptyState(
                icon: Icons.people_outline,
                title: 'No patients found',
              )
            : ListView.builder(
                padding: const EdgeInsets.all(20).copyWith(bottom: 100),
                itemCount: paginatedList.length,
                itemBuilder: (ctx, i) {
                  final p = paginatedList[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ModernPatientTile(
                      patient: p,
                      onEdit: () => _showPatientDialog(context, patient: p),
                      onBook: () => _showBookAppointmentDialog(context, p),
                    ),
                  );
                },
              ),
      ),
    ),
      bottomNavigationBar: list.isEmpty ? null : Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          border: Border(top: BorderSide(color: context.borderColor)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Showing ${totalItems == 0 ? 0 : startIndex + 1}-$endIndex of $totalItems',
                style: TextStyle(color: context.textMutedColor, fontSize: 13),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: currentPage > 1
                        ? () => setState(() => _currentPage = currentPage - 1)
                        : null,
                  ),
                  Text(
                    'Page $currentPage of ${totalPages > 0 ? totalPages : 1}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: currentPage < totalPages
                        ? () => setState(() => _currentPage = currentPage + 1)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPatientDialog(context),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Add Patient',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _showPatientDialog(BuildContext context, {Patient? patient}) {
    AndroidPatientDialogs.showRegistrationSheet(context, patient: patient);
  }

  void _showBookAppointmentDialog(BuildContext context, Patient p) {
    AndroidPatientDialogs.showBookingSheet(context, patient: p);
  }
}

// ─── Patient Tile ─────────────────────────────────────────────────────────────
class _ModernPatientTile extends StatelessWidget {
  final Patient patient;
  final VoidCallback onEdit;
  final VoidCallback onBook;

  const _ModernPatientTile({
    required this.patient,
    required this.onEdit,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => PatientDetailsScreen(patientId: patient.id),
            ),
          ),
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          patient.name.isNotEmpty
                              ? patient.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patient.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${patient.uhid}  •  ${patient.gender}${patient.ageYears > 0 ? "  •  ${patient.ageYears}y" : ""}${patient.phone.isNotEmpty ? "  •  ${patient.phone}" : ""}',
                            style: TextStyle(
                                color: context.textMutedColor,
                                fontWeight: FontWeight.w500,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                        color: context.borderColor.withValues(alpha: 0.3)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: _ActionBtn(
                        label: 'Book Appt',
                        icon: Icons.add_box_rounded,
                        color: AppTheme.primary,
                        onTap: onBook,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionBtn(
                        label: 'Edit',
                        icon: Icons.edit_rounded,
                        color: AppTheme.indigo,
                        onTap: onEdit,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionBtn(
                        label: 'Delete',
                        icon: Icons.delete_outline_rounded,
                        color: AppTheme.danger,
                        onTap: () => _confirmDelete(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Patient?'),
        content: Text(
            'Are you sure you want to delete ${patient.name}? This will remove all their medical history and photographs.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final sync = context.read<SyncService>();
              context
                  .read<PatientProvider>()
                  .deletePatient(patient.id, syncService: sync);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Patient ${patient.name} deleted'),
                  backgroundColor: AppTheme.danger,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
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
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
