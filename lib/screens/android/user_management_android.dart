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

    return Scaffold(
      backgroundColor: context.surfaceColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: const Text('Staff Management'),
            pinned: true,
            floating: true,
            forceElevated: innerBoxIsScrolled,
            elevation: innerBoxIsScrolled ? 4 : 0,
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
                padding: const EdgeInsets.all(20).copyWith(bottom: 100),
                itemCount: users.length,
                itemBuilder: (ctx, i) =>
                    _buildUserCard(context, users[i], auth),
              ),
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
