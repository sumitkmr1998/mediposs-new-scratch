import 'package:flutter/material.dart';
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
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PatientProvider>().load();
    });
  }

  void _onScroll() {
    if (_scrollCtrl.hasClients &&
        _scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      context.read<PatientProvider>().loadMore();
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final patients = context.watch<PatientProvider>();
    final list = patients.filtered;
    final totalCount = patients.totalCount;

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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: context.borderColor.withValues(alpha: 0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) {
                    patients.setSearch(v);
                  },
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search by name, phone, or UHID...',
                    hintStyle: TextStyle(fontSize: 12, color: context.textMutedColor),
                    prefixIcon:
                        const Icon(Icons.search, size: 18, color: AppTheme.primary),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              patients.setSearch('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'LOADED ${list.length} OF $totalCount PATIENTS',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: context.textMutedColor,
                      letterSpacing: 1.2,
                    ),
                  ),
                  if (patients.isLoadingMore) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        body: list.isEmpty
            ? const AppEmptyState(
                icon: Icons.people_outline,
                title: 'No patients found',
              )
            : ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(20).copyWith(bottom: 100),
                itemCount: list.length + (patients.hasMore ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i == list.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: patients.isLoadingMore
                            ? const CircularProgressIndicator()
                            : TextButton.icon(
                                onPressed: () => patients.loadMore(),
                                icon: const Icon(Icons.arrow_downward, size: 16),
                                label: const Text('Load More Patients'),
                              ),
                      ),
                    );
                  }
                  final p = list[i];
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
class _ModernPatientTile extends StatefulWidget {
  final Patient patient;
  final VoidCallback onEdit;
  final VoidCallback onBook;

  const _ModernPatientTile({
    required this.patient,
    required this.onEdit,
    required this.onBook,
  });

  @override
  State<_ModernPatientTile> createState() => _ModernPatientTileState();
}

class _ModernPatientTileState extends State<_ModernPatientTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.subtleShadow,
        border: Border.all(
          color: _expanded
              ? AppTheme.primary.withValues(alpha: 0.3)
              : context.borderColor.withValues(alpha: 0.4),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          onLongPress: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                      child: Text(
                        widget.patient.name.isNotEmpty
                            ? widget.patient.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.patient.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(
                                _expanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                size: 18,
                                color: context.textMutedColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.patient.uhid}  •  ${widget.patient.gender}${widget.patient.ageYears > 0 ? "  •  ${widget.patient.ageYears}y" : ""}${widget.patient.phone.isNotEmpty ? "  •  ${widget.patient.phone}" : ""}',
                            style: TextStyle(
                                color: context.textMutedColor,
                                fontWeight: FontWeight.w500,
                                fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_expanded) ...[
                Container(
                  height: 1,
                  color: context.borderColor.withValues(alpha: 0.2),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ActionBtn(
                          label: 'Details',
                          icon: Icons.visibility_outlined,
                          color: AppTheme.primaryLight,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (ctx) =>
                                  PatientDetailsScreen(patientId: widget.patient.id),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _ActionBtn(
                          label: 'Book',
                          icon: Icons.add_box_rounded,
                          color: AppTheme.primary,
                          onTap: widget.onBook,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _ActionBtn(
                          label: 'Edit',
                          icon: Icons.edit_rounded,
                          color: AppTheme.indigo,
                          onTap: widget.onEdit,
                        ),
                      ),
                      const SizedBox(width: 6),
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
            'Are you sure you want to delete ${widget.patient.name}? This will remove all their medical history and photographs.'),
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
                  .deletePatient(widget.patient.id, syncService: sync);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Patient ${widget.patient.name} deleted'),
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
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
