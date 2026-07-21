import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/attendance_provider.dart';
import '../../shared/models/app_user.dart';
import '../../theme/app_theme.dart';
import '../../widgets/user_form_dialog.dart';

class UserManagementWindows extends StatefulWidget {
  final bool isEmbedded;
  const UserManagementWindows({super.key, this.isEmbedded = false});

  @override
  State<UserManagementWindows> createState() => _UserManagementWindowsState();
}

class _UserManagementWindowsState extends State<UserManagementWindows> with SingleTickerProviderStateMixin {
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
        backgroundColor: context.bgColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_person_rounded, size: 64, color: AppTheme.danger),
              const SizedBox(height: 16),
              const Text('Access Denied', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('You do not have permission to manage staff profiles.', style: TextStyle(color: context.textMutedColor)),
            ],
          ),
        ),
      );
    }

    final registryContent = GridView.builder(
      padding: widget.isEmbedded ? EdgeInsets.zero : const EdgeInsets.all(24),
      shrinkWrap: widget.isEmbedded,
      physics: widget.isEmbedded ? const NeverScrollableScrollPhysics() : null,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        mainAxisExtent: 260,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: users.length,
      itemBuilder: (ctx, i) => _UserCard(user: users[i], auth: auth),
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
                radius: 14,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
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
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle),
                child: const Text('P', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              );
            } else {
              absentCount++;
              cellChild = Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: AppTheme.danger, shape: BoxShape.circle),
                child: const Text('A', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              );
            }
          } else {
            absentCount++;
            cellChild = Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppTheme.danger.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: const Text('A', style: TextStyle(color: AppTheme.danger, fontSize: 10, fontWeight: FontWeight.bold)),
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

      cells.add(DataCell(Center(child: Text('$presentCount', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold)))));
      cells.add(DataCell(Center(child: Text('$absentCount', style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold)))));

      return DataRow(cells: cells);
    }).toList();

    final attendanceContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
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
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: () => _changeMonth(1),
                  ),
                ],
              ),
              Text(
                'Total Staff: ${staffUsers.length}',
                style: TextStyle(color: context.textMutedColor, fontWeight: FontWeight.bold),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                            columnSpacing: 16,
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

    if (widget.isEmbedded) {
      return DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     const Text('Staff & Attendance', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                     Text('Manage profiles, roles, permissions, and log staff attendance', style: TextStyle(color: context.textMutedColor)),
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
                    label: const Text('Add Staff'),
                    onPressed: () {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => const UserFormDialog(),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TabBar(
              labelColor: AppTheme.primary,
              unselectedLabelColor: context.textMutedColor,
              indicatorColor: AppTheme.primary,
              tabs: const [
                Tab(icon: Icon(Icons.people_alt_rounded), text: 'Staff Registry'),
                Tab(icon: Icon(Icons.calendar_month_rounded), text: 'Attendance Logs'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 500,
              child: TabBarView(
                children: [
                  registryContent,
                  attendanceContent,
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        title: const Text('Staff Management'),
        backgroundColor: context.surfaceColor,
        elevation: 0,
        actions: [
          if (canManage)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shadowColor: AppTheme.primary.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.person_add_rounded, size: 18),
                label: const Text('Add New Staff'),
                onPressed: () {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const UserFormDialog(),
                  );
                },
              ),
            ),
        ],
      ),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Container(
              color: context.surfaceColor,
              child: TabBar(
                labelColor: AppTheme.primary,
                unselectedLabelColor: context.textMutedColor,
                indicatorColor: AppTheme.primary,
                tabs: const [
                  Tab(icon: Icon(Icons.people_alt_rounded), text: 'Staff Registry'),
                  Tab(icon: Icon(Icons.calendar_month_rounded), text: 'Attendance Logs'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  registryContent,
                  attendanceContent,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final AppUser user;
  final AuthProvider auth;
  const _UserCard({required this.user, required this.auth});

  @override
  Widget build(BuildContext context) {
    final isAdmin = user.role.toLowerCase() == 'admin';

    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Status Strip
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 4,
              child: Container(
                color: user.isActive ? AppTheme.success : AppTheme.danger,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                        child: Text(
                          user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primary,
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
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                )),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: context.bgColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                user.role.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                  color: context.textMutedColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (auth.canManageUsers)
                        IconButton(
                          onPressed: () {
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => UserFormDialog(existingUser: user),
                            );
                          },
                          icon: const Icon(Icons.edit_note_rounded),
                          color: AppTheme.primary,
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.primary.withValues(alpha: 0.08),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(height: 1),
                  const SizedBox(height: 20),
                  Text('MODULE ACCESS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: context.textMutedColor,
                      )),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _PermIcon(Icons.shopping_cart, 'POS', user.canAccessPOS || isAdmin, context),
                      _PermIcon(Icons.inventory_2, 'Stock', user.canEditInventory || isAdmin, context),
                      _PermIcon(Icons.local_hospital, 'OPD', user.canAccessOPD || isAdmin, context),
                      _PermIcon(Icons.analytics, 'Reports', (user.canViewDashboard || user.canViewOpdReports || user.canViewAnalytics || user.canViewSalesHistory) || isAdmin, context),
                      _PermIcon(Icons.settings, 'Admin', user.canAccessSettings || isAdmin, context),
                    ],
                  ),
                ],
              ),
            ),
            // PIN Badge (at bottom right)
            Positioned(
              bottom: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.bgColor.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.key, size: 12, color: context.textMutedColor),
                    const SizedBox(width: 6),
                    Text(user.pin,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: context.textColor,
                          letterSpacing: 1.5,
                        )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _PermIcon(IconData icon, String label, bool active, BuildContext context) {
    final color = active ? AppTheme.primary : context.textMutedColor.withValues(alpha: 0.3);
    return Tooltip(
      message: '$label: ${active ? "Access Granted" : "No Access"}',
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
