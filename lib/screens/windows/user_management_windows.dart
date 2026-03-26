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
      backgroundColor: context.bgColor,
      appBar: AppBar(
        title: const Text('Staff Management'),
        backgroundColor: context.surfaceColor,
        elevation: 0,
        actions: [
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
      body: GridView.builder(
        padding: const EdgeInsets.all(24),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 400,
          mainAxisExtent: 260,
          crossAxisSpacing: 24,
          mainAxisSpacing: 24,
        ),
        itemCount: users.length,
        itemBuilder: (ctx, i) => _UserCard(user: users[i], auth: auth),
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
                      _PermIcon(Icons.analytics, 'Reports', (user.canViewDashboard || user.canViewOpdReports) || isAdmin, context),
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
