import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/models/doctor.dart';
import '../../../shared/providers/opd_provider.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/services/sync_service.dart';
import '../../../theme/app_theme.dart';
import '../../../shared/widgets/app_empty_state.dart';

class DoctorListAndroid extends StatefulWidget {
  const DoctorListAndroid({super.key});

  @override
  State<DoctorListAndroid> createState() => _DoctorListAndroidState();
}

class _DoctorListAndroidState extends State<DoctorListAndroid> {
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
    final auth = context.watch<AuthProvider>();
    final canManage = auth.canManageDoctors;

    if (!canManage && opd.doctors.isEmpty) {
       // Optional: show empty state or access denied if no doctors and no permission
    }

    return Scaffold(
      backgroundColor: context.surfaceColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: const Text('Doctors'),
            pinned: true,
            floating: true,
            forceElevated: innerBoxIsScrolled,
            elevation: innerBoxIsScrolled ? 4 : 0,
            actions: [
              if (canManage)
                IconButton(
                  icon: const Icon(Icons.person_add),
                  tooltip: 'Add Doctor',
                  onPressed: () => _showDoctorDialog(context),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ],
        body: opd.doctors.isEmpty
            ? AppEmptyState(
                icon: Icons.medical_services_outlined,
                title: 'No doctors added yet',
                ctaLabel: canManage ? 'Add First Doctor' : null,
                ctaIcon: canManage ? Icons.add : null,
                onCtaTap: canManage ? () => _showDoctorDialog(context) : null,
              )
            : ListView.builder(
                padding: const EdgeInsets.all(20).copyWith(bottom: 100),
                itemCount: opd.doctors.length,
                itemBuilder: (ctx, i) {
                  final d = opd.doctors[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
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
                      border: Border.all(
                          color: context.borderColor.withValues(alpha: 0.5)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: Text(
                                    d.name.isNotEmpty
                                        ? d.name[0].toUpperCase()
                                        : 'D',
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
                                      'Dr. ${d.name}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${d.specialization}${d.qualifications.isNotEmpty ? "  •  ${d.qualifications}" : ""}',
                                      style: TextStyle(
                                          color: context.textMutedColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.success.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '₹${d.consultationFee.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                      color: AppTheme.success,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.only(top: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                    color: context.borderColor
                                        .withValues(alpha: 0.3)),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Switch(
                                      value: d.isActive,
                                      onChanged: !canManage ? null : (v) {
                                        d.isActive = v;
                                        final sync =
                                            context.read<SyncService>();
                                        context
                                            .read<OpdProvider>()
                                            .saveDoctor(d, syncService: sync);
                                      },
                                      activeThumbColor: AppTheme.success,
                                      activeTrackColor: AppTheme.success
                                          .withValues(alpha: 0.3),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      d.isActive ? 'Active' : 'Inactive',
                                      style: TextStyle(
                                          color: d.isActive
                                              ? AppTheme.success
                                              : context.textMutedColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                                if (canManage)
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_rounded,
                                            size: 20),
                                        color: AppTheme.indigo,
                                        onPressed: () =>
                                            _showDoctorDialog(context, doctor: d),
                                        tooltip: 'Edit Doctor',
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 20),
                                        color: AppTheme.danger,
                                        onPressed: () => _confirmDelete(d),
                                        tooltip: 'Delete Doctor',
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _showDoctorDialog(context),
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.person_add, color: Colors.white),
              label: const Text('Add Doctor',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            )
          : null,
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
