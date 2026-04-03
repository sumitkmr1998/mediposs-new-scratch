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
  final _searchCtrl = TextEditingController();
  bool _isGridView = false;
  String _filter = 'all';

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
    final allDoctors = opd.doctors;

    final filteredDoctors = allDoctors.where((d) {
      final matchesSearch = _searchCtrl.text.isEmpty ||
          d.name.toLowerCase().contains(_searchCtrl.text.toLowerCase()) ||
          d.specialization
              .toLowerCase()
              .contains(_searchCtrl.text.toLowerCase());

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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Doctors',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                Text('Clinic consultants',
                    style:
                        TextStyle(fontSize: 12, color: context.textMutedColor)),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            width: 280,
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search doctors...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: context.surfaceColor,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _StatsRow(
                    allCount: allDoctors.length,
                    activeCount: activeCount,
                    inactiveCount: inactiveCount,
                    filter: _filter,
                    onFilterChanged: (f) => setState(() => _filter = f),
                  ),
                ),
                const SizedBox(width: 16),
                _ViewToggle(
                  isGrid: _isGridView,
                  onToggle: () => setState(() => _isGridView = !_isGridView),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_isGridView)
              _DoctorGrid(
                doctors: filteredDoctors,
                onEdit: (d) => _showDoctorDialog(context, doctor: d),
                onDelete: (d) => _confirmDelete(context, d),
              )
            else
              _DoctorTable(
                doctors: filteredDoctors,
                onEdit: (d) => _showDoctorDialog(context, doctor: d),
                onDelete: (d) => _confirmDelete(context, d),
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

class _StatsRow extends StatelessWidget {
  final int allCount;
  final int activeCount;
  final int inactiveCount;
  final String filter;
  final ValueChanged<String> onFilterChanged;

  const _StatsRow({
    required this.allCount,
    required this.activeCount,
    required this.inactiveCount,
    required this.filter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FilterChip(
          label: 'All',
          count: allCount,
          isSelected: filter == 'all',
          color: AppTheme.primary,
          onTap: () => onFilterChanged('all'),
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: 'Active',
          count: activeCount,
          isSelected: filter == 'active',
          color: AppTheme.success,
          onTap: () => onFilterChanged('active'),
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: 'Inactive',
          count: inactiveCount,
          isSelected: filter == 'inactive',
          color: Colors.grey,
          onTap: () => onFilterChanged('inactive'),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? color : context.borderColor,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? color : context.textMutedColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? color : context.borderColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? Colors.white : context.textMutedColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  final bool isGrid;
  final VoidCallback onToggle;

  const _ViewToggle({required this.isGrid, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleBtn(
            icon: Icons.view_list_rounded,
            isSelected: !isGrid,
            onTap: onToggle,
          ),
          _ToggleBtn(
            icon: Icons.grid_view_rounded,
            isSelected: isGrid,
            onTap: onToggle,
          ),
        ],
      ),
    );
  }
}

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

class _DoctorTable extends StatelessWidget {
  final List<Doctor> doctors;
  final Function(Doctor) onEdit;
  final Function(Doctor) onDelete;

  const _DoctorTable({
    required this.doctors,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.borderColor.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(
              children: [
                const Expanded(
                  flex: 3,
                  child: Text('DOCTOR',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: AppTheme.primaryLight)),
                ),
                const SizedBox(
                    width: 150,
                    child: Text('SPECIALIZATION',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: AppTheme.primaryLight))),
                const SizedBox(
                    width: 100,
                    child: Text('FEE',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: AppTheme.primaryLight))),
                const SizedBox(
                    width: 130,
                    child: Text('PHONE',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: AppTheme.primaryLight))),
                const SizedBox(
                    width: 130,
                    child: Text('STATUS',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: AppTheme.primaryLight))),
                const SizedBox(
                    width: 100,
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
          if (doctors.isEmpty)
            _EmptyState(onAdd: () {})
          else
            ...doctors.map((d) => _DoctorTableRow(
                  doctor: d,
                  onEdit: () => onEdit(d),
                  onDelete: () => onDelete(d),
                )),
        ],
      ),
    );
  }
}

class _DoctorTableRow extends StatefulWidget {
  final Doctor doctor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DoctorTableRow({
    required this.doctor,
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
            SizedBox(
              width: 150,
              child: _SpecializationBadge(
                  specialization: widget.doctor.specialization),
            ),
            const SizedBox(width: 16),
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
            SizedBox(
              width: 130,
              child: _StatusToggle(doctor: widget.doctor),
            ),
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

class _DoctorAvatar extends StatelessWidget {
  final String name;
  final bool isActive;

  const _DoctorAvatar({required this.name, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final colors = isActive
        ? [AppTheme.primary, AppTheme.primaryLight]
        : [
            context.textMutedColor,
            context.textMutedColor.withValues(alpha: 0.7)
          ];

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'D',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

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

class _StatusToggle extends StatelessWidget {
  final Doctor doctor;

  const _StatusToggle({required this.doctor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _AnimatedSwitch(
          value: doctor.isActive,
          onChanged: (v) {
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

class _AnimatedKey extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _AnimatedKey({required this.value, required this.onChanged});

  @override
  State<_AnimatedKey> createState() => _AnimatedKeyState();
}

class _AnimatedKeyState extends State<_AnimatedKey>
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
  void didUpdateWidget(_AnimatedKey oldWidget) {
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

class _AnimatedSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _AnimatedSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _AnimatedKey(value: value, onChanged: onChanged);
  }
}

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

class _DoctorGrid extends StatelessWidget {
  final List<Doctor> doctors;
  final Function(Doctor) onEdit;
  final Function(Doctor) onDelete;

  const _DoctorGrid({
    required this.doctors,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (doctors.isEmpty) {
      return _EmptyState(onAdd: () {});
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1200
            ? 4
            : (constraints.maxWidth > 800 ? 3 : 2);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.85,
          ),
          itemCount: doctors.length,
          itemBuilder: (context, index) => _DoctorCard(
            doctor: doctors[index],
            onEdit: () => onEdit(doctors[index]),
            onDelete: () => onDelete(doctors[index]),
          ),
        );
      },
    );
  }
}

class _DoctorCard extends StatefulWidget {
  final Doctor doctor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DoctorCard({
    required this.doctor,
    required this.onEdit,
    required this.onDelete,
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
            ? (Matrix4.identity()..translate(0, -4, 0))
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isHovered
                ? AppTheme.primary.withValues(alpha: 0.3)
                : AppTheme.lightBorder.withValues(alpha: 0.3),
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
                          color: isInactive ? Colors.grey : Colors.black87),
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
                            color: isInactive ? Colors.grey : AppTheme.success),
                      ),
                      Text('/visit',
                          style: TextStyle(
                              fontSize: 12, color: context.textMutedColor)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _CardActionBtn(
                          icon: Icons.edit_rounded,
                          color: AppTheme.warning,
                          onTap: widget.onEdit,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CardActionBtn(
                          icon: Icons.delete_rounded,
                          color: AppTheme.danger,
                          onTap: widget.onDelete,
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
          const Text('No doctors found',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A2332))),
          const SizedBox(height: 6),
          Text('Try adjusting your search or filters',
              style: TextStyle(fontSize: 13, color: context.textMutedColor)),
        ],
      ),
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
    final isEditing = widget.doctor != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(28),
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
