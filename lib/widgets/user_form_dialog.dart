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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: context.surfaceColor,
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existingUser == null ? 'Add New Staff' : 'Edit Staff',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: context.textColor,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _nameCtrl,
                      style: TextStyle(color: context.textColor),
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person, color: AppTheme.primary),
                      ),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _roleCtrl,
                      style: TextStyle(color: context.textColor),
                      decoration: const InputDecoration(
                        labelText: 'Role Title (Display Only)',
                        prefixIcon: Icon(Icons.badge, color: AppTheme.primary),
                      ),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _pinCtrl,
                      style: TextStyle(color: context.textColor),
                      decoration: const InputDecoration(
                        labelText: 'Login PIN',
                        prefixIcon:
                            Icon(Icons.password, color: AppTheme.primary),
                      ),
                      validator: (v) => v!.length < 4 ? 'Min 4 chars' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SwitchListTile(
                      title: Text('Account Active',
                          style: TextStyle(color: context.textColor)),
                      value: _isActive,
                      activeThumbColor: AppTheme.success,
                      onChanged: (val) => setState(() => _isActive = val),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Granular Permissions',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
              Divider(color: context.borderColor),
              Expanded(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ExpansionTile(
                      title: Text('Admin & Settings',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: context.textColor)),
                      children: [
                        _buildPermToggle(
                            'Access Settings',
                            'Can view/edit shop configuration, run backups',
                            _canAccessSettings,
                            (v) => setState(() => _canAccessSettings = v)),
                        _buildPermToggle(
                            'Manage Users',
                            'Can add staff and change their permissions',
                            _canManageUsers,
                            (v) => setState(() => _canManageUsers = v)),
                      ],
                    ),
                    ExpansionTile(
                      title: Text('Dashboard',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: context.textColor)),
                      children: [
                        _buildPermToggle(
                            'View Dashboard',
                            'Can access KPI analytics and high-level charts',
                            _canViewDashboard,
                            (v) => setState(() => _canViewDashboard = v)),
                      ],
                    ),
                    ExpansionTile(
                      title: Text('Inventory Management',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: context.textColor)),
                      children: [
                        _buildPermToggle(
                            'View Inventory',
                            'Can access Inventory list and check prices/stock',
                            _canViewInventory,
                            (v) => setState(() {
                                  _canViewInventory = v;
                                  if (!v) _canEditInventory = false;
                                })),
                        _buildPermToggle(
                            'Edit Inventory',
                            'Can ADD, EDIT, or DELETE medicines and categories',
                            _canEditInventory,
                            (v) => setState(() {
                                  _canEditInventory = v;
                                  if (v) _canViewInventory = true;
                                })),
                      ],
                    ),
                    ExpansionTile(
                      title: Text('Warehouse Operations',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: context.textColor)),
                      children: [
                        _buildPermToggle(
                            'View Warehouse',
                            'Can view main vs store stock distribution',
                            _canViewWarehouse,
                            (v) => setState(() {
                                  _canViewWarehouse = v;
                                  if (!v) _canTransferStock = false;
                                })),
                        _buildPermToggle(
                            'Execute Transfers',
                            'Can move stock between Main and Store warehouse',
                            _canTransferStock,
                            (v) => setState(() {
                                  _canTransferStock = v;
                                  if (v) _canViewWarehouse = true;
                                })),
                      ],
                    ),
                    ExpansionTile(
                      title: Text('Point of Sale (POS)',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: context.textColor)),
                      children: [
                        _buildPermToggle(
                            'Access POS',
                            'Can open POS screen and bill customers',
                            _canAccessPOS,
                            (v) => setState(() {
                                  _canAccessPOS = v;
                                  if (!v) _canDiscountSales = false;
                                })),
                        _buildPermToggle(
                            'Apply Discounts',
                            'Can apply manual discounts at checkout',
                            _canDiscountSales,
                            (v) => setState(() {
                                  _canDiscountSales = v;
                                  if (v) _canAccessPOS = true;
                                })),
                      ],
                    ),
                    ExpansionTile(
                      title: Text('Sales History & Refunds',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: context.textColor)),
                      children: [
                        _buildPermToggle(
                            'View History',
                            'Can view table of past receipts',
                            _canViewSalesHistory,
                            (v) => setState(() {
                                  _canViewSalesHistory = v;
                                  if (!v) {
                                    _canVoidSales = false;
                                    _canProcessReturns = false;
                                  }
                                })),
                        _buildPermToggle(
                            'Process Returns',
                            'Can execute Item Returns (negative quantities)',
                            _canProcessReturns,
                            (v) => setState(() {
                                  _canProcessReturns = v;
                                  if (v) _canViewSalesHistory = true;
                                })),
                        _buildPermToggle(
                            'Void Receipts',
                            'Can permanently delete/void an entire receipt',
                            _canVoidSales,
                            (v) => setState(() {
                                  _canVoidSales = v;
                                  if (v) _canViewSalesHistory = true;
                                })),
                      ],
                    ),
                    ExpansionTile(
                      title: Text('OPD Management',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: context.textColor)),
                      children: [
                        _buildPermToggle(
                            'Access OPD Queue',
                            'Can manage patient queue and view patient list',
                            _canAccessOPD,
                            (v) => setState(() {
                                  _canAccessOPD = v;
                                  if (!v) {
                                    _canManageDoctors = false;
                                    _canViewOpdReports = false;
                                  }
                                })),
                        _buildPermToggle(
                            'Manage Doctors',
                            'Can add/edit doctor profiles and fees',
                            _canManageDoctors,
                            (v) => setState(() {
                                  _canManageDoctors = v;
                                  if (v) _canAccessOPD = true;
                                })),
                        _buildPermToggle(
                            'View OPD Analytics',
                            'Can access OPD reports and revenue charts',
                            _canViewOpdReports,
                            (v) => setState(() {
                                  _canViewOpdReports = v;
                                  if (v) _canAccessOPD = true;
                                })),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel',
                        style: TextStyle(color: context.textMutedColor)),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Save User'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermToggle(
      String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title,
          style:
              TextStyle(color: context.textColor, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: TextStyle(color: context.textMutedColor, fontSize: 12)),
      value: value,
      activeThumbColor: AppTheme.primary,
      onChanged: onChanged,
    );
  }
}
