import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/models/doctor.dart';
import '../../../shared/providers/opd_provider.dart';
import '../../../shared/services/sync_service.dart';
import '../../../theme/app_theme.dart';

class DoctorListWindows extends StatefulWidget {
  const DoctorListWindows({super.key});

  @override
  State<DoctorListWindows> createState() => _DoctorListWindowsState();
}

class _DoctorListWindowsState extends State<DoctorListWindows> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OpdProvider>().loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final opd = context.watch<OpdProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctors'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Doctor',
            onPressed: () => _showDoctorDialog(context),
          ),
        ],
      ),
      body: opd.doctors.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.medical_services_outlined,
                      size: 64, color: context.textMutedColor),
                  const SizedBox(height: 12),
                  Text('No doctors added yet',
                      style: TextStyle(color: context.textMutedColor)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add First Doctor'),
                    onPressed: () => _showDoctorDialog(context),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: opd.doctors.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final d = opd.doctors[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                      child: const Icon(Icons.person, color: AppTheme.primary),
                    ),
                    title: Text('Dr. ${d.name}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${d.specialization}${d.qualifications.isNotEmpty ? "  •  ${d.qualifications}" : ""}',
                      style: TextStyle(color: context.textMutedColor),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '₹${d.consultationFee.toStringAsFixed(0)}',
                            style: const TextStyle(
                                color: AppTheme.success,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: d.isActive,
                          onChanged: (v) {
                            d.isActive = v;
                            final sync = context.read<SyncService>();
                            context
                                .read<OpdProvider>()
                                .saveDoctor(d, syncService: sync);
                          },
                          activeColor: AppTheme.success,
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () =>
                              _showDoctorDialog(context, doctor: d),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 18, color: AppTheme.danger),
                          onPressed: () => _confirmDelete(d),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _confirmDelete(Doctor d) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Doctor?'),
        content: Text('Are you sure you want to remove Dr. ${d.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final sync = context.read<SyncService>();
              context.read<OpdProvider>().deleteDoctor(d.id, syncService: sync);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDoctorDialog(BuildContext context, {Doctor? doctor}) {
    showDialog(
      context: context,
      builder: (ctx) => _DoctorDialog(doctor: doctor),
    );
  }
}

class _DoctorDialog extends StatefulWidget {
  final Doctor? doctor;
  const _DoctorDialog({this.doctor});

  @override
  State<_DoctorDialog> createState() => _DoctorDialogState();
}

class _DoctorDialogState extends State<_DoctorDialog> {
  final _nameCtrl = TextEditingController();
  final _specCtrl = TextEditingController();
  final _qualCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.doctor != null) {
      _nameCtrl.text = widget.doctor!.name;
      _specCtrl.text = widget.doctor!.specialization;
      _qualCtrl.text = widget.doctor!.qualifications;
      _phoneCtrl.text = widget.doctor!.phone;
      _feeCtrl.text = widget.doctor!.consultationFee.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _specCtrl.dispose();
    _qualCtrl.dispose();
    _phoneCtrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.doctor != null ? 'Edit Doctor' : 'Add Doctor'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Full Name *', isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _specCtrl,
              decoration: const InputDecoration(
                  labelText: 'Specialization',
                  isDense: true,
                  hintText: 'General / Ortho / Gynae...'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _qualCtrl,
              decoration: const InputDecoration(
                  labelText: 'Qualifications',
                  isDense: true,
                  hintText: 'MBBS, MD...'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _feeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Consultation Fee (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                  isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: 'Phone', isDense: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  void _save() {
    if (_nameCtrl.text.trim().isEmpty) return;
    final doctor = widget.doctor ?? Doctor(name: '', specialization: 'General');
    doctor.name = _nameCtrl.text.trim();
    doctor.specialization =
        _specCtrl.text.trim().isEmpty ? 'General' : _specCtrl.text.trim();
    doctor.qualifications = _qualCtrl.text.trim();
    doctor.consultationFee = double.tryParse(_feeCtrl.text) ?? 0;
    doctor.phone = _phoneCtrl.text.trim();
    final syncService = context.read<SyncService>();
    context.read<OpdProvider>().saveDoctor(doctor, syncService: syncService);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(widget.doctor != null
          ? 'Doctor updated'
          : 'Dr. ${doctor.name} added'),
      backgroundColor: AppTheme.success,
    ));
  }
}
