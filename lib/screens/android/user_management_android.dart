import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/models/app_user.dart';
import '../../theme/app_theme.dart';
import '../../widgets/android/user_dialog_android.dart';

class UserManagementAndroid extends StatefulWidget {
  const UserManagementAndroid({super.key});

  @override
  State<UserManagementAndroid> createState() => _UserManagementAndroidState();
}

class _UserManagementAndroidState extends State<UserManagementAndroid> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final users = auth.getAllUsers();

    return Scaffold(
      backgroundColor: context.surfaceColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: const Text('User Management'),
            pinned: true,
            floating: true,
            forceElevated: innerBoxIsScrolled,
            elevation: innerBoxIsScrolled ? 4 : 0,
            actions: [
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
        ],
        body: users.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline,
                        size: 72, color: context.textMutedColor),
                    const SizedBox(height: 16),
                    Text('No staff found',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                color: context.textMutedColor,
                                fontWeight: FontWeight.w600)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16).copyWith(bottom: 100),
                itemCount: users.length,
                itemBuilder: (ctx, i) =>
                    _buildUserCard(context, users[i], auth),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          AndroidUserDialog.showUserSheet(context);
        },
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }

  Widget _buildUserCard(BuildContext context, AppUser user, AuthProvider auth) {
    final isAdmin = user.role.toLowerCase() == 'admin';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
        border: Border.all(color: context.borderColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 22,
                          fontWeight: FontWeight.w900),
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
                              fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('${user.role}  •  PIN: ${user.pin}',
                          style: TextStyle(
                              color: context.textMutedColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: user.isActive
                        ? AppTheme.success.withValues(alpha: 0.1)
                        : AppTheme.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    user.isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      color: user.isActive ? AppTheme.success : AppTheme.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _permChip('POS', user.canAccessPOS || isAdmin),
                _permChip('Inventory', user.canEditInventory || isAdmin),
                _permChip('OPD', user.canAccessOPD || isAdmin),
                _permChip('Reports',
                    user.canViewDashboard || user.canViewOpdReports || isAdmin),
                _permChip('Settings', user.canAccessSettings || isAdmin),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding:
                const EdgeInsets.only(top: 8, bottom: 8, right: 8, left: 16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                    color: context.borderColor.withValues(alpha: 0.3)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Permissions & Access',
                    style: TextStyle(
                        color: context.textMutedColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  color: const Color(0xFF6366F1),
                  tooltip: 'Edit Permissions',
                  onPressed: () {
                    AndroidUserDialog.showUserSheet(context,
                        existingUser: user);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _permChip(String label, bool val) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: val
            ? AppTheme.success.withValues(alpha: 0.08)
            : context.textMutedColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: val
              ? AppTheme.success.withValues(alpha: 0.3)
              : context.borderColor.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            val ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: val ? AppTheme.success : context.textMutedColor,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: val ? AppTheme.success : context.textMutedColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
