import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/models/app_user.dart';
import '../../theme/app_theme.dart';
import '../../widgets/user_form_dialog.dart';

class UserManagementWindows extends StatefulWidget {
  const UserManagementWindows({super.key});

  @override
  State<UserManagementWindows> createState() => _UserManagementWindowsState();
}

class _UserManagementWindowsState extends State<UserManagementWindows> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final users = auth.getAllUsers();

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add New Staff',
            onPressed: () {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const UserFormDialog(),
              );
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverToBoxAdapter(
              child: Card(
                elevation: 0,
                color: context.surfaceColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: AppTheme.primary.withValues(alpha: 0.1)),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingTextStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: context.textColor,
                    ),
                    columns: const [
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Role Title')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Sell')),
                      DataColumn(label: Text('Inventory')),
                      DataColumn(label: Text('OPD')),
                      DataColumn(label: Text('Reports')),
                      DataColumn(label: Text('Settings')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: users.map((u) => _buildRow(u, auth)).toList(),
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  DataRow _buildRow(AppUser user, AuthProvider auth) {
    final isAdmin = user.role.toLowerCase() == 'admin';
    return DataRow(
      cells: [
        DataCell(
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                radius: 16,
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppTheme.primary, fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(user.pin,
                      style: TextStyle(
                          color: context.textMutedColor, fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
        DataCell(Text(user.role)),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: user.isActive
                  ? AppTheme.success.withValues(alpha: 0.15)
                  : AppTheme.danger.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              user.isActive ? 'Active' : 'Inactive',
              style: TextStyle(
                color: user.isActive ? AppTheme.success : AppTheme.danger,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        DataCell(_boolIcon(user.canAccessPOS || isAdmin)),
        DataCell(_boolIcon(user.canEditInventory || isAdmin)),
        DataCell(_boolIcon(user.canAccessOPD || isAdmin)),
        DataCell(_boolIcon(
            user.canViewDashboard || user.canViewOpdReports || isAdmin)),
        DataCell(_boolIcon(user.canAccessSettings || isAdmin)),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 20, color: AppTheme.primary),
                tooltip: 'Edit Permissions',
                onPressed: () {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => UserFormDialog(existingUser: user),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _boolIcon(bool val) {
    return Icon(
      val ? Icons.check_circle : Icons.cancel,
      color: val ? AppTheme.success : context.textMutedColor,
      size: 18,
    );
  }
}
