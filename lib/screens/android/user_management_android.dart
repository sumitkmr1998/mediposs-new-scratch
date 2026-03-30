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
        color: context.surfaceColor.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: context.borderColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.primary.withValues(alpha: 0.2), AppTheme.primary.withValues(alpha: 0.05)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: AppTheme.primaryLight,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
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
                              fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: -0.2)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _Badge(
                            label: user.role.toUpperCase(),
                            color: isAdmin ? AppTheme.primaryLight : context.textMutedColor,
                            isGlass: true,
                          ),
                          const SizedBox(width: 8),
                          Text('PIN: ${user.pin}',
                              style: TextStyle(
                                  color: context.textMutedColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1)),
                        ],
                      ),
                    ],
                  ),
                ),
                _StatusBadge(isActive: user.isActive),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _permChip('POS', user.canAccessPOS || isAdmin),
                _permChip('INVENTORY', user.canEditInventory || isAdmin),
                _permChip('OPD', user.canAccessOPD || isAdmin),
                _permChip('REPORTS', user.canViewDashboard || user.canViewOpdReports || isAdmin),
                _permChip('SETTINGS', user.canAccessSettings || isAdmin),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: context.textMutedColor.withValues(alpha: 0.03),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              border: Border(top: BorderSide(color: context.borderColor.withValues(alpha: 0.2))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('STAFF ACCESS PERMISSIONS',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        color: AppTheme.primaryLight)),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => AndroidUserDialog.showUserSheet(context, existingUser: user),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 14, color: AppTheme.primary),
                          SizedBox(width: 6),
                          Text('EDIT', style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ),
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
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: val
              ? AppTheme.success.withValues(alpha: 0.2)
              : context.borderColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            val ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
            color: val ? AppTheme.success : context.textMutedColor.withValues(alpha: 0.4),
            size: 12,
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: val ? AppTheme.success.withValues(alpha: 0.9) : context.textMutedColor.withValues(alpha: 0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final bool isGlass;

  const _Badge({required this.label, required this.color, this.isGlass = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isGlass ? color.withValues(alpha: 0.08) : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.withValues(alpha: 0.9),
          fontSize: 10,
          fontWeight: FontWeight.w900,
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
                BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 4, spreadRadius: 1),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isActive ? 'ACTIVE' : 'INACTIVE',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
