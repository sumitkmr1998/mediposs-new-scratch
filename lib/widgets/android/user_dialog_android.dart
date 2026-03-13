import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/models/app_user.dart';
import '../../theme/app_theme.dart';

class AndroidUserDialog {
  static Future<void> showUserSheet(BuildContext context,
      {AppUser? existingUser}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _UserFormSheet(existingUser: existingUser),
    );
  }
}

class _UserFormSheet extends StatefulWidget {
  final AppUser? existingUser;

  const _UserFormSheet({this.existingUser});

  @override
  State<_UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends State<_UserFormSheet> {
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(widget.existingUser != null ? 'User updated' : 'User added'),
        backgroundColor: AppTheme.success,
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String labelText,
    IconData? prefixIcon,
    TextInputType? keyboardType,
    String? suffixText,
    bool autofocus = false,
    int maxLines = 1,
    TextInputAction textInputAction = TextInputAction.next,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textInputAction: textInputAction,
      validator: validator,
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: TextStyle(color: context.textMutedColor),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: AppTheme.primaryLight)
            : null,
        suffixText: suffixText,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: context.borderColor.withValues(alpha: 0.5))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: context.borderColor.withValues(alpha: 0.5))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
        filled: true,
        fillColor: Theme.of(context).scaffoldBackgroundColor,
        isDense: true,
      ),
    );
  }

  Widget _buildFormSection(
      {required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            title,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: AppTheme.primaryLight),
          ),
          children: children,
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
      activeColor: AppTheme.primaryLight,
      activeTrackColor: AppTheme.primary.withValues(alpha: 0.3),
      inactiveThumbColor: context.textMutedColor,
      inactiveTrackColor: context.borderColor,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingUser != null;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grab Handle
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                      color: context.borderColor,
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEdit ? 'Edit Staff' : 'Add New Staff',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryLight),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildField(
                              controller: _nameCtrl,
                              labelText: 'Full Name',
                              prefixIcon: Icons.person_rounded,
                              validator: (v) => v!.isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildField(
                              controller: _roleCtrl,
                              labelText: 'Role (Display)',
                              prefixIcon: Icons.badge_rounded,
                              validator: (v) => v!.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildField(
                              controller: _pinCtrl,
                              labelText: 'Login PIN',
                              prefixIcon: Icons.password_rounded,
                              keyboardType: TextInputType.number,
                              validator: (v) =>
                                  v!.length < 4 ? 'Min 4 chars' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                const Text('Active',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12)),
                                Switch(
                                  value: _isActive,
                                  onChanged: (val) =>
                                      setState(() => _isActive = val),
                                  activeColor: AppTheme.success,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Granular Permissions',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primaryLight,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildFormSection(
                        title: 'Admin & Settings',
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
                      const SizedBox(height: 12),
                      _buildFormSection(
                        title: 'Dashboard',
                        children: [
                          _buildPermToggle(
                              'View Dashboard',
                              'Can access KPI analytics and high-level charts',
                              _canViewDashboard,
                              (v) => setState(() => _canViewDashboard = v)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildFormSection(
                        title: 'Inventory Management',
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
                      const SizedBox(height: 12),
                      _buildFormSection(
                        title: 'Warehouse Operations',
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
                      const SizedBox(height: 12),
                      _buildFormSection(
                        title: 'Point of Sale (POS)',
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
                      const SizedBox(height: 12),
                      _buildFormSection(
                        title: 'Sales History & Refunds',
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
                      const SizedBox(height: 12),
                      _buildFormSection(
                        title: 'OPD Management',
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
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: Text(isEdit ? 'Save User' : 'Add User',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
