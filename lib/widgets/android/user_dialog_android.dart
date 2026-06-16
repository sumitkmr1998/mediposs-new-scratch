import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/models/app_user.dart';
import '../../shared/services/sync_service.dart';
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
  bool _canViewAnalytics = false;

  // Inventory
  bool _canViewInventory = false;
  bool _canEditInventory = false;
  bool _canOverrideStock = false;

  // Warehouse
  bool _canViewWarehouse = false;
  bool _canTransferStock = false;

  // POS
  bool _canAccessPOS = true;
  bool _canDiscountSales = false;
  bool _canOverridePrice = false;
  bool _canBulkDiscount = false;

  // Sales History
  bool _canViewSalesHistory = false;
  bool _canVoidSales = false;
  bool _canProcessReturns = false;
  bool _canEditSales = false;

  // OPD
  bool _canAccessOPD = true;
  bool _canManageDoctors = false;
  bool _canViewOpdReports = false;
  bool _canAccessMedicalRecords = false;
  bool _canDispenseMedicines = false;

  // Security & Data
  bool _canViewPurchasePrice = false;
  bool _canExportData = false;
  bool _canViewHistoricalData = true;

  // Deletion Rights
  bool _canDeleteInventory = false;
  bool _canDeletePatients = false;
  bool _canDeleteAppointments = false;
  bool _canProcessRetailSales = true;
  bool _canProcessClinicalDispenses = true;

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
      _canViewAnalytics = u.canViewAnalytics;

      _canViewInventory = u.canViewInventory;
      _canEditInventory = u.canEditInventory;
      _canOverrideStock = u.canOverrideStock;

      _canViewWarehouse = u.canViewWarehouse;
      _canTransferStock = u.canTransferStock;

      _canAccessPOS = u.canAccessPOS;
      _canDiscountSales = u.canDiscountSales;
      _canOverridePrice = u.canOverridePrice;
      _canBulkDiscount = u.canBulkDiscount;

      _canViewSalesHistory = u.canViewSalesHistory;
      _canVoidSales = u.canVoidSales;
      _canProcessReturns = u.canProcessReturns;
      _canEditSales = u.canEditSales;

      _canAccessOPD = u.canAccessOPD;
      _canManageDoctors = u.canManageDoctors;
      _canViewOpdReports = u.canViewOpdReports;
      _canAccessMedicalRecords = u.canAccessMedicalRecords;
      _canDispenseMedicines = u.canDispenseMedicines;

      _canViewPurchasePrice = u.canViewPurchasePrice;
      _canExportData = u.canExportData;
      _canViewHistoricalData = u.canViewHistoricalData;
      _canDeleteInventory = u.canDeleteInventory;
      _canDeletePatients = u.canDeletePatients;
      _canDeleteAppointments = u.canDeleteAppointments;
      _canProcessRetailSales = u.canProcessRetailSales;
      _canProcessClinicalDispenses = u.canProcessClinicalDispenses;
    }
  }

  void _applyPreset(String preset) {
    final tempUser = AppUser(name: '');
    tempUser.applyPreset(preset);
    setState(() {
      _roleCtrl.text = tempUser.role;
      _canAccessSettings = tempUser.canAccessSettings;
      _canManageUsers = tempUser.canManageUsers;
      _canViewDashboard = tempUser.canViewDashboard;
      _canViewAnalytics = tempUser.canViewAnalytics;
      _canViewInventory = tempUser.canViewInventory;
      _canEditInventory = tempUser.canEditInventory;
      _canOverrideStock = tempUser.canOverrideStock;
      _canViewWarehouse = tempUser.canViewWarehouse;
      _canTransferStock = tempUser.canTransferStock;
      _canAccessPOS = tempUser.canAccessPOS;
      _canDiscountSales = tempUser.canDiscountSales;
      _canOverridePrice = tempUser.canOverridePrice;
      _canBulkDiscount = tempUser.canBulkDiscount;
      _canViewSalesHistory = tempUser.canViewSalesHistory;
      _canVoidSales = tempUser.canVoidSales;
      _canProcessReturns = tempUser.canProcessReturns;
      _canEditSales = tempUser.canEditSales;
      _canAccessOPD = tempUser.canAccessOPD;
      _canManageDoctors = tempUser.canManageDoctors;
      _canViewOpdReports = tempUser.canViewOpdReports;
      _canAccessMedicalRecords = tempUser.canAccessMedicalRecords;
      _canDispenseMedicines = tempUser.canDispenseMedicines;
      _canViewPurchasePrice = tempUser.canViewPurchasePrice;
      _canExportData = tempUser.canExportData;
      _canViewHistoricalData = tempUser.canViewHistoricalData;
      _canDeleteInventory = tempUser.canDeleteInventory;
      _canDeletePatients = tempUser.canDeletePatients;
      _canDeleteAppointments = tempUser.canDeleteAppointments;
      _canProcessRetailSales = tempUser.canProcessRetailSales;
      _canProcessClinicalDispenses = tempUser.canProcessClinicalDispenses;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final auth = context.read<AuthProvider>();
    if (!auth.canManageUsers) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unauthorized: You do not have permission to manage staff profiles.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final u = widget.existingUser ?? AppUser(name: _nameCtrl.text);

    u.name = _nameCtrl.text;
    u.role = _roleCtrl.text;
    u.pin = _pinCtrl.text;
    u.isActive = _isActive;

    u.canAccessSettings = _canAccessSettings;
    u.canManageUsers = _canManageUsers;
    u.canViewDashboard = _canViewDashboard;
    u.canViewAnalytics = _canViewAnalytics;

    u.canViewInventory = _canViewInventory;
    u.canEditInventory = _canEditInventory;
    u.canOverrideStock = _canOverrideStock;

    u.canViewWarehouse = _canViewWarehouse;
    u.canTransferStock = _canTransferStock;

    u.canAccessPOS = _canAccessPOS;
    u.canDiscountSales = _canDiscountSales;
    u.canOverridePrice = _canOverridePrice;
    u.canBulkDiscount = _canBulkDiscount;

    u.canViewSalesHistory = _canViewSalesHistory;
    u.canVoidSales = _canVoidSales;
    u.canProcessReturns = _canProcessReturns;
    u.canEditSales = _canEditSales;

    u.canAccessOPD = _canAccessOPD;
    u.canManageDoctors = _canManageDoctors;
    u.canViewOpdReports = _canViewOpdReports;
    u.canAccessMedicalRecords = _canAccessMedicalRecords;
    u.canDispenseMedicines = _canDispenseMedicines;

    u.canViewPurchasePrice = _canViewPurchasePrice;
    u.canExportData = _canExportData;
    u.canViewHistoricalData = _canViewHistoricalData;
    u.canDeleteInventory = _canDeleteInventory;
    u.canDeletePatients = _canDeletePatients;
    u.canDeleteAppointments = _canDeleteAppointments;
    u.canProcessRetailSales = _canProcessRetailSales;
    u.canProcessClinicalDispenses = _canProcessClinicalDispenses;

    context.read<AuthProvider>().addUser(u, syncService: context.read<SyncService>());
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
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      decoration: InputDecoration(
        labelText: labelText.toUpperCase(),
        labelStyle: TextStyle(color: context.textMutedColor, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.8),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: AppTheme.primaryLight, size: 20)
            : null,
        suffixText: suffixText,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: context.borderColor.withValues(alpha: 0.3))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: context.borderColor.withValues(alpha: 0.3))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
        filled: true,
        fillColor: context.textMutedColor.withValues(alpha: 0.03),
        isDense: true,
      ),
    );
  }

  Widget _buildFormSection(
      {required String title, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            title.toUpperCase(),
            style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 1,
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
              TextStyle(color: context.textColor, fontWeight: FontWeight.w800, fontSize: 14)),
      subtitle: Text(subtitle,
          style: TextStyle(color: context.textMutedColor, fontSize: 11, fontWeight: FontWeight.w600)),
      value: value,
      activeColor: AppTheme.success,
      activeTrackColor: AppTheme.success.withValues(alpha: 0.2),
      inactiveThumbColor: context.textMutedColor,
      inactiveTrackColor: context.borderColor.withValues(alpha: 0.3),
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
                  const SizedBox(height: 12),
                  // Role Presets
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _presetChip('CASHIER', Icons.point_of_sale_rounded, () => _applyPreset('Cashier')),
                        _presetChip('PHARMACIST', Icons.medication_rounded, () => _applyPreset('Pharmacist')),
                        _presetChip('DOCTOR', Icons.medical_services_rounded, () => _applyPreset('Doctor')),
                        _presetChip('MANAGER', Icons.supervisor_account_rounded, () => _applyPreset('Manager')),
                        _presetChip('ADMIN', Icons.admin_panel_settings_rounded, () => _applyPreset('Admin')),
                      ],
                    ),
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
                              (v) => setState(() {
                                    _canViewDashboard = v;
                                    if (!v) _canViewAnalytics = false;
                                  })),
                          _buildPermToggle(
                              'View Analytics',
                              'Can access advanced business analytics hub',
                              _canViewAnalytics,
                              (v) => setState(() {
                                    _canViewAnalytics = v;
                                    if (v) _canViewDashboard = true;
                                  })),
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
                                    if (!v) {
                                      _canEditInventory = false;
                                      _canDeleteInventory = false;
                                      _canOverrideStock = false;
                                    }
                                  })),
                          _buildPermToggle(
                              'Edit Inventory',
                              'Can ADD, EDIT, or DELETE medicines and categories',
                              _canEditInventory,
                              (v) => setState(() {
                                    _canEditInventory = v;
                                    if (v) _canViewInventory = true;
                                    if (!v) _canDeleteInventory = false;
                                  })),
                          _buildPermToggle(
                              'Override Stock',
                              'Can manually adjust stock counts (Auditing)',
                              _canOverrideStock,
                              (v) => setState(() {
                                    _canOverrideStock = v;
                                    if (v) _canViewInventory = true;
                                  })),
                          _buildPermToggle(
                              'Delete Items',
                              'Can permanently remove medicines from system',
                              _canDeleteInventory,
                              (v) => setState(() {
                                    _canDeleteInventory = v;
                                    if (v) {
                                      _canEditInventory = true;
                                      _canViewInventory = true;
                                    }
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
                                    if (!v) {
                                      _canProcessRetailSales = false;
                                      _canProcessClinicalDispenses = false;
                                      _canDiscountSales = false;
                                      _canOverridePrice = false;
                                      _canBulkDiscount = false;
                                    }
                                  })),
                          _buildPermToggle(
                              'Process Retail Sales',
                              'Allow standard retail checkout (GST)',
                              _canProcessRetailSales,
                              (v) => setState(() {
                                    _canProcessRetailSales = v;
                                    if (v) _canAccessPOS = true;
                                  })),
                          _buildPermToggle(
                              'Process Clinical Dispenses',
                              'Allow clinical dispensing (internal consumption)',
                              _canProcessClinicalDispenses,
                              (v) => setState(() {
                                    _canProcessClinicalDispenses = v;
                                    if (v) _canAccessPOS = true;
                                  })),
                          _buildPermToggle(
                              'Apply Discounts',
                              'Can apply manual discounts at checkout',
                              _canDiscountSales,
                              (v) => setState(() {
                                    _canDiscountSales = v;
                                    if (v) _canAccessPOS = true;
                                  })),
                          _buildPermToggle(
                              'Price Overrides',
                              'Can change item price on the fly in POS',
                              _canOverridePrice,
                              (v) => setState(() {
                                    _canOverridePrice = v;
                                    if (v) _canAccessPOS = true;
                                  })),
                          _buildPermToggle(
                              'Bulk Discounts',
                              'Can apply flat discounts to entire bill',
                              _canBulkDiscount,
                              (v) => setState(() {
                                    _canBulkDiscount = v;
                                    if (v) _canAccessPOS = true;
                                  })),
                          _buildPermToggle(
                              'Edit Sales',
                              'Can edit completed invoices/receipts',
                              _canEditSales,
                              (v) => setState(() {
                                    _canEditSales = v;
                                    if (v) {
                                      _canAccessPOS = true;
                                      _canViewSalesHistory = true;
                                    }
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
                                      _canAccessMedicalRecords = false;
                                      _canManageDoctors = false;
                                      _canViewOpdReports = false;
                                      _canDeletePatients = false;
                                      _canDeleteAppointments = false;
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
                          _buildPermToggle(
                              'Privacy: Medical Records',
                              'Can view clinical history and prescriptions',
                              _canAccessMedicalRecords,
                              (v) => setState(() {
                                    _canAccessMedicalRecords = v;
                                    if (v) _canAccessOPD = true;
                                  })),
                          _buildPermToggle(
                              'Dispense Medicines',
                              'Can load and bill prescriptions in POS',
                              _canDispenseMedicines,
                              (v) => setState(() {
                                    _canDispenseMedicines = v;
                                    if (v) _canAccessOPD = true;
                                  })),
                          _buildPermToggle(
                              'Delete Patients',
                              'Can permanently remove patient files',
                              _canDeletePatients,
                              (v) => setState(() {
                                    _canDeletePatients = v;
                                    if (v) _canAccessOPD = true;
                                  })),
                          _buildPermToggle(
                              'Cancel Appointments',
                              'Can remove patient visits from queue',
                              _canDeleteAppointments,
                              (v) => setState(() {
                                    _canDeleteAppointments = v;
                                    if (v) _canAccessOPD = true;
                                  })),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildFormSection(
                        title: 'Security & Financial Data',
                        children: [
                          _buildPermToggle(
                              'View Purchase Price',
                              'Can see cost prices of medicines (Restricted)',
                              _canViewPurchasePrice,
                              (v) => setState(() => _canViewPurchasePrice = v)),
                          _buildPermToggle(
                              'Today Only Access',
                              'Restriction: Staff cannot see past records',
                              !_canViewHistoricalData,
                              (v) => setState(() => _canViewHistoricalData = !v)),
                          _buildPermToggle(
                              'Export Data',
                              'Can export system records to Excel/CSV',
                              _canExportData,
                              (v) => setState(() => _canExportData = v)),
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

  Widget _presetChip(String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 14, color: AppTheme.primary),
        label: Text(label,
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        onPressed: onTap,
        backgroundColor: AppTheme.primary.withValues(alpha: 0.05),
        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.1)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
