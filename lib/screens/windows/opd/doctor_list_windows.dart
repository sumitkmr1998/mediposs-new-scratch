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
    final allDoctors = opd.doctors;
    final activeCount = allDoctors.where((d) => d.isActive).length;
    final inactiveCount = allDoctors.where((d) => !d.isActive).length;

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
              child: const Icon(Icons.medical_services_rounded,
                  color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Doctors',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                Text('Clinic consultants',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7B8D))),
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
              final cols = constraints.maxWidth > 700
                  ? 3
                  : (constraints.maxWidth > 400 ? 2 : 1);
              const spacing = 12.0;
              final cardWidth =
                  (constraints.maxWidth - (cols - 1) * spacing) / cols;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  _StatCard(
                    label: 'Total Doctors',
                    value: '${allDoctors.length}',
                    icon: Icons.groups_rounded,
                    color: AppTheme.primary,
                    width: cardWidth,
                  ),
                  _StatCard(
                    label: 'Active',
                    value: '$activeCount',
                    icon: Icons.check_circle_rounded,
                    color: AppTheme.success,
                    width: cardWidth,
                  ),
                  _StatCard(
                    label: 'Inactive',
                    value: '$inactiveCount',
                    icon: Icons.pause_circle_rounded,
                    color: Colors.grey,
                    width: cardWidth,
                  ),
                ],
              );
            }),

            const SizedBox(height: 24),

            // Bento Table
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: AppTheme.lightBorder.withValues(alpha: 0.5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
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
                        const Expanded(
                          flex: 3,
                          child: Text('DOCTOR',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                  color: Color(0xFF6B7B8D))),
                        ),
                        const SizedBox(
                            width: 150,
                            child: Text('SPECIALIZATION',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                    color: Color(0xFF6B7B8D)))),
                        const SizedBox(
                            width: 100,
                            child: Text('FEE',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                    color: Color(0xFF6B7B8D)))),
                        const SizedBox(
                            width: 130,
                            child: Text('PHONE',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                    color: Color(0xFF6B7B8D)))),
                        const SizedBox(
                            width: 180,
                            child: Text('STATUS',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                    color: Color(0xFF6B7B8D)))),
                        const SizedBox(
                            width: 100,
                            child: Align(
                                alignment: Alignment.centerRight,
                                child: Text('ACTIONS',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.5,
                                        color: Color(0xFF6B7B8D))))),
                      ],
                    ),
                  ),

                  Divider(height: 1, color: context.borderColor),

                  const SizedBox(height: 4),

                  // Doctor Rows
                  if (allDoctors.isEmpty)
                    _EmptyState(onAdd: () => _showDoctorDialog(context))
                  else
                    ...allDoctors.map((d) => _DoctorRow(
                          doctor: d,
                          onEdit: () => _showDoctorDialog(context, doctor: d),
                          onDelete: () => _confirmDelete(context, d),
                        )),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showDoctorDialog(context),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Doctor'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  void _confirmDelete(BuildContext context, Doctor d) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.warning_rounded,
                  color: AppTheme.danger, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Delete Doctor?',
                style: TextStyle(color: AppTheme.danger)),
          ],
        ),
        content: Text(
            'Are you sure you want to remove Dr. ${d.name}? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text('Cancel', style: TextStyle(color: context.textMutedColor)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final sync = context.read<SyncService>();
              context.read<OpdProvider>().deleteDoctor(d.id, syncService: sync);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text('Dr. ${d.name} deleted'),
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

  void _showDoctorDialog(BuildContext context, {Doctor? doctor}) {
    showDialog(
      context: context,
      builder: (ctx) => _DoctorDialog(doctor: doctor),
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

// ── Doctor Row ─────────────────────────────────────────────────────────────

class _DoctorRow extends StatelessWidget {
  final Doctor doctor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DoctorRow({
    required this.doctor,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isInactive = !doctor.isActive;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: isInactive
            ? Colors.grey.withValues(alpha: 0.05)
            : AppTheme.primary.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          // Doctor info
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isInactive
                      ? Colors.grey.withValues(alpha: 0.15)
                      : AppTheme.primary.withValues(alpha: 0.1),
                  child: Text(
                    doctor.name.isNotEmpty ? doctor.name[0].toUpperCase() : 'D',
                    style: TextStyle(
                        color: isInactive ? Colors.grey : AppTheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Dr. ${doctor.name}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: isInactive
                                      ? Colors.grey
                                      : Colors.black87)),
                          if (isInactive) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('INACTIVE',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey,
                                      letterSpacing: 0.5)),
                            ),
                          ],
                        ],
                      ),
                      if (doctor.qualifications.isNotEmpty)
                        Text(doctor.qualifications,
                            style: TextStyle(
                                fontSize: 12,
                                color: context.textMutedColor,
                                fontWeight: FontWeight.w400)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Specialization
          SizedBox(
            width: 150,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF14A085).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                doctor.specialization,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF14A085)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Fee
          SizedBox(
            width: 100,
            child: Text(
              '₹${doctor.consultationFee.toStringAsFixed(0)}',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: isInactive ? Colors.grey : AppTheme.success),
            ),
          ),

          // Phone
          SizedBox(
            width: 130,
            child: Text(
              doctor.phone.isNotEmpty ? doctor.phone : '--',
              style: TextStyle(
                  fontSize: 13,
                  color: context.textMutedColor,
                  fontFamily: doctor.phone.isNotEmpty ? 'monospace' : null),
            ),
          ),

          // Status Toggle
          SizedBox(
            width: 180,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Switch(
                  value: doctor.isActive,
                  onChanged: (v) {
                    doctor.isActive = v;
                    final sync = context.read<SyncService>();
                    context
                        .read<OpdProvider>()
                        .saveDoctor(doctor, syncService: sync);
                  },
                  activeColor: Colors.white,
                  activeTrackColor: AppTheme.primary,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: const Color(0xFFCBD5E1),
                ),
                const SizedBox(width: 4),
                Text(
                  doctor.isActive ? 'Active' : 'Inactive',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: doctor.isActive ? AppTheme.success : Colors.grey),
                ),
              ],
            ),
          ),

          // Actions
          SizedBox(
            width: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ActionBtn(
                  icon: Icons.edit_rounded,
                  color: AppTheme.warning,
                  onTap: onEdit,
                  tooltip: 'Edit',
                ),
                const SizedBox(width: 6),
                _ActionBtn(
                  icon: Icons.delete_rounded,
                  color: AppTheme.danger,
                  onTap: onDelete,
                  tooltip: 'Delete',
                ),
              ],
            ),
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
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}

// ── Empty State ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

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
            child: Icon(Icons.medical_services_outlined,
                size: 40, color: AppTheme.primary.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 16),
          const Text('No doctors added yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A2332))),
          const SizedBox(height: 6),
          Text('Add your first doctor to get started',
              style: TextStyle(fontSize: 13, color: context.textMutedColor)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Doctor'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Doctor Dialog ───────────────────────────────────────────────────────────

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
    final isEditing = widget.doctor != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.medical_services_rounded,
                      color: AppTheme.primary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEditing ? 'Edit Doctor' : 'Add Doctor',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A2332)),
                      ),
                      Text(
                        isEditing
                            ? 'Update consultant details'
                            : 'Register a new consultant',
                        style: TextStyle(
                            fontSize: 12, color: context.textMutedColor),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: context.textMutedColor),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Form fields
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'Full Name *',
                prefixIcon: const Icon(Icons.person_outline, size: 20),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),

            const SizedBox(height: 14),

            TextField(
              controller: _specCtrl,
              decoration: InputDecoration(
                labelText: 'Specialization',
                prefixIcon: const Icon(Icons.category_outlined, size: 20),
                hintText: 'General / Ortho / Gynae...',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),

            const SizedBox(height: 14),

            TextField(
              controller: _qualCtrl,
              decoration: InputDecoration(
                labelText: 'Qualifications',
                prefixIcon: const Icon(Icons.school_outlined, size: 20),
                hintText: 'MBBS, MD...',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _feeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Consultation Fee',
                      prefixIcon: const Icon(Icons.currency_rupee, size: 20),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel',
                      style: TextStyle(color: context.textMutedColor)),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _save,
                  icon: Icon(isEditing ? Icons.save : Icons.add, size: 18),
                  label: Text(isEditing ? 'Save Changes' : 'Add Doctor'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter doctor name'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(widget.doctor != null
                ? 'Dr. ${doctor.name} updated'
                : 'Dr. ${doctor.name} added'),
          ],
        ),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
