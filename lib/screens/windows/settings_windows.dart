import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../../shared/services/cloudflare_service.dart';
import '../../shared/services/sync_service.dart';

import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/navigation_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/models/app_user.dart';
import '../../theme/app_theme.dart';
import '../../shared/services/local_server_service.dart';
import '../../shared/services/printing_service.dart';
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as excel_pkg;
import '../../shared/providers/inventory_provider.dart';
import '../../shared/models/medicine.dart';
import '../user_management_screen.dart';
import '../opd/doctor_list_screen.dart';
import 'user_management_windows.dart';
import 'opd/doctor_list_windows.dart';
import 'widgets/settings_widgets.dart';

class SettingsWindows extends StatefulWidget {
  const SettingsWindows({super.key});

  @override
  State<SettingsWindows> createState() => _SettingsWindowsState();
}

class _SettingsWindowsState extends State<SettingsWindows> {
  late final TextEditingController _storeNameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _gstCtrl;
  late final TextEditingController _clinicNameCtrl;
  late final TextEditingController _clinicAddressCtrl;
  late final TextEditingController _clinicPhoneCtrl;
  late final TextEditingController _clinicRegCtrl;
  late final TextEditingController _footerCtrl;
  late final TextEditingController _taxCtrl;
  late final TextEditingController _currencyCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _lowStockCtrl;
  late final TextEditingController _nearExpiryCtrl;

  String _selectedTheme = 'system';
  List<Printer> _printers = [];
  String _selectedPrinter = '';
  bool _autoPrint = false;
  String _paperSize = 'A6';
  int _selectedSection = 0;
  
  // New UI states
  bool _enableAnimations = true;
  String _autoBackupFreq = 'Never';
  String _autoBackupLogic = 'At Startup';
  String? _hubIp;
  bool _isWindowsClient = false;
  bool _isCompositionScheme = false;
  bool _showBatchExpiryRetail = true;
  bool _showBatchExpiryClinical = true;

  @override
  void initState() {
    super.initState();
    _loadHubIp();
    // ...
    final s = context.read<SettingsProvider>().settings;
    _storeNameCtrl = TextEditingController(text: s.storeName);
    _addressCtrl = TextEditingController(text: s.storeAddress);
    _phoneCtrl = TextEditingController(text: s.storePhone);
    _gstCtrl = TextEditingController(text: s.gstNumber);
    _clinicNameCtrl = TextEditingController(text: s.clinicName ?? 'MediPoss Clinic');
    _clinicAddressCtrl = TextEditingController(text: s.clinicAddress ?? '');
    _clinicPhoneCtrl = TextEditingController(text: s.clinicPhone ?? '');
    _clinicRegCtrl = TextEditingController(text: s.clinicRegNo ?? '');
    _footerCtrl = TextEditingController(text: s.receiptFooterMessage);
    _taxCtrl = TextEditingController(text: '${s.taxRate}');
    _currencyCtrl = TextEditingController(text: s.currencySymbol);
    _portCtrl = TextEditingController(text: '${s.serverPort}');
    _lowStockCtrl = TextEditingController(text: '${s.lowStockThreshold}');
    _nearExpiryCtrl = TextEditingController(text: '${s.nearExpiryThresholdDays}');
    
    _selectedTheme = ['system', 'light', 'dark'].contains(s.themeMode) ? s.themeMode : 'system';
    _selectedPrinter = s.defaultPrinterName;
    _autoPrint = s.autoPrintReceipt;
    _paperSize = ['A6', 'Letter', 'A4', 'Roll80'].contains(s.receiptPaperSize) ? s.receiptPaperSize : 'A6';
    _enableAnimations = s.enableAnimations;
    _autoBackupFreq = ['Never', 'Daily', 'Weekly', 'Monthly'].contains(s.autoBackupFrequency) 
        ? s.autoBackupFrequency 
        : 'Never';
    _autoBackupLogic = ['At Startup', 'On Close', 'Periodic'].contains(s.autoBackupLogic) 
        ? s.autoBackupLogic 
        : 'At Startup';
    _isWindowsClient = s.isWindowsClient;
    _isCompositionScheme = s.isCompositionScheme;
    _showBatchExpiryRetail = s.showBatchExpiryInRetailPrint;
    _showBatchExpiryClinical = s.showBatchExpiryInClinicalPrint;

    _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    final printers = await Printing.listPrinters();
    if (mounted) {
      setState(() {
        _printers = printers.where((p) => p.isAvailable).toList();
      });
    }
  }

  Future<void> _loadHubIp() async {
    try {
      final info = NetworkInfo();
      final ip = await info.getWifiIP();
      if (mounted) setState(() => _hubIp = ip);
    } catch (e) {
      debugPrint('Error loading Hub IP: $e');
    }
  }

  void _save() {
    final settingsProv = context.read<SettingsProvider>();
    final s = settingsProv.settings;
    s
      ..storeName = _storeNameCtrl.text
      ..storeAddress = _addressCtrl.text
      ..storePhone = _phoneCtrl.text
      ..gstNumber = _gstCtrl.text
      ..receiptFooterMessage = _footerCtrl.text
      ..taxRate = _isCompositionScheme ? 0.0 : (double.tryParse(_taxCtrl.text) ?? 0)
      ..currencySymbol = _currencyCtrl.text
      ..themeMode = _selectedTheme
      ..defaultPrinterName = _selectedPrinter
      ..autoPrintReceipt = _autoPrint
      ..receiptPaperSize = _paperSize
      ..lowStockThreshold = int.tryParse(_lowStockCtrl.text) ?? 10
      ..nearExpiryThresholdDays = int.tryParse(_nearExpiryCtrl.text) ?? 90
      ..serverPort = int.tryParse(_portCtrl.text) ?? 8080
      ..enableAnimations = _enableAnimations
      ..autoBackupFrequency = _autoBackupFreq
      ..autoBackupLogic = _autoBackupLogic
      ..isWindowsClient = _isWindowsClient
      ..clinicName = _clinicNameCtrl.text
      ..clinicAddress = _clinicAddressCtrl.text
      ..clinicPhone = _clinicPhoneCtrl.text
      ..clinicRegNo = _clinicRegCtrl.text
      ..isCompositionScheme = _isCompositionScheme
      ..showBatchExpiryInRetailPrint = _showBatchExpiryRetail
      ..showBatchExpiryInClinicalPrint = _showBatchExpiryClinical;

    final wasClient = settingsProv.settings.isWindowsClient;
    settingsProv.save(s);
    LocalServerService.instance.broadcast({'event': 'settings_updated'});

    if (wasClient != _isWindowsClient) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Restart Required'),
          content: const Text(
              'Changing between Hub and Terminal mode requires a full application restart to apply network changes.'),
          actions: [
            ElevatedButton(
              onPressed: () => exit(0),
              child: const Text('Restart Now'),
            ),
          ],
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Settings saved successfully'),
      backgroundColor: AppTheme.success,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
    ));
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _gstCtrl.dispose();
    _clinicNameCtrl.dispose();
    _clinicAddressCtrl.dispose();
    _clinicPhoneCtrl.dispose();
    _clinicRegCtrl.dispose();
    _footerCtrl.dispose();
    _taxCtrl.dispose();
    _currencyCtrl.dispose();
    _portCtrl.dispose();
    _lowStockCtrl.dispose();
    _nearExpiryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final settingsProv = context.watch<SettingsProvider>();

    final navItems = [
      _NavModel(LucideIcons.store, 'Store Details', AppTheme.primary),
      _NavModel(LucideIcons.printer, 'Printing', AppTheme.accent),
      _NavModel(LucideIcons.monitor, 'Interface', AppTheme.purple),
      _NavModel(LucideIcons.cloud, 'Cloud Sync', AppTheme.sky),
      _NavModel(LucideIcons.network, 'Networking', Colors.orange),
      _NavModel(LucideIcons.package, 'Inventory', Colors.teal),
      _NavModel(LucideIcons.database, 'Data', AppTheme.warning),
      if (auth.isAdmin) ...[
        _NavModel(LucideIcons.users, 'Staff', AppTheme.success),
        _NavModel(LucideIcons.stethoscope, 'Doctors', Colors.indigo),
      ],
    ];

    return Scaffold(
      body: Row(
        children: [
          // Glass Sidebar
          Container(
            width: 280,
            decoration: BoxDecoration(
              color: context.surfaceColor,
              border: Border(right: BorderSide(color: context.borderColor)),
            ),
            child: Column(
              children: [
                _buildSidebarHeader(),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: navItems.length,
                    itemBuilder: (context, index) {
                      final item = navItems[index];
                      return SettingsSidebarItem(
                        icon: item.icon,
                        label: item.label,
                        isSelected: _selectedSection == index,
                        accentColor: item.color,
                        onTap: () => setState(() => _selectedSection = index),
                      );
                    },
                  ),
                ),
                _buildSidebarFooter(),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: Stack(
              children: [
                Container(color: context.bgColor),
                
                Positioned.fill(
                  child: Builder(
                    builder: (context) {
                      final title = navItems[_selectedSection].label;
                      final isManagement = title == 'Staff' || title == 'Doctors';
                      
                      final content = Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionContent(title, settingsProv, auth),
                            const SizedBox(height: 100),
                          ],
                        ),
                      );

                      if (isManagement) {
                        return SingleChildScrollView(
                          padding: EdgeInsets.zero,
                          child: content,
                        );
                      }

                      return SingleChildScrollView(
                        child: content,
                      );
                    },
                  ),
                ),

                // Save FAB
                Positioned(
                  bottom: 30,
                  right: 30,
                  child: FloatingActionButton.extended(
                    onPressed: _save,
                    icon: const Icon(LucideIcons.save, size: 18),
                    label: const Text('Save Changes'),
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ).animate().scale(delay: 500.ms, duration: 300.ms, curve: Curves.easeOutBack),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                context.read<NavigationProvider>().selectDestination('dashboard');
              }
            },
            icon: const Icon(LucideIcons.arrowLeft, size: 20),
            tooltip: 'Go Back',
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, AppTheme.primaryLight],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(LucideIcons.settings, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              Text(
                'MediPoss Hub v1.0',
                style: TextStyle(fontSize: 12, color: context.textMutedColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarFooter() {
    final user = context.read<AuthProvider>().currentUser;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
            child: const Icon(LucideIcons.user, color: AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.name ?? 'Administrator',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(user?.role ?? 'Admin', style: TextStyle(fontSize: 11, color: context.textMutedColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionContent(String title, SettingsProvider settingsProv, AuthProvider auth) {
    switch (title) {
      case 'Store Details':
        return _buildStoreSection();
      case 'Printing':
        return _buildPrintingSection();
      case 'Interface':
        return _buildInterfaceSection();
      case 'Cloud Sync':
        return _buildCloudSection(settingsProv);
      case 'Networking':
        return _buildNetworkingSection();
      case 'Inventory':
        return _buildInventorySection();
      case 'Data':
        return _buildDataSection(settingsProv);
      case 'Staff':
        return UserManagementWindows(isEmbedded: true);
      case 'Doctors':
        return DoctorListWindows(isEmbedded: true);
      default:
        return const SizedBox();
    }
  }

  Widget _buildStoreSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(
          title: 'Store Information',
          icon: LucideIcons.building,
          children: [
            SettingsField(controller: _storeNameCtrl, label: 'Store Name', icon: LucideIcons.building),
            SettingsField(controller: _addressCtrl, label: 'Store Address', icon: LucideIcons.mapPin),
            Row(
              children: [
                Expanded(child: SettingsField(controller: _phoneCtrl, label: 'Store Phone', icon: LucideIcons.phone)),
                const SizedBox(width: 16),
                Expanded(child: SettingsField(controller: _gstCtrl, label: 'GST Number', icon: LucideIcons.fileText)),
              ],
            ),
            const SizedBox(height: 16),
            SettingsSwitch(
              title: 'GST Composition Scheme',
              subtitle: 'Enable if the store is registered under the GST Composition Scheme (tax is not collected from customers).',
              value: _isCompositionScheme,
              icon: LucideIcons.percent,
              onChanged: (val) {
                setState(() {
                  _isCompositionScheme = val;
                  if (val) {
                    _taxCtrl.text = '0.0';
                  }
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 32),
        SettingsSection(
          title: 'Clinic / Doctor Details (for Clinical Dispenses)',
          icon: LucideIcons.stethoscope,
          children: [
            SettingsField(controller: _clinicNameCtrl, label: 'Clinic / Doctor Name', icon: LucideIcons.stethoscope),
            SettingsField(controller: _clinicAddressCtrl, label: 'Physical Address', icon: LucideIcons.mapPin),
            Row(
              children: [
                Expanded(child: SettingsField(controller: _clinicPhoneCtrl, label: 'Contact Phone', icon: LucideIcons.phone)),
                const SizedBox(width: 16),
                Expanded(child: SettingsField(controller: _clinicRegCtrl, label: 'Medical Reg No.', icon: LucideIcons.fileText)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCloudSection(SettingsProvider settingsProv) {
    return Column(
      children: [
        SettingsSection(
          title: 'Google Drive Cloud Sync',
          icon: LucideIcons.cloud,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: settingsProv.settings.googleDriveLinked ? AppTheme.success.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                  child: Icon(
                    settingsProv.settings.googleDriveLinked ? LucideIcons.cloudLightning : LucideIcons.cloudOff,
                    color: settingsProv.settings.googleDriveLinked ? AppTheme.success : AppTheme.danger,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settingsProv.settings.googleDriveLinked ? 'Google Account Connected' : 'Google Drive Not Linked',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        settingsProv.settings.googleDriveLinked 
                          ? 'Automated backups are configured according to your schedule.' 
                          : 'Connect your Google account to enable full database zipping and cloud storage.',
                        style: TextStyle(color: context.textMutedColor, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (!settingsProv.settings.googleDriveLinked)
                  ElevatedButton.icon(
                    onPressed: settingsProv.isGoogleLoading ? null : () => settingsProv.linkGoogleDrive(),
                    icon: const Icon(LucideIcons.chrome, size: 18),
                    label: Text(settingsProv.isGoogleLoading ? 'Opening Browser...' : 'Link Account'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.sky),
                  )
                else
                  TextButton.icon(
                    onPressed: () => settingsProv.unlinkGoogleDrive(),
                    icon: const Icon(LucideIcons.logOut, size: 18),
                    label: const Text('Disconnect'),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                  ),
              ],
            ),
            if (settingsProv.settings.googleDriveLinked) ...[
              const Divider(height: 48),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Last Cloud Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(
                          settingsProv.settings.lastBackupMillis != null 
                            ? DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(settingsProv.settings.lastBackupMillis!))
                            : 'No backups recorded recently',
                          style: TextStyle(color: context.textMutedColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: settingsProv.isGoogleLoading ? null : () async {
                      final success = await settingsProv.performManualBackup();
                      if (success && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Full Data Folder Backup Success!'), backgroundColor: AppTheme.success));
                      } else if (!success && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Backup Failed: ${settingsProv.googleError ?? 'Unknown Error'}'), 
                          backgroundColor: AppTheme.danger,
                          duration: const Duration(seconds: 5),
                        ));
                      }
                    },
                    icon: settingsProv.isGoogleLoading 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(LucideIcons.uploadCloud, size: 18),
                    label: const Text('Full Backup Now'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: settingsProv.isGoogleLoading ? null : () => _showRestoreDialog(context, settingsProv),
                    icon: const Icon(LucideIcons.downloadCloud, size: 18),
                    label: const Text('Restore from Cloud'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.warning,
                      side: const BorderSide(color: AppTheme.warning),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        SettingsSection(
          title: 'Auto-Backup Automation',
            icon: LucideIcons.calendarClock,
            children: [
              SettingsDropdown<String>(
                title: 'Frequency Strategy',
                value: _autoBackupFreq,
                icon: LucideIcons.calendar,
                items: ['Never', 'Daily', 'Weekly', 'Monthly']
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _autoBackupFreq = val);
                    final updated = settingsProv.settings;
                    updated.autoBackupFrequency = val;
                    settingsProv.save(updated);
                  }
                },
              ),
              if (_autoBackupFreq != 'Never')
                ListTile(
                  leading: const Icon(LucideIcons.clock, size: 20),
                  title: const Text('Scheduled Time', style: TextStyle(fontSize: 14)),
                  subtitle: Text(settingsProv.settings.autoBackupTime ?? 'Select Time', style: TextStyle(color: AppTheme.primary)),
                  trailing: const Icon(LucideIcons.chevronRight, size: 16),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                        hour: int.parse((settingsProv.settings.autoBackupTime ?? '22:00').split(':').first),
                        minute: int.parse((settingsProv.settings.autoBackupTime ?? '22:00').split(':').last),
                      ),
                    );
                    if (time != null) {
                      final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                      final updated = settingsProv.settings;
                      updated.autoBackupTime = timeStr;
                      settingsProv.save(updated);
                      setState(() {});
                    }
                  },
                ),
              const Divider(),
              SettingsDropdown<String>(
                title: 'Trigger Logic',
                value: _autoBackupLogic,
                icon: LucideIcons.cog,
                items: ['At Startup', 'On Close', 'Periodic']
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: (val) => setState(() => _autoBackupLogic = val!),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildInterfaceSection() {
    return SettingsSection(
      title: 'UI Preferences',
      icon: LucideIcons.monitor,
      children: [
        SettingsDropdown<String>(
          title: 'Visual Theme',
          value: _selectedTheme,
          icon: LucideIcons.palette,
          items: const [
            DropdownMenuItem(value: 'system', child: Text('System Preference')),
            DropdownMenuItem(value: 'light', child: Text('Light Mode')),
            DropdownMenuItem(value: 'dark', child: Text('Dark Mode')),
          ],
          onChanged: (val) => setState(() => _selectedTheme = val!),
        ),
        const Divider(),
        SettingsSwitch(
          title: 'Premium Animations',
          subtitle: 'Enable smooth entrance and layout transitions',
          value: _enableAnimations,
          icon: LucideIcons.sparkles,
          onChanged: (val) => setState(() => _enableAnimations = val),
        ),
      ],
    );
  }

  Widget _buildPrintingSection() {
    return Column(
      children: [
        SettingsSection(
          title: 'Invoice Styling',
          icon: LucideIcons.receipt,
          children: [
            SettingsField(controller: _footerCtrl, label: 'Receipt Footer Message', icon: LucideIcons.messageSquare),
            Row(
              children: [
                Expanded(child: SettingsField(controller: _currencyCtrl, label: 'Currency Symbol', icon: LucideIcons.banknote)),
                const SizedBox(width: 16),
                Expanded(
                  child: SettingsField(
                    controller: _taxCtrl, 
                    label: _isCompositionScheme ? 'Tax Rate (%) (Locked by Composition)' : 'Tax Rate (%)', 
                    icon: LucideIcons.percent, 
                    keyboardType: TextInputType.number,
                    enabled: !_isCompositionScheme,
                  ),
                ),
              ],
            ),
          ],
        ),
        SettingsSection(
          title: 'Printer Hardware',
          icon: LucideIcons.printer,
          children: [
            SettingsDropdown<String>(
              title: 'Paper Type',
              value: _paperSize,
              icon: LucideIcons.fileText,
              items: const [
                DropdownMenuItem(value: 'A6', child: Text('A6 (Standard)')),
                DropdownMenuItem(value: 'Letter', child: Text('Letter')),
                DropdownMenuItem(value: 'A4', child: Text('A4')),
                DropdownMenuItem(value: 'Roll80', child: Text('Thermal Roll (80mm)')),
              ],
              onChanged: (val) => setState(() => _paperSize = val!),
            ),
            const Divider(),
            SettingsDropdown<String>(
              title: 'Active Printer',
              value: _printers.any((p) => p.name == _selectedPrinter) ? _selectedPrinter : '',
              icon: LucideIcons.printer,
              items: [
                const DropdownMenuItem(value: '', child: Text('No Printer Selected')),
                ..._printers.map((p) => DropdownMenuItem(value: p.name, child: Text(p.name))),
              ],
              onChanged: (val) => setState(() => _selectedPrinter = val!),
            ),
            const Divider(),
            SettingsSwitch(
              title: 'Direct Mode',
              subtitle: 'Skip print preview and print immediately on checkout',
              value: _autoPrint,
              icon: LucideIcons.zap,
              onChanged: (val) => setState(() => _autoPrint = val),
            ),
            const Divider(),
            SettingsSwitch(
              title: 'Show Batch & Expiry (Retail)',
              subtitle: 'Show Batch number and Expiry date on retail receipts',
              value: _showBatchExpiryRetail,
              icon: LucideIcons.calendar,
              onChanged: (val) => setState(() => _showBatchExpiryRetail = val),
            ),
            const Divider(),
            SettingsSwitch(
              title: 'Show Batch & Expiry (Dispense)',
              subtitle: 'Show Batch number and Expiry date on clinical dispense slips',
              value: _showBatchExpiryClinical,
              icon: LucideIcons.calendar,
              onChanged: (val) => setState(() => _showBatchExpiryClinical = val),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => PrintingService.instance.testPrint(context),
                icon: const Icon(LucideIcons.type, size: 18),
                label: const Text('Send Diagnostic Print'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNetworkingSection() {
    final serverRunning = LocalServerService.instance.isRunning;
    return Column(
      children: [
        SettingsSection(
          title: 'Connection Role',
          icon: LucideIcons.cpu,
          children: [
            SettingsSwitch(
              title: 'Act as Terminal (Client Mode)',
              subtitle: 'Enable this if this PC should connect to a Main Hub PC instead of being the Hub itself.',
              value: _isWindowsClient,
              icon: LucideIcons.monitorSpeaker,
              onChanged: (val) {
                setState(() => _isWindowsClient = val);
                if (val) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('App will restart in Client Mode after saving.'),
                    backgroundColor: AppTheme.warning,
                  ));
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (!_isWindowsClient) ...[
          SettingsSection(
            title: 'Local Hub Server',
            icon: LucideIcons.server,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.activity,
                    color: serverRunning ? AppTheme.success : AppTheme.danger,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    serverRunning ? 'Sync Server: ACTIVE' : 'Sync Server: STOPPED',
                    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingsField(controller: _portCtrl, label: 'Hub Sync Port', icon: LucideIcons.hash, keyboardType: TextInputType.number),
              const Text(
                'Android clients must specify this port to connect to this Hub.',
                style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
              const Divider(height: 48),
              _buildInfoCard(
                'Local Network Address',
                _hubIp ?? 'Finding IP...',
                LucideIcons.wifi,
                'Use this IP in the companion app while on the same Wi-Fi.',
              ),
              const SizedBox(height: 16),
              _buildInfoCard(
                'Cloudflare Tunnel Link',
                CloudflareService.instance.currentUrl ?? 'No active tunnel',
                LucideIcons.globe,
                'Use this URL to connect remotely from anywhere in the world.',
                isLink: true,
              ),
            ],
          ),
        ] else ...[
          SettingsSection(
            title: 'Terminal Status',
            icon: LucideIcons.link,
            children: [
              const Text(
                'This PC is currently acting as a Terminal Client. It will connect to the master Hub for all data.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              _buildInfoCard(
                'Connected Hub IP',
                context.watch<SyncService>().hubIp ?? 'Not Connected',
                LucideIcons.server,
                'The IP address of the main Windows Hub.',
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon, String hint, {bool isLink = false}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primaryLight),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.copy, size: 16),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                },
                tooltip: 'Copy',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isLink ? AppTheme.primary : context.textColor,
              decoration: isLink ? TextDecoration.underline : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(hint, style: TextStyle(fontSize: 12, color: context.textMutedColor)),
        ],
      ),
    );
  }

  Widget _buildInventorySection() {
    return SettingsSection(
      title: 'Threshold Monitoring',
      icon: LucideIcons.alertCircle,
      children: [
        SettingsField(controller: _lowStockCtrl, label: 'Low Stock Level', icon: LucideIcons.alertTriangle, keyboardType: TextInputType.number),
        SettingsField(controller: _nearExpiryCtrl, label: 'Expiry Warning (Days)', icon: LucideIcons.timer, keyboardType: TextInputType.number),
      ],
    );
  }

  Widget _buildDataSection(SettingsProvider settingsProv) {
    return Column(
      children: [
        SettingsSection(
          title: 'Excel Data Exchange',
          icon: LucideIcons.fileUp,
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _exportExcel(),
                    icon: const Icon(LucideIcons.fileOutput),
                    label: const Text('Export Collection'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emerald),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _importExcel(),
                    icon: const Icon(LucideIcons.plusCircle),
                    label: const Text('Import Catalog'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.indigo),
                  ),
                ),
              ],
            ),
          ],
        ),
        SettingsSection(
          title: 'Manual Database Control',
          icon: LucideIcons.hardDrive,
          children: [
            const Text(
              'Perform individual database file operations. Restoring will reset local data.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _backupDatabase(),
                    icon: const Icon(LucideIcons.save),
                    label: const Text('Download .mdb'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _restoreDatabase(),
                    icon: const Icon(LucideIcons.history),
                    label: const Text('Restore from .mdb'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: settingsProv.isGoogleLoading ? null : () async {
                      final path = await settingsProv.exportFullLocalBackup();
                      if (path != null && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Full Backup Saved: ${p.basename(path)}'),
                          backgroundColor: AppTheme.success,
                        ));
                      }
                    },
                    icon: settingsProv.isGoogleLoading 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(LucideIcons.archive),
                    label: const Text('Generate Full System Backup (.zip)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final appSupportDir = await getApplicationSupportDirectory();
                    final backupDir = Directory(p.join(appSupportDir.path, 'backups'));
                    if (await backupDir.exists()) {
                      launchUrl(Uri.file(backupDir.path));
                    } else {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No automated backups created yet.')));
                    }
                  },
                  icon: const Icon(LucideIcons.folder),
                  label: const Text('Open Backup Folder'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Recommended: Includes all database records, patient photos, and prescriptions.',
              style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ],
    );
  }

  // Staff and Doctor sections are now embedded directly via UserManagementWindows and DoctorListWindows

  // --- Core Data Operations ---
  Future<void> _backupDatabase() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dbFile = File('${docDir.path}/objectbox/data.mdb');
      if (!dbFile.existsSync()) throw Exception('Database file missing!');

      String? outputPath = Platform.isWindows ? '${Platform.environment['USERPROFILE']}\\Downloads' : (await getDownloadsDirectory())?.path;
      if (outputPath == null) throw Exception('No Downloads folder found');

      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final backupPath = '$outputPath/mediposs_backup_$timestamp.mdb';
      await dbFile.copy(backupPath);

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Locally saved to Downloads'), backgroundColor: AppTheme.success, behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
    }
  }

  Future<void> _restoreDatabase() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null || result.files.isEmpty) return;
      final selectedFile = File(result.files.single.path!);
      if (!selectedFile.path.endsWith('.mdb')) throw Exception('Invalid .mdb file');

      final docDir = await getApplicationDocumentsDirectory();
      await selectedFile.copy('${docDir.path}/objectbox/data.mdb');

      if (mounted) {
        showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
          title: const Text('Data Restored'),
          content: const Text('Application must restart to finalize database changes.'),
          actions: [ElevatedButton(onPressed: () => SystemNavigator.pop(), child: const Text('Close App'))],
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore failed: $e'), backgroundColor: AppTheme.danger));
    }
  }

  Future<void> _exportExcel() async {
    try {
      final medicines = context.read<InventoryProvider>().medicines;
      if (medicines.isEmpty) return;

      var excel = excel_pkg.Excel.createExcel();
      var sheet = excel['Sheet1'];
      sheet.appendRow(['ID', 'Medicine Name', 'Barcode', 'Category', 'Unit', 'Purchase Price', 'Selling Rate', 'Hub Stock', 'Store Stock', 'Threshold'].map((e) => excel_pkg.TextCellValue(e)).toList());
      for (var med in medicines) {
        sheet.appendRow([
          excel_pkg.IntCellValue(med.id), excel_pkg.TextCellValue(med.name), excel_pkg.TextCellValue(med.barcode), excel_pkg.TextCellValue(med.category),
          excel_pkg.TextCellValue(med.unit), excel_pkg.DoubleCellValue(med.purchasePrice), excel_pkg.DoubleCellValue(med.sellingPrice),
          excel_pkg.IntCellValue(med.mainStock), excel_pkg.IntCellValue(med.storeStock), excel_pkg.IntCellValue(med.lowStockThreshold),
        ]);
      }

      String? outputPath = Platform.isWindows ? '${Platform.environment['USERPROFILE']}\\Downloads' : (await getDownloadsDirectory())?.path;
      if (outputPath == null) throw Exception('No download path');
      final fileBytes = excel.save();
      if (fileBytes != null) {
        File('$outputPath/mediposs_export_${DateTime.now().millisecondsSinceEpoch}.xlsx').writeAsBytesSync(fileBytes);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Excel Exported to Downloads'), backgroundColor: AppTheme.success));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Excel Export Error: $e'), backgroundColor: AppTheme.danger));
    }
  }

  Future<void> _importExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
      if (result == null || result.files.single.path == null) return;
      final file = File(result.files.single.path!);
      var excel = excel_pkg.Excel.decodeBytes(file.readAsBytesSync());
      if (excel.tables.isEmpty) return;
      var table = excel.tables[excel.tables.keys.first]!;
      
      if (!context.mounted) return;
      final inv = context.read<InventoryProvider>();
      int added = 0; int updated = 0;

      bool isTally = false;
      // Scan rows to find "Particulars" to auto-detect Tally exports
      for (int i = 0; i < table.maxRows; i++) {
        final row = table.row(i);
        for (int j = 0; j < row.length; j++) {
          final cellValue = row[j]?.value?.toString().trim().toLowerCase() ?? '';
          if (cellValue == 'particulars') {
            isTally = true;
            break;
          }
        }
        if (isTally) break;
      }

      if (isTally) {
        for (int i = 0; i < table.maxRows; i++) {
          final row = table.row(i);
          if (row.isEmpty) continue;
          final sNoStr = row[0]?.value?.toString().trim() ?? '';
          final isSerial = int.tryParse(sNoStr) != null;
          final nameCell = row[1]?.value?.toString().trim() ?? '';

          if (isSerial && nameCell.isNotEmpty) {
            final barcode = '';
            final category = 'General';
            final unit = 'Pcs';

            final double qtyVal = row.length > 3
                ? (double.tryParse(row[3]?.value?.toString().trim() ?? '') ?? 0.0)
                : 0.0;
            final double rateVal = row.length > 4
                ? (double.tryParse(row[4]?.value?.toString().trim() ?? '') ?? 0.0)
                : 0.0;

            final mainStock = qtyVal.round();
            final storeStock = 0;
            final purchasePrice = rateVal;
            final sellingPrice = rateVal;

            final existing = inv.medicines
                .where((m) => m.name.toLowerCase() == nameCell.toLowerCase())
                .firstOrNull;

            if (existing != null) {
              existing
                ..category = category
                ..unit = unit
                ..purchasePrice = purchasePrice > 0 ? purchasePrice : existing.purchasePrice
                ..sellingPrice = sellingPrice > 0 ? sellingPrice : existing.sellingPrice;

              inv.updateMedicine(existing);

              if (mainStock > 0) {
                inv.addBatchStock(
                  {existing.id: mainStock},
                  storeUpdates: {existing.id: storeStock},
                  batchNo: 'IMPORT-${DateTime.now().millisecondsSinceEpoch}',
                  expiryDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  note: 'Imported from Excel (Tally)',
                );
              }
              updated++;
            } else {
              final newMed = Medicine(
                name: nameCell,
                barcode: barcode,
                category: category,
                unit: unit,
                purchasePrice: purchasePrice,
                sellingPrice: sellingPrice,
                mainStock: 0,
                storeStock: 0,
                lowStockThreshold: 10,
              );
              inv.addMedicine(newMed);

              if (mainStock > 0) {
                inv.addBatchStock(
                  {newMed.id: mainStock},
                  storeUpdates: {newMed.id: storeStock},
                  batchNo: 'IMPORT-${DateTime.now().millisecondsSinceEpoch}',
                  expiryDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  note: 'Imported from Excel (Tally)',
                );
              }
              added++;
            }
          }
        }
      } else {
        int headerRowIndex = -1;
        Map<String, int> colMap = {};

        // 1. Find the header row
        for (int i = 0; i < table.maxRows; i++) {
          final row = table.row(i);
          for (int j = 0; j < row.length; j++) {
            final cellValue =
                row[j]?.value?.toString().trim().toLowerCase() ?? '';
            if (cellValue == 'medicine name' ||
                cellValue == 'item name' ||
                cellValue == 'product name' ||
                cellValue == 'itemname') {
              headerRowIndex = i;
              break;
            }
          }
          if (headerRowIndex != -1) break;
        }

        if (headerRowIndex == -1) {
          // If no custom header matches, default to standard column indices as fallback
          for (int i = 1; i < table.maxRows; i++) {
            final row = table.row(i);
            final name = row[1]?.value?.toString() ?? '';
            if (name.isEmpty) continue;
            
            final existing = inv.medicines.where((m) => m.name.toLowerCase() == name.toLowerCase()).firstOrNull;
            if (existing != null) {
              inv.updateMedicine(Medicine(
                id: existing.id, 
                name: name, 
                purchasePrice: existing.purchasePrice,
                sellingPrice: existing.sellingPrice,
                category: 'Imported', 
                synced: false
              ));
              updated++;
            } else {
              inv.addMedicine(Medicine(
                name: name, 
                purchasePrice: 0.0,
                sellingPrice: 0.0,
                category: 'Imported'
              ));
              added++;
            }
          }
        } else {
          // Map columns
          final headerRow = table.row(headerRowIndex);
          for (int j = 0; j < headerRow.length; j++) {
            final title =
                headerRow[j]?.value?.toString().trim().toLowerCase() ?? '';
            if (title.isNotEmpty) {
              colMap[title] = j;
            }
          }

          // Helper to get index matching a list of possible names
          int getColIdx(List<String> possibleNames) {
            for (final name in possibleNames) {
              if (colMap.containsKey(name)) return colMap[name]!;
            }
            return -1;
          }

          final nameIdx = getColIdx(['medicine name', 'item name', 'product name']);
          final barcodeIdx = getColIdx(['barcode']);
          final categoryIdx = getColIdx(['category']);
          final unitIdx = getColIdx(['unit']);
          final purchasePriceIdx = getColIdx(['purchase price', 'cost']);
          final sellingPriceIdx =
              getColIdx(['selling price', 'selling rate', 'rate', 'price']);
          final mainStockIdx = getColIdx(['main hub stock', 'main stock']);
          final storeStockIdx =
              getColIdx(['store front stock', 'store stock', 'quantity', 'qty']);
          final lowStockIdx = getColIdx(['low stock threshold', 'threshold']);

          // Process rows
          for (int i = headerRowIndex + 1; i < table.maxRows; i++) {
            final row = table.row(i);

            String getCellStr(int idx, String def) =>
                (idx != -1 && idx < row.length)
                    ? (row[idx]?.value?.toString().trim() ?? def)
                    : def;
            double getCellDbl(int idx, double def) => (idx != -1 &&
                    idx < row.length)
                ? (double.tryParse(row[idx]?.value?.toString().trim() ?? '') ?? def)
                : def;
            int getCellInt(int idx, int def) => (idx != -1 && idx < row.length)
                ? (int.tryParse(row[idx]?.value?.toString().trim() ?? '') ?? def)
                : def;

            final nameCell = getCellStr(nameIdx, '');
            if (nameCell.isEmpty) continue; // Skip empty rows

            final barcode = getCellStr(barcodeIdx, '');
            final category = getCellStr(categoryIdx, 'General');
            final unit = getCellStr(unitIdx, 'Pcs');

            final purchasePrice = getCellDbl(purchasePriceIdx, 0.0);
            final sellingPrice = getCellDbl(sellingPriceIdx, 0.0);

            final mainStock = getCellInt(mainStockIdx, 0);
            final storeStock = getCellInt(storeStockIdx, 0);
            final lowStock = getCellInt(lowStockIdx, 10);

            // Check if medicine exists
            final existing = inv.medicines
                .where((m) => m.name.toLowerCase() == nameCell.toLowerCase())
                .firstOrNull;

            if (existing != null) {
              // Update existing metadata
              existing
                ..barcode = barcode.isNotEmpty ? barcode : existing.barcode
                ..category = category
                ..unit = unit
                ..purchasePrice =
                    purchasePrice > 0 ? purchasePrice : existing.purchasePrice
                ..sellingPrice =
                    sellingPrice > 0 ? sellingPrice : existing.sellingPrice
                ..lowStockThreshold = lowStock;

              inv.updateMedicine(existing);

              // If stock is provided in Excel, add it as a new batch to avoid total drift
              if (mainStock > 0 || storeStock > 0) {
                inv.addBatchStock(
                  {existing.id: mainStock},
                  storeUpdates: {existing.id: storeStock},
                  batchNo: 'IMPORT-${DateTime.now().millisecondsSinceEpoch}',
                  expiryDate: DateTime.now()
                      .add(const Duration(days: 365 * 2)), // 2 year default
                  note: 'Imported from Excel',
                );
              }
              updated++;
            } else {
              // Add new
              final newMed = Medicine(
                name: nameCell,
                barcode: barcode,
                category: category,
                unit: unit,
                purchasePrice: purchasePrice,
                sellingPrice: sellingPrice,
                mainStock: 0, // Will be updated by batch
                storeStock: 0,
                lowStockThreshold: lowStock,
              );
              inv.addMedicine(newMed);

              if (mainStock > 0 || storeStock > 0) {
                inv.addBatchStock(
                  {newMed.id: mainStock},
                  storeUpdates: {newMed.id: storeStock},
                  batchNo: 'IMPORT-${DateTime.now().millisecondsSinceEpoch}',
                  expiryDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  note: 'Imported from Excel',
                );
              }
              added++;
            }
          }
        }
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import: $added Added, $updated Updated'), backgroundColor: AppTheme.success));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e'), backgroundColor: AppTheme.danger));
    }
  }

  Future<void> _showRestoreDialog(BuildContext context, SettingsProvider settingsProv) async {
    final backups = await settingsProv.fetchCloudBackups();
    if (!mounted) return;

    if (backups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No backups found on Google Drive.'),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Backup to Restore'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'WARNING: Restoring will overwrite all current local data. A safety backup of your current data will be created automatically.',
                style: TextStyle(color: AppTheme.danger, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: backups.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final b = backups[index];
                    final date = b.createdTime != null 
                        ? DateFormat('dd MMM yyyy, hh:mm a').format(b.createdTime!.toLocal())
                        : 'Unknown Date';
                    return ListTile(
                      title: Text(b.name ?? 'Untitled Backup'),
                      subtitle: Text('Created: $date'),
                      trailing: const Icon(LucideIcons.chevronRight, size: 16),
                      onTap: () {
                        Navigator.pop(ctx);
                        _confirmAndRestore(context, settingsProv, b.id!, b.name!);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
  }

  Future<void> _confirmAndRestore(BuildContext context, SettingsProvider settingsProv, String fileId, String fileName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Restoration'),
        content: Text('Are you absolutely sure you want to restore "$fileName"?\n\nThe app will CLOSE automatically after the restoration is complete.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('RESTORE & CLOSE'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final success = await settingsProv.restoreFromCloud(fileId);
      if (success && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Restore Complete'),
            content: const Text('The data has been restored successfully. The application will now close. Please re-open it manually.'),
            actions: [
              ElevatedButton(
                onPressed: () => exit(0),
                child: const Text('CHAO!'),
              ),
            ],
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Restore Failed: ${settingsProv.googleError}'),
          backgroundColor: AppTheme.danger,
        ));
      }
    }
  }
}

class _NavModel {
  final IconData icon;
  final String label;
  final Color color;
  _NavModel(this.icon, this.label, this.color);
}
