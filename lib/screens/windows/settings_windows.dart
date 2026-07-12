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
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/services/cloudflare_service.dart';
import '../../shared/services/sync_service.dart';
import '../../shared/services/ota_update_service.dart';

import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/navigation_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../shared/services/local_server_service.dart';
import '../../shared/services/printing_service.dart';
import '../../shared/models/doctor.dart';
import '../../shared/services/objectbox_service.dart';
import '../../shared/services/firebase_sync_service.dart';
import '../../objectbox.g.dart';
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as excel_pkg;
import '../../shared/providers/inventory_provider.dart';
import '../../shared/models/medicine.dart';
import '../../shared/services/audit_export_service.dart';
import '../../shared/services/backup_restore_service.dart';
import 'user_management_windows.dart';
import 'opd/doctor_list_windows.dart';
import 'widgets/settings_widgets.dart';
import '../../shared/services/data_population_service.dart';
import 'settings/sections/identity_printing_section.dart';
import 'settings/sections/interface_network_inventory_section.dart';
import 'settings/sections/data_control_section.dart';

class SettingsWindows extends StatefulWidget {
  const SettingsWindows({super.key});

  @override
  State<SettingsWindows> createState() => _SettingsWindowsState();
}

class _SettingsWindowsState extends State<SettingsWindows> {
  late final TextEditingController _storeNameCtrl;
  late final TextEditingController _shopIdCtrl;
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
  bool _showOpdIdInPrint = true;
  bool _firebaseEnabled = true;
  bool _firebaseMirrorEnabled = false;
  bool _firebaseSummaryEnabled = false;
  bool _googleDriveSyncEnabled = true;
  int _auditRetentionDays = 90;
  List<Doctor> _doctors = [];
  int? _selectedDefaultDoctorId;

  @override
  void initState() {
    super.initState();
    _loadHubIp();
    // ...
    final s = context.read<SettingsProvider>().settings;
    _storeNameCtrl = TextEditingController(text: s.storeName);
    _shopIdCtrl = TextEditingController(text: s.shopId);
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
    _showOpdIdInPrint = s.showOpdIdInPrint;
    _firebaseEnabled = s.firebaseEnabled;
    _firebaseMirrorEnabled = s.connectionMode == 'firebase';
    _firebaseSummaryEnabled = s.connectionMode == 'summary';
    _googleDriveSyncEnabled = s.googleDriveSyncEnabled;
    _auditRetentionDays = s.auditRetentionDays;
    _selectedDefaultDoctorId = s.defaultDoctorId;

    _loadPrinters();
    _loadDoctors();
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

  void _loadDoctors() {
    try {
      final docBox = ObjectBoxService.instance.store.box<Doctor>();
      final docs = docBox.query(Doctor_.isActive.equals(true)).build().find();
      setState(() {
        _doctors = docs;
      });
    } catch (e) {
      debugPrint('Error loading doctors: $e');
    }
  }

  Future<void> _save() async {
    final settingsProv = context.read<SettingsProvider>();
    final s = settingsProv.settings;
    s
      ..storeName = _storeNameCtrl.text
      ..shopId = _shopIdCtrl.text
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
      ..showBatchExpiryInClinicalPrint = _showBatchExpiryClinical
      ..showOpdIdInPrint = _showOpdIdInPrint
      ..firebaseEnabled = _firebaseEnabled
      ..connectionMode = _firebaseMirrorEnabled ? 'firebase' : (_firebaseSummaryEnabled ? 'summary' : 'auto')
      ..googleDriveSyncEnabled = _googleDriveSyncEnabled
      ..auditRetentionDays = _auditRetentionDays
      ..defaultDoctorId = _selectedDefaultDoctorId;

    final wasClient = settingsProv.settings.isWindowsClient;
    settingsProv.save(s);
    LocalServerService.instance.broadcast({'event': 'settings_updated'});

    if (wasClient != _isWindowsClient) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isTerminalMode', _isWindowsClient);
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Restart Required'),
          content: const Text(
              'Changing between Hub and Terminal mode requires a full application restart to apply network changes.'),
          actions: [
            ElevatedButton(
              onPressed: () async {
                await Future.delayed(const Duration(milliseconds: 1000));
                exit(0);
              },
              child: const Text('Restart Now'),
            ),
          ],
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Settings saved successfully'),
      backgroundColor: AppTheme.success,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.all(20),
    ));
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _shopIdCtrl.dispose();
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
      _NavModel(LucideIcons.refreshCw, 'Updates', Colors.pink),
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
              const Text(
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
        return StoreDetailsSection(
          storeNameCtrl: _storeNameCtrl,
          addressCtrl: _addressCtrl,
          phoneCtrl: _phoneCtrl,
          gstCtrl: _gstCtrl,
          clinicNameCtrl: _clinicNameCtrl,
          clinicAddressCtrl: _clinicAddressCtrl,
          clinicPhoneCtrl: _clinicPhoneCtrl,
          clinicRegCtrl: _clinicRegCtrl,
          taxCtrl: _taxCtrl,
          isCompositionScheme: _isCompositionScheme,
          selectedDefaultDoctorId: _selectedDefaultDoctorId,
          doctors: _doctors,
          onCompositionSchemeChanged: (val) => setState(() => _isCompositionScheme = val),
          onDefaultDoctorChanged: (val) => setState(() => _selectedDefaultDoctorId = val),
        );
      case 'Printing':
        return PrintingSection(
          footerCtrl: _footerCtrl,
          currencyCtrl: _currencyCtrl,
          taxCtrl: _taxCtrl,
          paperSize: _paperSize,
          selectedPrinter: _selectedPrinter,
          autoPrint: _autoPrint,
          showBatchExpiryRetail: _showBatchExpiryRetail,
          showBatchExpiryClinical: _showBatchExpiryClinical,
          showOpdIdInPrint: _showOpdIdInPrint,
          printers: _printers,
          isCompositionScheme: _isCompositionScheme,
          onPaperSizeChanged: (val) => setState(() => _paperSize = val),
          onPrinterChanged: (val) => setState(() => _selectedPrinter = val),
          onAutoPrintChanged: (val) => setState(() => _autoPrint = val),
          onShowBatchExpiryRetailChanged: (val) => setState(() => _showBatchExpiryRetail = val),
          onShowBatchExpiryClinicalChanged: (val) => setState(() => _showBatchExpiryClinical = val),
          onShowOpdIdInPrintChanged: (val) => setState(() => _showOpdIdInPrint = val),
        );
      case 'Interface':
        return InterfaceSection(
          selectedTheme: _selectedTheme,
          enableAnimations: _enableAnimations,
          onThemeChanged: (val) => setState(() => _selectedTheme = val),
          onAnimationsChanged: (val) => setState(() => _enableAnimations = val),
        );
      case 'Cloud Sync':
        return CloudSection(
          settingsProv: settingsProv,
          googleDriveSyncEnabled: _googleDriveSyncEnabled,
          firebaseEnabled: _firebaseEnabled,
          firebaseMirrorEnabled: _firebaseMirrorEnabled,
          firebaseSummaryEnabled: _firebaseSummaryEnabled,
          shopIdCtrl: _shopIdCtrl,
          autoBackupFreq: _autoBackupFreq,
          autoBackupLogic: _autoBackupLogic,
          onGoogleDriveSyncEnabledChanged: (val) => setState(() => _googleDriveSyncEnabled = val),
          onFirebaseEnabledChanged: (val) => setState(() => _firebaseEnabled = val),
          onFirebaseMirrorEnabledChanged: (val) => setState(() => _firebaseMirrorEnabled = val),
          onFirebaseSummaryEnabledChanged: (val) => setState(() => _firebaseSummaryEnabled = val),
          onAutoBackupFreqChanged: (val) => setState(() => _autoBackupFreq = val),
          onAutoBackupLogicChanged: (val) => setState(() => _autoBackupLogic = val),
          onSyncTodayNow: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Syncing today's data to cloud..."), duration: Duration(seconds: 2)),
            );
            await FirebaseSyncService.instance.uploadTodaysDataToCloud();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Today's data synced successfully!"), backgroundColor: AppTheme.success),
              );
            }
          },
          onShowRestoreDialog: () => _showRestoreDialog(context, settingsProv),
          onSelectBackupTime: () async {
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
        );
      case 'Networking':
        return NetworkingSection(
          isWindowsClient: _isWindowsClient,
          portCtrl: _portCtrl,
          hubIp: _hubIp,
          syncService: context.watch<SyncService>(),
          onWindowsClientChanged: (val) => setState(() => _isWindowsClient = val),
        );
      case 'Inventory':
        return InventorySection(
          lowStockCtrl: _lowStockCtrl,
          nearExpiryCtrl: _nearExpiryCtrl,
        );
      case 'Data':
        return DataSection(
          auditRetentionDays: _auditRetentionDays,
          onAuditRetentionDaysChanged: (val) => setState(() => _auditRetentionDays = val),
          onExportExcel: _exportExcel,
          onImportExcel: _importExcel,
          onBackupDatabase: _backupDatabase,
          onRestoreDatabase: _restoreDatabase,
          onBackupJsonGranular: _backupJsonGranular,
          onRestoreJsonGranular: _restoreJsonGranular,
          onGenerateAuditReport: () async {
            String? defaultDir;
            try {
              defaultDir = Platform.isWindows
                  ? '${Platform.environment['USERPROFILE']}\\Downloads'
                  : (await getDownloadsDirectory())?.path;
            } catch (_) {}

            final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
            final fileName = 'MediPoss_Audit_Report_$timestamp.xlsx';

            final outputPath = await FilePicker.platform.saveFile(
              dialogTitle: 'Save Audit Report',
              fileName: fileName,
              initialDirectory: defaultDir,
              type: FileType.custom,
              allowedExtensions: ['xlsx'],
            );

            if (outputPath == null) return; // User cancelled

            final file = await AuditExportService.generateAuditReport(customPath: outputPath);
            if (file != null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Audit Report Saved to: ${file.path}'),
                backgroundColor: AppTheme.success,
              ));
            } else if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Failed to generate Audit Report'),
                backgroundColor: AppTheme.danger,
              ));
            }
          },
          onSeedCustomDemoData: _seedCustomDemoData,
        );
      case 'Updates':
        return const UpdatesSection();
      case 'Staff':
        return const UserManagementWindows(isEmbedded: true);
      case 'Doctors':
        return const DoctorListWindows(isEmbedded: true);
      default:
        return const SizedBox();
    }
  }

  // Staff and Doctor sections are now embedded directly via UserManagementWindows and DoctorListWindows

  Future<void> _seedCustomDemoData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seed 6-Month Demo Data?'),
        content: const Text(
          'This will populate the database with a high volume of demo data (approx. 5,400 patients, 9,000 sales transactions/dispenses, and 1,800 stock transfers) across the last 180 days. This process may take a few seconds.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
            child: const Text('Seed Data'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.purple),
            SizedBox(width: 24),
            Expanded(
              child: Text(
                'Generating and writing data to local ObjectBox. Please wait...',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final seeder = DataPopulationService();
      await seeder.populateCustomDataFor6Months();
      
      if (mounted) Navigator.pop(context);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Data Seeded Successfully'),
            content: const Text(
              'Successfully seeded patients, dispenses, sales, and stock transfers for the last 6 months.\n\nPlease restart the application to refresh all providers and cache lists.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  exit(0);
                },
                child: const Text('Exit App Now'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Seeding failed: $e'),
          backgroundColor: AppTheme.danger,
        ));
      }
    }
  }

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

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Locally saved to Downloads'), backgroundColor: AppTheme.success, behavior: SnackBarBehavior.floating));
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

  Future<void> _backupJsonGranular() async {
    try {
      final file = await BackupRestoreService.exportToJsonBackup();
      if (file != null && mounted) {
        String? defaultDir;
        try {
          defaultDir = Platform.isWindows
              ? '${Platform.environment['USERPROFILE']}\\Downloads'
              : (await getDownloadsDirectory())?.path;
        } catch (_) {}

        final fileName = p.basename(file.path);
        final outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Granular Backup',
          fileName: fileName,
          initialDirectory: defaultDir,
          type: FileType.custom,
          allowedExtensions: ['zip'],
        );

        if (outputPath != null) {
          await file.copy(outputPath);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Granular Backup Saved to: $outputPath'),
              backgroundColor: AppTheme.success,
            ));
          }
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e'), backgroundColor: AppTheme.danger));
    }
  }

  Future<void> _restoreJsonGranular() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null || result.files.isEmpty) return;

      final selectedFile = File(result.files.single.path!);
      if (!selectedFile.path.endsWith('.zip')) {
        throw Exception('Invalid file! Please select a .zip JSON backup.');
      }

      bool restInventory = true;
      bool restSales = true;
      bool restOpd = true;
      bool restSettings = true;

      if (!mounted) return;
      final config = await showDialog<RestoreConfig>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('Granular Restore Options'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Select which modules to restore.\nWARNING: Will replace existing data.', style: TextStyle(fontSize: 13, color: AppTheme.danger)),
                      CheckboxListTile(title: const Text('Inventory'), value: restInventory, onChanged: (v) => setState(() => restInventory = v!)),
                      CheckboxListTile(title: const Text('Sales'), value: restSales, onChanged: (v) => setState(() => restSales = v!)),
                      CheckboxListTile(title: const Text('OPD/Patients'), value: restOpd, onChanged: (v) => setState(() => restOpd = v!)),
                      CheckboxListTile(title: const Text('Settings'), value: restSettings, onChanged: (v) => setState(() => restSettings = v!)),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, RestoreConfig(inventory: restInventory, salesHistory: restSales, opd: restOpd, settingsUsers: restSettings)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                    child: const Text('RESTORE'),
                  ),
                ],
              );
            }
          );
        },
      );

      if (config != null) {
        await BackupRestoreService.importFromJsonBackup(selectedFile, config);
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Restore Complete'),
              content: const Text('Data restored successfully. Please restart app.'),
              actions: [
                ElevatedButton(onPressed: () => SystemNavigator.pop(), child: const Text('Exit App')),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e'), backgroundColor: AppTheme.danger));
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
      final actor = context.read<AuthProvider>().currentUser;
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
            const barcode = '';
            const category = 'General';
            const unit = 'Pcs';

            final double qtyVal = row.length > 3
                ? (double.tryParse(row[3]?.value?.toString().trim() ?? '') ?? 0.0)
                : 0.0;
            final double rateVal = row.length > 4
                ? (double.tryParse(row[4]?.value?.toString().trim() ?? '') ?? 0.0)
                : 0.0;

            final mainStock = qtyVal.round();
            const storeStock = 0;
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

              inv.updateMedicine(existing, actor: actor);

              if (mainStock > 0) {
                inv.addBatchStock(
                  {existing.id: mainStock},
                  storeUpdates: {existing.id: storeStock},
                  batchNo: 'IMPORT-${DateTime.now().millisecondsSinceEpoch}',
                  expiryDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  note: 'Imported from Excel (Tally)',
                  actor: actor,
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
              inv.addMedicine(newMed, actor: actor);

              if (mainStock > 0) {
                inv.addBatchStock(
                  {newMed.id: mainStock},
                  storeUpdates: {newMed.id: storeStock},
                  batchNo: 'IMPORT-${DateTime.now().millisecondsSinceEpoch}',
                  expiryDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  note: 'Imported from Excel (Tally)',
                  actor: actor,
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

              inv.updateMedicine(existing, actor: actor);

              // If stock is provided in Excel, add it as a new batch to avoid total drift
              if (mainStock > 0 || storeStock > 0) {
                inv.addBatchStock(
                  {existing.id: mainStock},
                  storeUpdates: {existing.id: storeStock},
                  batchNo: 'IMPORT-${DateTime.now().millisecondsSinceEpoch}',
                  expiryDate: DateTime.now()
                      .add(const Duration(days: 365 * 2)), // 2 year default
                  note: 'Imported from Excel',
                  actor: actor,
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
              inv.addMedicine(newMed, actor: actor);

              if (mainStock > 0 || storeStock > 0) {
                inv.addBatchStock(
                  {newMed.id: mainStock},
                  storeUpdates: {newMed.id: storeStock},
                  batchNo: 'IMPORT-${DateTime.now().millisecondsSinceEpoch}',
                  expiryDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  note: 'Imported from Excel',
                  actor: actor,
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
    bool restInventory = true;
    bool restSales = true;
    bool restOpd = true;
    bool restSettings = true;

    final config = await showDialog<RestoreConfig>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Granular Restore Options'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Select which modules to restore from "$fileName".\n\nWARNING: Restored modules will replace existing local data for that module.',
                      style: const TextStyle(fontSize: 13, color: AppTheme.danger),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      title: const Text('Inventory & Stock Transfers'),
                      value: restInventory,
                      onChanged: (v) => setState(() => restInventory = v!),
                    ),
                    CheckboxListTile(
                      title: const Text('Sales History'),
                      value: restSales,
                      onChanged: (v) => setState(() => restSales = v!),
                    ),
                    CheckboxListTile(
                      title: const Text('OPD, Patients & Prescriptions'),
                      value: restOpd,
                      onChanged: (v) => setState(() => restOpd = v!),
                    ),
                    CheckboxListTile(
                      title: const Text('Settings & Users'),
                      value: restSettings,
                      onChanged: (v) => setState(() => restSettings = v!),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx, RestoreConfig(
                      inventory: restInventory,
                      salesHistory: restSales,
                      opd: restOpd,
                      settingsUsers: restSettings,
                    ));
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                  child: const Text('RESTORE SELECTED'),
                ),
              ],
            );
          }
        );
      },
    );

    if (config != null && mounted) {
      final success = await settingsProv.restoreFromCloud(fileId, config: config);
      if (success && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Restore Complete'),
            content: const Text('The selected data has been restored successfully. The application will now close. Please re-open it manually.'),
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
