import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/models/doctor.dart';
import '../../../shared/providers/opd_provider.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/services/sync_service.dart';
import '../../../theme/app_theme.dart';
import '../../../shared/widgets/app_kpi_card.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_status_badge.dart';

class DoctorListWindows extends StatefulWidget {
  final bool isEmbedded;
  const DoctorListWindows({super.key, this.isEmbedded = false});

  @override
  State<DoctorListWindows> createState() => _DoctorListWindowsState();
}

class _DoctorListWindowsState extends State<DoctorListWindows> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _filter = 'all';
  bool _isGridView = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OpdProvider>().loadAll();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opd = context.watch<OpdProvider>();
    final auth = context.watch<AuthProvider>();
    final canManage = auth.canManageDoctors;
    final allDoctors = opd.doctors;

    final filteredDoctors = allDoctors.where((d) {
      final matchesSearch = _searchQuery.isEmpty ||
          d.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          d.specialization.toLowerCase().contains(_searchQuery.toLowerCase());

      switch (_filter) {
        case 'active':
          return matchesSearch && d.isActive;
        case 'inactive':
          return matchesSearch && !d.isActive;
        default:
          return matchesSearch;
      }
    }).toList();

    final activeCount = allDoctors.where((d) => d.isActive).length;
    final inactiveCount = allDoctors.where((d) => !d.isActive).length;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isEmbedded) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   const Text('Clinician Directory', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                   Text('Manage records for ${allDoctors.length} registered healthcare providers', style: TextStyle(color: context.textMutedColor)),
                ],
              ),
              if (canManage)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.person_add_rounded, size: 18),
                  label: const Text('Add Doctor'),
                  onPressed: () => _showDoctorDialog(context),
                ),
            ],
          ),
          const SizedBox(height: 32),
        ],
        _buildKpiSection(allDoctors.length, activeCount, inactiveCount),
        const SizedBox(height: 24),
        _buildFilterSearchCard(context),
        const SizedBox(height: 24),
        _buildDataTable(context, filteredDoctors, canManage),
      ],
    );

    if (widget.isEmbedded) {
      return Padding(
        padding: EdgeInsets.zero,
        child: content,
      );
    }

    return Scaffold(
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: content,
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _showDoctorDialog(context),
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Add Doctor'),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Doctors',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text('Clinic consultants',
                  style:
                      TextStyle(fontSize: 12, color: context.textMutedColor)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiSection(int total, int active, int inactive) {
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
                label: 'Total Doctors',
                value: '$total',
                icon: Icons.groups_rounded,
                color: AppTheme.primary,
                width: cardWidth,
              ),
              AppKpiCard(
                label: 'Active',
                value: '$active',
                icon: Icons.check_circle_rounded,
                color: AppTheme.success,
                width: cardWidth,
              ),
              AppKpiCard(
                label: 'Inactive',
                value: '$inactive',
                icon: Icons.cancel_rounded,
                color: Colors.grey,
                width: cardWidth,
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildFilterSearchCard(BuildContext context) {
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
                    label: 'All',
                    icon: Icons.groups_rounded,
                    isSelected: _filter == 'all',
                    onTap: () => setState(() => _filter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  AppFilterChip(
                    label: 'Active',
                    icon: Icons.check_circle_rounded,
                    isSelected: _filter == 'active',
                    onTap: () => setState(() => _filter = 'active'),
                    activeColor: AppTheme.success,
                  ),
                  const SizedBox(width: 8),
                  AppFilterChip(
                    label: 'Inactive',
                    icon: Icons.cancel_rounded,
                    isSelected: _filter == 'inactive',
                    onTap: () => setState(() => _filter = 'inactive'),
                    activeColor: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToggleBtn(
                  icon: Icons.view_list_rounded,
                  isSelected: !_isGridView,
                  onTap: () => setState(() => _isGridView = false),
                ),
                _ToggleBtn(
                  icon: Icons.grid_view_rounded,
                  isSelected: _isGridView,
                  onTap: () => setState(() => _isGridView = true),
                ),
              ],
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
                hintText: 'Search doctors...',
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

  Widget _buildDataTable(BuildContext context, List<Doctor> doctors, bool canManage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 4),
          child: Text(
            'FOUND ${doctors.length} DOCTORS',
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
          child: _isGridView
              ? _DoctorGrid(
                  doctors: doctors,
                  onEdit: !canManage ? null : (d) => _showDoctorDialog(context, doctor: d),
                  onDelete: !canManage ? null : (d) => _confirmDelete(context, d),
                )
              : Column(
                  children: [
                    _buildTableHeader(),
                    Divider(height: 1, color: context.borderColor),
                    if (doctors.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(40),
                        child: AppEmptyState(
                          icon: Icons.medical_services_outlined,
                          title: 'No doctors found',
                          subtitle: 'Try adjusting your search or filters',
                          iconColor: AppTheme.primary,
                        ),
                      )
                    else
                      ...doctors.map((d) => _DoctorTableRow(
                            doctor: d,
                            canManage: canManage,
                            onEdit: () => _showDoctorDialog(context, doctor: d),
                            onDelete: () => _confirmDelete(context, d),
                          )),
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
          Expanded(
              flex: 3, child: Text('DOCTOR', style: _headerStyle(context))),
          const SizedBox(width: 12),
          SizedBox(
              width: 150,
              child: Text('SPECIALIZATION', style: _headerStyle(context))),
          const SizedBox(width: 12),
          SizedBox(
              width: 100,
              child: Center(child: Text('FEE', style: _headerStyle(context)))),
          const SizedBox(width: 12),
          SizedBox(
              width: 130, child: Text('PHONE', style: _headerStyle(context))),
          const SizedBox(width: 12),
          SizedBox(
              width: 130,
              child:
                  Center(child: Text('STATUS', style: _headerStyle(context)))),
          const SizedBox(width: 12),
          SizedBox(
              width: 100,
              child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('ACTIONS', style: _headerStyle(context)))),
        ],
      ),
    );
  }

  TextStyle _headerStyle(BuildContext context) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: context.textMutedColor);

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

// ── View Toggle ─────────────────────────────────────────────────────────────

class _ToggleBtn extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleBtn({
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppTheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 20,
            color: isSelected ? Colors.white : context.textMutedColor,
          ),
        ),
      ),
    );
  }
}

// ── Doctor Table Row ────────────────────────────────────────────────────────

class _DoctorTableRow extends StatefulWidget {
  final Doctor doctor;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DoctorTableRow({
    required this.doctor,
    this.canManage = true,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_DoctorTableRow> createState() => _DoctorTableRowState();
}

class _DoctorTableRowState extends State<_DoctorTableRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isInactive = !widget.doctor.isActive;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _isHovered
              ? AppTheme.primary.withValues(alpha: 0.1)
              : (isInactive
                  ? context.borderColor.withValues(alpha: 0.2)
                  : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
          border: _isHovered
              ? Border.all(color: AppTheme.primary.withValues(alpha: 0.2))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  _DoctorAvatar(
                    name: widget.doctor.name,
                    isActive: widget.doctor.isActive,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Dr. ${widget.doctor.name}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: isInactive
                                        ? context.textMutedColor
                                        : context.textColor)),
                            if (isInactive) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('INACTIVE',
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: context.textMutedColor,
                                        letterSpacing: 0.5)),
                              ),
                            ],
                          ],
                        ),
                        if (widget.doctor.qualifications.isNotEmpty)
                          Text(widget.doctor.qualifications,
                              style: TextStyle(
                                  fontSize: 11, color: context.textMutedColor)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 150,
              child: _SpecializationBadge(
                  specialization: widget.doctor.specialization),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: Text(
                '₹${widget.doctor.consultationFee.toStringAsFixed(0)}',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isInactive ? Colors.grey : AppTheme.success),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 130,
              child: Text(
                widget.doctor.phone.isNotEmpty ? widget.doctor.phone : '--',
                style: TextStyle(
                    fontSize: 13,
                    color: context.textMutedColor,
                    fontFamily:
                        widget.doctor.phone.isNotEmpty ? 'monospace' : null),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 130,
              child: _StatusToggle(doctor: widget.doctor, enabled: widget.canManage),
            ),
            const SizedBox(width: 12),
            if (widget.canManage)
              SizedBox(
                width: 100,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _IconActionBtn(
                      icon: Icons.edit_rounded,
                      color: AppTheme.warning,
                      onTap: widget.onEdit,
                      tooltip: 'Edit',
                    ),
                    const SizedBox(width: 4),
                    _IconActionBtn(
                      icon: Icons.delete_rounded,
                      color: AppTheme.danger,
                      onTap: widget.onDelete,
                      tooltip: 'Delete',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Doctor Avatar ───────────────────────────────────────────────────────────

class _DoctorAvatar extends StatelessWidget {
  final String name;
  final bool isActive;

  const _DoctorAvatar({required this.name, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: isActive
          ? AppTheme.primary.withValues(alpha: 0.1)
          : context.textMutedColor.withValues(alpha: 0.1),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'D',
        style: TextStyle(
          color: isActive ? AppTheme.primary : context.textMutedColor,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ── Specialization Badge ────────────────────────────────────────────────────

class _SpecializationBadge extends StatelessWidget {
  final String specialization;

  const _SpecializationBadge({required this.specialization});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryLight.withValues(alpha: 0.1),
            AppTheme.primaryLight.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        specialization,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryLight),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ── Status Toggle ───────────────────────────────────────────────────────────

class _StatusToggle extends StatelessWidget {
  final Doctor doctor;

  final bool enabled;

  const _StatusToggle({required this.doctor, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _AnimatedSwitch(
          value: doctor.isActive,
          onChanged: !enabled ? (_) {} : (v) {
            doctor.isActive = v;
            final sync = context.read<SyncService>();
            context.read<OpdProvider>().saveDoctor(doctor, syncService: sync);
          },
        ),
        const SizedBox(width: 8),
        Text(
          doctor.isActive ? 'Active' : 'Inactive',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color:
                  doctor.isActive ? AppTheme.success : context.textMutedColor),
        ),
      ],
    );
  }
}

// ── Animated Switch ─────────────────────────────────────────────────────────

class _AnimatedSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _AnimatedSwitch({required this.value, required this.onChanged});

  @override
  State<_AnimatedSwitch> createState() => _AnimatedSwitchState();
}

class _AnimatedSwitchState extends State<_AnimatedSwitch>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.value) _controller.forward();
  }

  @override
  void didUpdateWidget(_AnimatedSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => widget.onChanged(!widget.value),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            width: 44,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Color.lerp(
                  context.borderColor, AppTheme.primary, _animation.value),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 2 + (18 * _animation.value),
                  top: 2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Icon Action Button ──────────────────────────────────────────────────────

class _IconActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _IconActionBtn({
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

// ── Doctor Grid ─────────────────────────────────────────────────────────────

class _DoctorGrid extends StatelessWidget {
  final List<Doctor> doctors;
  final Function(Doctor)? onEdit;
  final Function(Doctor)? onDelete;

  const _DoctorGrid({
    required this.doctors,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (doctors.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: AppEmptyState(
          icon: Icons.medical_services_outlined,
          title: 'No doctors found',
          subtitle: 'Try adjusting your search or filters',
          iconColor: AppTheme.primary,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1200
            ? 4
            : (constraints.maxWidth > 800 ? 3 : 2);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.85,
          ),
          itemCount: doctors.length,
          itemBuilder: (context, index) => _DoctorCard(
            doctor: doctors[index],
            onEdit: () => onEdit?.call(doctors[index]),
            onDelete: () => onDelete?.call(doctors[index]),
          ),
        );
      },
    );
  }
}

// ── Doctor Card ─────────────────────────────────────────────────────────────

class _DoctorCard extends StatefulWidget {
  final Doctor doctor;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _DoctorCard({
    required this.doctor,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<_DoctorCard> createState() => _DoctorCardState();
}

class _DoctorCardState extends State<_DoctorCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isInactive = !widget.doctor.isActive;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: _isHovered
            ? Matrix4.translationValues(0.0, -4.0, 0.0)
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isHovered
                ? AppTheme.primary.withValues(alpha: 0.3)
                : context.borderColor.withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered
                  ? AppTheme.primary.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: _isHovered ? 20 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _DoctorAvatar(
                    name: widget.doctor.name,
                    isActive: widget.doctor.isActive,
                  ),
                  const SizedBox(height: 12),
                  Text('Dr. ${widget.doctor.name}',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: isInactive
                              ? context.textMutedColor
                              : context.textColor),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  _SpecializationBadge(
                      specialization: widget.doctor.specialization),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '₹${widget.doctor.consultationFee.toStringAsFixed(0)}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: isInactive
                                ? context.textMutedColor
                                : AppTheme.success),
                      ),
                      Text('/visit',
                          style: TextStyle(
                              fontSize: 12, color: context.textMutedColor)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (widget.onEdit != null || widget.onDelete != null)
                    Row(
                      children: [
                        if (widget.onEdit != null)
                          Expanded(
                            child: _CardActionBtn(
                              icon: Icons.edit_rounded,
                              color: AppTheme.warning,
                              onTap: widget.onEdit!,
                            ),
                          ),
                        if (widget.onEdit != null && widget.onDelete != null)
                          const SizedBox(width: 8),
                        if (widget.onDelete != null)
                          Expanded(
                            child: _CardActionBtn(
                              icon: Icons.delete_rounded,
                              color: AppTheme.danger,
                              onTap: widget.onDelete!,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            if (!isInactive)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppTheme.success,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.success.withValues(alpha: 0.4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Card Action Button ──────────────────────────────────────────────────────

class _CardActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CardActionBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Icon(icon, size: 18, color: color),
        ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withValues(alpha: 0.15),
                        AppTheme.primaryLight.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
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
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A2332)),
                      ),
                      Text(
                        isEditing
                            ? 'Update consultant details'
                            : 'Register a new consultant',
                        style: TextStyle(
                            fontSize: 13, color: context.textMutedColor),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon:
                      Icon(Icons.close_rounded, color: context.textMutedColor),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _ModernTextField(
                    controller: _nameCtrl,
                    label: 'Full Name',
                    prefix: Icons.person_outline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ModernTextField(
                    controller: _feeCtrl,
                    label: 'Fee',
                    prefix: Icons.currency_rupee,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ModernTextField(
                    controller: _specCtrl,
                    label: 'Specialization',
                    prefix: Icons.category_outlined,
                    hint: 'General / Ortho...',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ModernTextField(
                    controller: _phoneCtrl,
                    label: 'Phone',
                    prefix: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ModernTextField(
              controller: _qualCtrl,
              label: 'Qualifications',
              prefix: Icons.school_outlined,
              hint: 'MBBS, MD...',
            ),
            const SizedBox(height: 28),
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
                  icon: Icon(isEditing ? Icons.save_rounded : Icons.add_rounded,
                      size: 18),
                  label: Text(isEditing ? 'Save Changes' : 'Add Doctor'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
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

// ── Modern Text Field ───────────────────────────────────────────────────────

class _ModernTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData prefix;
  final String? hint;
  final TextInputType? keyboardType;

  const _ModernTextField({
    required this.controller,
    required this.label,
    required this.prefix,
    this.hint,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(prefix, size: 20, color: AppTheme.primaryLight),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
