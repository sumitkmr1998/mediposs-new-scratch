import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/attendance_provider.dart';
import '../../shared/models/app_user.dart';
import '../../theme/app_theme.dart';
import '../../widgets/android/user_dialog_android.dart';

class UserManagementAndroid extends StatefulWidget {
  const UserManagementAndroid({super.key});

  @override
  State<UserManagementAndroid> createState() => _UserManagementAndroidState();
}

class _UserManagementAndroidState extends State<UserManagementAndroid> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta, 1);
    });
  }

  void _showStatusDialog(AppUser user, DateTime dayDate, String currentStatus) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Mark Attendance for ${user.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Date: ${DateFormat('EEEE, d MMMM yyyy').format(dayDate)}', 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.check_circle_rounded, color: AppTheme.success),
              title: const Text('Mark Present'),
              subtitle: const Text('Logs attendance as Present for this day'),
              onTap: () {
                context.read<AttendanceProvider>().markStatus(user, dayDate, 'present');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel_rounded, color: AppTheme.danger),
              title: const Text('Mark Absent'),
              subtitle: const Text('Logs attendance as Absent for this day'),
              onTap: () {
                context.read<AttendanceProvider>().markStatus(user, dayDate, 'absent');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded, color: Colors.grey),
              title: const Text('Reset / Clear Log'),
              subtitle: const Text('Removes manual entries and restores automatic status'),
              onTap: () {
                context.read<AttendanceProvider>().markStatus(user, dayDate, 'clear');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canManage = auth.canManageUsers;
    final users = auth.getAllUsers();

    if (!canManage) {
      return Scaffold(
        backgroundColor: context.surfaceColor,
        appBar: AppBar(title: const Text('Staff Management')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_person_rounded, size: 64, color: AppTheme.danger),
              const SizedBox(height: 16),
              const Text('Access Denied', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('You do not have permission to manage staff.', style: TextStyle(color: context.textMutedColor)),
            ],
          ),
        ),
      );
    }

    final registryContent = users.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline, size: 72, color: context.textMutedColor),
                const SizedBox(height: 16),
                Text('No staff found',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: context.textMutedColor, fontWeight: FontWeight.w600)),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(20).copyWith(bottom: 100),
            itemCount: users.length,
            itemBuilder: (ctx, i) => _buildUserCard(context, users[i], auth),
          );

    // Compute month details
    final year = _selectedMonth.year;
    final month = _selectedMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final staffUsers = users.where((u) => u.role.toLowerCase() != 'admin').toList();
    final records = context.watch<AttendanceProvider>().getMonthRecords(_selectedMonth);

    final columns = <DataColumn>[
      const DataColumn(label: Text('Staff Member', style: TextStyle(fontWeight: FontWeight.bold))),
      for (int day = 1; day <= daysInMonth; day++)
        DataColumn(
          label: Center(
            child: Text(
              '$day',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
        ),
      const DataColumn(label: Text('Present', style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold))),
      const DataColumn(label: Text('Absent', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold))),
    ];

    final rows = staffUsers.map((user) {
      int presentCount = 0;
      int absentCount = 0;

      final cells = <DataCell>[
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 6),
              Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
        ),
      ];

      for (int day = 1; day <= daysInMonth; day++) {
        final dayDate = DateTime(year, month, day);
        final dateStr = DateFormat('yyyy-MM-dd').format(dayDate);
        final isFuture = dayDate.isAfter(DateTime.now());
        final record = records.where((r) => r.userId == user.id && r.date == dateStr).firstOrNull;

        String status = '';
        Widget cellChild;

        if (isFuture) {
          status = 'future';
          cellChild = const Text('-', style: TextStyle(color: Colors.grey));
        } else {
          if (record != null) {
            status = record.status;
            if (status == 'present') {
              presentCount++;
              cellChild = Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle),
                child: const Text('P', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
              );
            } else {
              absentCount++;
              cellChild = Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: AppTheme.danger, shape: BoxShape.circle),
                child: const Text('A', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
              );
            }
          } else {
            absentCount++;
            cellChild = Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: AppTheme.danger.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: const Text('A', style: TextStyle(color: AppTheme.danger, fontSize: 8, fontWeight: FontWeight.bold)),
            );
          }
        }

        cells.add(
          DataCell(
            Center(child: cellChild),
            onTap: isFuture ? null : () => _showStatusDialog(user, dayDate, status),
          ),
        );
      }

      cells.add(DataCell(Center(child: Text('$presentCount', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 12)))));
      cells.add(DataCell(Center(child: Text('$absentCount', style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 12)))));

      return DataRow(cells: cells);
    }).toList();

    final attendanceContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => _changeMonth(-1),
                  ),
                  Text(
                    DateFormat('MMMM yyyy').format(_selectedMonth),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: () => _changeMonth(1),
                  ),
                ],
              ),
              Text(
                'Staff: ${staffUsers.length}',
                style: TextStyle(color: context.textMutedColor, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: staffUsers.isEmpty
              ? const Center(
                  child: Text('No staff members registered for attendance tracking.'),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: context.borderColor,
                          ),
                          child: DataTable(
                            columnSpacing: 12,
                            horizontalMargin: 8,
                            columns: columns,
                            rows: rows,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: context.surfaceColor,
        appBar: AppBar(
          title: const Text('Staff Management'),
          bottom: const TabBar(
            labelColor: AppTheme.primary,
            indicatorColor: AppTheme.primary,
            tabs: [
              Tab(icon: Icon(Icons.people_alt_rounded), text: 'Registry'),
              Tab(icon: Icon(Icons.calendar_month_rounded), text: 'Attendance'),
            ],
          ),
          actions: [
            if (canManage)
              IconButton(
                icon: const Icon(Icons.person_add),
                tooltip: 'Add New Staff',
                onPressed: () {
                  AndroidUserDialog.showUserSheet(context);
                },
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: TabBarView(
          children: [
            registryContent,
            attendanceContent,
          ],
        ),
        floatingActionButton: canManage 
            ? FloatingActionButton(
                onPressed: () {
                  AndroidUserDialog.showUserSheet(context);
                },
                backgroundColor: AppTheme.primary,
                child: const Icon(Icons.person_add, color: Colors.white),
              )
            : null,
      ),
    );
  }

  Widget _buildUserCard(BuildContext context, AppUser user, AuthProvider auth) {
    final isAdmin = user.role.toLowerCase() == 'admin';
    final statusColor = user.isActive ? AppTheme.success : AppTheme.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: context.borderColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Status Strip
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 4,
              child: Container(color: statusColor),
            ),
            
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  child: Row(
                    children: [
                      // Avatar with Gradient
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primary.withValues(alpha: 0.2),
                              AppTheme.primary.withValues(alpha: 0.05)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                color: AppTheme.primaryLight,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    letterSpacing: -0.5)),
                            const SizedBox(height: 6),
                            _Badge(
                              label: user.role.toUpperCase(),
                              color: isAdmin ? AppTheme.primaryLight : context.textMutedColor,
                              isGlass: true,
                            ),
                          ],
                        ),
                      ),
                      _StatusBadge(isActive: user.isActive),
                    ],
                  ),
                ),

                const Divider(indent: 20, endIndent: 20, height: 1),

                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MODULE ACCESS',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: context.textMutedColor.withValues(alpha: 0.6))),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _moduleIcon(Icons.shopping_cart_rounded, 'POS', user.canAccessPOS || isAdmin, context),
                          _moduleIcon(Icons.inventory_2_rounded, 'Stock', user.canEditInventory || isAdmin, context),
                          _moduleIcon(Icons.local_hospital_rounded, 'OPD', user.canAccessOPD || isAdmin, context),
                          _moduleIcon(Icons.analytics_rounded, 'Reports', (user.canViewDashboard || user.canViewOpdReports || user.canViewAnalytics || user.canViewSalesHistory) || isAdmin, context),
                          _moduleIcon(Icons.settings_rounded, 'Admin', user.canAccessSettings || isAdmin, context),
                        ],
                      ),
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: context.textMutedColor.withValues(alpha: 0.05),
                    border: Border(
                        top: BorderSide(
                            color: context.borderColor.withValues(alpha: 0.2))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // PIN Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.key_rounded, size: 12, color: context.textMutedColor),
                            const SizedBox(width: 6),
                            Text(user.pin,
                                style: TextStyle(
                                    color: context.textColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5)),
                          ],
                        ),
                      ),
                      
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                          foregroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        onPressed: () => AndroidUserDialog.showUserSheet(context, existingUser: user),
                        icon: const Icon(Icons.edit_note_rounded, size: 18),
                        label: const Text('MANAGE STAFF',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _moduleIcon(IconData icon, String label, bool active, BuildContext context) {
    final color = active ? AppTheme.primary : context.textMutedColor.withValues(alpha: 0.2);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: active ? AppTheme.primary.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? AppTheme.primary.withValues(alpha: 0.2) : Colors.transparent,
            ),
          ),
          child: Icon(icon, size: 22, color: color),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)),
      ],
    );
  }


}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final bool isGlass;

  const _Badge(
      {required this.label, required this.color, this.isGlass = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isGlass
            ? color.withValues(alpha: 0.08)
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.withValues(alpha: 0.9),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;
  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppTheme.success : AppTheme.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 4,
                    spreadRadius: 1),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isActive ? 'ACTIVE' : 'INACTIVE',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
