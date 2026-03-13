import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add Patient',
            onPressed: () => _showPatientDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => patients.setSearch(v),
              decoration: const InputDecoration(
                hintText: 'Search by name, phone, or UHID...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: patients.filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: context.textMutedColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No patients found',
                          style: TextStyle(color: context.textMutedColor),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: patients.filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final p = patients.filtered[i];
                      return _PatientTile(
                        patient: p,
                        onEdit: () => _showPatientDialog(context, patient: p),
                        onBook: () => _showBookAppointmentDialog(context, p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

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

// ─── Patient Tile ─────────────────────────────────────────────────────────────
class _PatientTile extends StatelessWidget {
  final Patient patient;
  final VoidCallback onEdit;
  final VoidCallback onBook;

  const _PatientTile({
    required this.patient,
    required this.onEdit,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
        child: Text(
          patient.name.isNotEmpty ? patient.name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: AppTheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        patient.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${patient.uhid}  •  ${patient.gender}${patient.ageYears > 0 ? "  •  ${patient.ageYears}y" : ""}${patient.phone.isNotEmpty ? "  •  ${patient.phone}" : ""}',
        style: TextStyle(color: context.textMutedColor, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Book Appointment',
            child: IconButton(
              icon: const Icon(
                Icons.add_box_outlined,
                color: AppTheme.primary,
                size: 20,
              ),
              onPressed: onBook,
            ),
          ),
          Tooltip(
            message: 'Edit',
            child: IconButton(
              icon: Icon(
                Icons.edit_outlined,
                color: context.textMutedColor,
                size: 20,
              ),
              onPressed: onEdit,
            ),
          ),
          Tooltip(
            message: 'Delete',
            child: IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: AppTheme.danger,
                size: 20,
              ),
              onPressed: () => _confirmDelete(context),
            ),
          ),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => PatientDetailsScreen(patientId: patient.id),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
