import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../shared/providers/auth_provider.dart';
import '../shared/models/app_user.dart';
import '../theme/app_theme.dart';

class UserFormDialog extends StatefulWidget {
  final AppUser? existingUser;

  const UserFormDialog({super.key, this.existingUser});

  @override
  State<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _roleCtrl;
  late TextEditingController _pinCtrl;

  bool _isActive = true;

  // Settings & Staff
  bool _canAccessSettings = false;
  bool _canManageUsers = false;

  // Dashboard
  bool _canViewDashboard = false;

  // Inventory
  bool _canViewInventory = false;
  bool _canEditInventory = false;

  // Warehouse
  bool _canViewWarehouse = false;
  bool _canTransferStock = false;

  // POS
  bool _canAccessPOS = true;
  bool _canDiscountSales = false;

  // Sales History
  bool _canViewSalesHistory = false;
  bool _canVoidSales = false;
  bool _canProcessReturns = false;

  // OPD
  bool _canAccessOPD = true;
  bool _canManageDoctors = false;
  bool _canViewOpdReports = false;

  @override
  void initState() {
    super.initState();
    final u = widget.existingUser;
    _nameCtrl = TextEditingController(text: u?.name ?? '');
    _roleCtrl = TextEditingController(text: u?.role ?? 'Staff');
    _pinCtrl = TextEditingController(text: u?.pin ?? '');

    if (u != null) {
      _isActive = u.isActive;

      _canAccessSettings = u.canAccessSettings;
      _canManageUsers = u.canManageUsers;
      _canViewDashboard = u.canViewDashboard;

      _canViewInventory = u.canViewInventory;
      _canEditInventory = u.canEditInventory;

      _canViewWarehouse = u.canViewWarehouse;
      _canTransferStock = u.canTransferStock;

      _canAccessPOS = u.canAccessPOS;
      _canDiscountSales = u.canDiscountSales;

      _canViewSalesHistory = u.canViewSalesHistory;
      _canVoidSales = u.canVoidSales;
      _canProcessReturns = u.canProcessReturns;

      _canAccessOPD = u.canAccessOPD;
      _canManageDoctors = u.canManageDoctors;
      _canViewOpdReports = u.canViewOpdReports;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final u = widget.existingUser ?? AppUser(name: _nameCtrl.text);

    u.name = _nameCtrl.text;
    u.role = _roleCtrl.text;
    u.pin = _pinCtrl.text;
    u.isActive = _isActive;

    u.canAccessSettings = _canAccessSettings;
    u.canManageUsers = _canManageUsers;
    u.canViewDashboard = _canViewDashboard;

    u.canViewInventory = _canViewInventory;
    u.canEditInventory = _canEditInventory;

    u.canViewWarehouse = _canViewWarehouse;
    u.canTransferStock = _canTransferStock;

    u.canAccessPOS = _canAccessPOS;
    u.canDiscountSales = _canDiscountSales;

    u.canViewSalesHistory = _canViewSalesHistory;
    u.canVoidSales = _canVoidSales;
    u.canProcessReturns = _canProcessReturns;

    u.canAccessOPD = _canAccessOPD;
    u.canManageDoctors = _canManageDoctors;
    u.canViewOpdReports = _canViewOpdReports;

    context.read<AuthProvider>().addUser(u);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Container(
        width: 850,
        height: 700,
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.05),
                    border: Border(bottom: BorderSide(color: context.borderColor, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.manage_accounts_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.existingUser == null ? 'CREATE NEW STAFF' : 'EDIT STAFF PROFILE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.existingUser?.name ?? 'New Team Member',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const Spacer(),
                      _StatusToggle(
                        isActive: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                    ],
                  ),
                ),

                // Body
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Side: Basic Info
                      Container(
                        width: 320,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          border: Border(right: BorderSide(color: context.borderColor, width: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('IDENTIFICATION',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                  color: context.textMutedColor,
                                )),
                            const SizedBox(height: 16),
                            _buildInput(
                              _nameCtrl,
                              'Full Name',
                              Icons.person_outline,
                              (v) => v!.isEmpty ? 'Required' : null,
                            ),
                            const SizedBox(height: 16),
                            _buildInput(
                              _roleCtrl,
                              'Role/Position',
                              Icons.badge_outlined,
                              (v) => v!.isEmpty ? 'Required' : null,
                            ),
                            const SizedBox(height: 16),
                            _buildInput(
                              _pinCtrl,
                              'Login PIN',
                              Icons.key_outlined,
                              (v) => v!.length < 4 ? 'Min 4 digits' : null,
                              isObscure: true,
                            ),
                            const Spacer(),
                            const Icon(Icons.shield_outlined, size: 48, color: AppTheme.primary),
                            const SizedBox(height: 12),
                            const Text(
                              'Secure Access',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Permissions defined on the right will take effect immediately after saving.',
                              style: TextStyle(fontSize: 12, color: context.textMutedColor),
                            ),
                          ],
                        ),
                      ),

                      // Right Side: Permissions Scored
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('PERMISSION MODULES',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                    color: context.textMutedColor,
                                  )),
                              const SizedBox(height: 24),
                              _PermGroup(
                                title: 'POS & Sales',
                                icon: Icons.shopping_basket_outlined,
                                children: [
                                  _PermTile('Access Terminal', 'Bill customers at POS', _canAccessPOS, (v) => setState(() => _canAccessPOS = v)),
                                  _PermTile('Manual Discounts', 'Apply custom discounts', _canDiscountSales, (v) => setState(() => _canDiscountSales = v)),
                                ],
                              ),
                              _PermGroup(
                                title: 'Inventory & Warehouse',
                                icon: Icons.inventory_2_outlined,
                                children: [
                                  _PermTile('Manage Stock', 'View and audit stock levels', _canViewInventory, (v) => setState(() => _canViewInventory = v)),
                                  _PermTile('Modify Items', 'Edit medicine details/pricing', _canEditInventory, (v) => setState(() => _canEditInventory = v)),
                                  _PermTile('Warehouse HQ', 'Manage main distribution', _canViewWarehouse, (v) => setState(() => _canViewWarehouse = v)),
                                  _PermTile('Execute Transfers', 'Move stock between locations', _canTransferStock, (v) => setState(() => _canTransferStock = v)),
                                ],
                              ),
                              _PermGroup(
                                title: 'OPD & Clinical',
                                icon: Icons.medical_services_outlined,
                                children: [
                                  _PermTile('Queue Management', 'Manage patiet visits', _canAccessOPD, (v) => setState(() => _canAccessOPD = v)),
                                  _PermTile('Manage Doctors', 'Edit doctor fees & profiles', _canManageDoctors, (v) => setState(() => _canManageDoctors = v)),
                                ],
                              ),
                              _PermGroup(
                                title: 'History & Admin',
                                icon: Icons.admin_panel_settings_outlined,
                                children: [
                                  _PermTile('Sale Auditing', 'View sales and void receipts', _canViewSalesHistory, (v) => setState(() => _canViewSalesHistory = v)),
                                  _PermTile('System Configuration', 'Access global settings', _canAccessSettings, (v) => setState(() => _canAccessSettings = v)),
                                  _PermTile('Manage Staff', 'Edit user roles & permissions', _canManageUsers, (v) => setState(() => _canManageUsers = v)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    border: Border(top: BorderSide(color: context.borderColor, width: 0.5)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        ),
                        child: Text('DISCARD', style: TextStyle(color: context.textMutedColor, letterSpacing: 1, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 16),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('SAVE PROFILE', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                          shadowColor: AppTheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput(TextEditingController ctrl, String label, IconData icon, String? Function(String?)? validator, {bool isObscure = false}) {
    return TextFormField(
      controller: ctrl,
      obscureText: isObscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: context.bgColor.withValues(alpha: 0.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      validator: validator,
    );
  }
}

class _StatusToggle extends StatelessWidget {
  final bool isActive;
  final ValueChanged<bool> onChanged;
  const _StatusToggle({required this.isActive, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!isActive),
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: (isActive ? AppTheme.success : AppTheme.danger).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: (isActive ? AppTheme.success : AppTheme.danger).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isActive ? AppTheme.success : AppTheme.danger,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isActive ? 'ACCOUNT ACTIVE' : 'ACCOUNT DEACTIVATED',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: isActive ? AppTheme.success : AppTheme.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _PermGroup({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor, width: 0.5),
          ),
          child: Column(children: children),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _PermTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool active;
  final ValueChanged<bool> onChanged;
  const _PermTile(this.title, this.subtitle, this.active, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: active,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: context.textMutedColor)),
      activeColor: AppTheme.primary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
