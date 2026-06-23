import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/navigation_provider.dart';
import '../../shared/models/app_user.dart';
import '../../shared/services/sync_service.dart';
import '../../shared/services/firebase_sync_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shop_selection_dialog.dart';
import '../../shared/services/local_server_service.dart';
import '../../shared/services/printing_service.dart';
import '../../shared/services/audit_export_service.dart';
import '../../shared/services/backup_restore_service.dart';
import '../../shared/models/doctor.dart';
import '../../shared/services/objectbox_service.dart';
import '../../objectbox.g.dart';
import 'package:printing/printing.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import '../user_management_screen.dart';
import '../opd/doctor_list_screen.dart';
import '../../shared/services/ota_update_service.dart';
import '../../shared/services/subscription_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:math' as math;

class SettingsAndroid extends StatefulWidget {
  const SettingsAndroid({super.key});

  @override
  State<SettingsAndroid> createState() => _SettingsAndroidState();
}

class _SettingsAndroidState extends State<SettingsAndroid> {
  late final TextEditingController _storeNameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _gstCtrl;
  late final TextEditingController _footerCtrl;
  late final TextEditingController _taxCtrl;
  late final TextEditingController _currencyCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _clinicNameCtrl;
  late final TextEditingController _clinicAddressCtrl;
  late final TextEditingController _clinicPhoneCtrl;
  late final TextEditingController _clinicRegCtrl;
  final _settingsKeyCtrl = TextEditingController();
  bool _isActivatingInSettings = false;
  String _settingsActivationErr = '';

  String _selectedTheme = 'system';
  List<Printer> _printers = [];
  String _selectedPrinter = '';
  bool _autoPrint = false;
  String _paperSize = 'A6';
  List<DisplayMode> _displayModes = [];
  double _selectedFPS = -1.0;
  String _connectionMode = 'auto';
  String _cloudflareUrl = '';
  bool _isFetchingHubStatus = false;
  bool _isCompositionScheme = false;
  bool _showBatchExpiryRetail = true;
  bool _showBatchExpiryClinical = true;
  bool _showOpdIdInPrint = true;
  int _auditRetentionDays = 90;
  List<Doctor> _doctors = [];
  int? _selectedDefaultDoctorId;
  bool _isWindowsClient = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>().settings;
    _storeNameCtrl = TextEditingController(text: s.storeName);
    _addressCtrl = TextEditingController(text: s.storeAddress);
    _phoneCtrl = TextEditingController(text: s.storePhone);
    _gstCtrl = TextEditingController(text: s.gstNumber);
    _footerCtrl = TextEditingController(text: s.receiptFooterMessage);
    _taxCtrl = TextEditingController(text: '${s.taxRate}');
    _currencyCtrl = TextEditingController(text: s.currencySymbol);
    _portCtrl = TextEditingController(text: '${s.serverPort}');
    _clinicNameCtrl = TextEditingController(text: s.clinicName ?? 'MediPoss Clinic');
    _clinicAddressCtrl = TextEditingController(text: s.clinicAddress ?? '');
    _clinicPhoneCtrl = TextEditingController(text: s.clinicPhone ?? '');
    _clinicRegCtrl = TextEditingController(text: s.clinicRegNo ?? '');
    _selectedTheme = ['system', 'light', 'dark'].contains(s.themeMode)
        ? s.themeMode
        : 'system';

    _selectedPrinter = s.defaultPrinterName;
    _autoPrint = s.autoPrintReceipt;
    _paperSize = s.receiptPaperSize;
    _selectedFPS = s.preferredRefreshRate;
    _connectionMode = s.connectionMode;
    _cloudflareUrl = s.cloudflareUrl;
    _isCompositionScheme = s.isCompositionScheme;
    _showBatchExpiryRetail = s.showBatchExpiryInRetailPrint;
    _showBatchExpiryClinical = s.showBatchExpiryInClinicalPrint;
    _showOpdIdInPrint = s.showOpdIdInPrint;
    _auditRetentionDays = s.auditRetentionDays;
    _selectedDefaultDoctorId = s.defaultDoctorId;
    _isWindowsClient = s.isWindowsClient;

    _loadPrinters();
    _loadDisplayModes();
    _fetchHubStatus();
    _loadDoctors();
  }

  Future<void> _fetchHubStatus() async {
    if (!mounted) return;
    setState(() => _isFetchingHubStatus = true);
    try {
      final status = await FirebaseSyncService.instance.getHubStatus();
      if (status != null && mounted) {
        setState(() {
          _cloudflareUrl = status['cloudflareUrl'] ?? _cloudflareUrl;
        });
      }
    } catch (e) {
      debugPrint('Error fetching hub status: $e');
    } finally {
      if (mounted) setState(() => _isFetchingHubStatus = false);
    }
  }

  Future<void> _loadDisplayModes() async {
    if (Platform.isAndroid) {
      try {
        final modes = await FlutterDisplayMode.supported;
        if (mounted) {
          setState(() {
            _displayModes = modes;
          });
        }
      } catch (e) {
        debugPrint('Failed to load display modes: $e');
      }
    }
  }

  Future<void> _loadPrinters() async {
    final printers = await Printing.listPrinters();
    if (mounted) {
      setState(() {
        _printers = printers.where((p) => p.isAvailable).toList();
        if (_selectedPrinter.isNotEmpty &&
            !_printers.any((p) => p.name == _selectedPrinter)) {
          // If saved printer is no longer available
          _selectedPrinter = '';
        }
      });
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

  void _save() {
    final settingsProv = context.read<SettingsProvider>();
    final s = settingsProv.settings;
    final wasClient = s.isWindowsClient;

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
      ..serverPort = int.tryParse(_portCtrl.text) ?? 8080
      ..preferredRefreshRate = _selectedFPS
      ..connectionMode = _connectionMode
      ..cloudflareUrl = _cloudflareUrl
      ..clinicName = _clinicNameCtrl.text
      ..clinicAddress = _clinicAddressCtrl.text
      ..clinicPhone = _clinicPhoneCtrl.text
      ..clinicRegNo = _clinicRegCtrl.text
      ..isCompositionScheme = _isCompositionScheme
      ..showBatchExpiryInRetailPrint = _showBatchExpiryRetail
      ..showBatchExpiryInClinicalPrint = _showBatchExpiryClinical
      ..showOpdIdInPrint = _showOpdIdInPrint
      ..auditRetentionDays = _auditRetentionDays
      ..defaultDoctorId = _selectedDefaultDoctorId
      ..isWindowsClient = _isWindowsClient;

    settingsProv.save(s, syncService: context.read<SyncService>());

    if (wasClient != _isWindowsClient) {
      SharedPreferences.getInstance().then((prefs) async {
        await prefs.setBool('isTerminalMode', _isWindowsClient);
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Restart Required'),
              content: const Text(
                  'Changing between Standalone Hub and Companion Terminal mode requires a full application restart to apply database locks and server configuration.'),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    exit(0);
                  },
                  child: const Text('Close App'),
                ),
              ],
            ),
          );
        }
      });
      return;
    }

    // Apply FPS immediately on Android
    if (Platform.isAndroid) {
      _applyFPS(_selectedFPS);
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('✅ Settings saved'),
      backgroundColor: AppTheme.success,
    ));
  }

  Future<void> _applyFPS(double fps) async {
    try {
      if (fps <= 0.0) {
        await FlutterDisplayMode.setHighRefreshRate();
      } else {
        final modes = await FlutterDisplayMode.supported;
        final mode = modes.firstWhere(
          (m) => m.refreshRate.toStringAsFixed(1) == fps.toStringAsFixed(1),
          orElse: () => modes.first,
        );
        await FlutterDisplayMode.setPreferredMode(mode);
      }
    } catch (e) {
      debugPrint('Error applying FPS: $e');
    }
  }

  @override
  void dispose() {
    _settingsKeyCtrl.dispose();
    super.dispose();
  }

  Widget _tierPriceBadge(String planName, String price, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$planName: $price',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _activateKeyInSettings() async {
    final key = _settingsKeyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _settingsActivationErr = 'Please enter a key');
      return;
    }

    setState(() {
      _isActivatingInSettings = true;
      _settingsActivationErr = '';
    });

    final success = await SubscriptionService.instance.activateLicense(key);

    if (mounted) {
      setState(() {
        _isActivatingInSettings = false;
        if (success) {
          _settingsKeyCtrl.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('MediPoss Activated successfully!'), backgroundColor: AppTheme.success),
          );
        } else {
          _settingsActivationErr = 'Invalid key. Check internet & try again.';
        }
      });
    }
  }

  Widget _buildLicensingSection(BuildContext context) {
    final sub = context.watch<SubscriptionService>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    String tierName = 'Free Tier';
    Color badgeColor = Colors.grey;
    if (sub.currentTier == UserTier.pro) {
      tierName = 'Pro Plan';
      badgeColor = AppTheme.primary;
    } else if (sub.currentTier == UserTier.enterprise) {
      tierName = 'Enterprise Plan';
      badgeColor = AppTheme.emerald;
    }

    final String expiryText = sub.licenseExpiry != null
        ? DateFormat('dd MMM yyyy').format(sub.licenseExpiry!)
        : 'Never (Free Mode)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: badgeColor.withOpacity(0.5)),
              ),
              child: Text(
                tierName,
                style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                sub.licenseKey.isNotEmpty 
                    ? 'Key: ${sub.licenseKey.substring(0, math.min(10, sub.licenseKey.length))}...'
                    : 'No License Key Activated',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'License Expiration: $expiryText',
          style: TextStyle(color: context.textMutedColor, fontSize: 12),
        ),
        const Divider(height: 24),
        const Text(
          'Activate New Key',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _settingsKeyCtrl,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Enter Activation Key',
                  prefixIcon: const Icon(Icons.vpn_key_rounded),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _isActivatingInSettings ? null : _activateKeyInSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isActivatingInSettings
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Activate', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        if (_settingsActivationErr.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _settingsActivationErr,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
        const Divider(height: 32),
        if (sub.currentTier != UserTier.enterprise && sub.upiId.isNotEmpty) ...[
          const Text(
            'Upgrade to Pro or Enterprise Plan',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan to pay & message admin with receipt to get your license key instantly.',
            style: TextStyle(color: context.textMutedColor, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: 'upi://pay?pa=${sub.upiId}&pn=MediPoss&cu=INR',
                    version: QrVersions.auto,
                    size: 130.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'UPI ID: ${sub.upiId}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _tierPriceBadge('Pro', '₹2,999/yr', AppTheme.primary),
                    const SizedBox(width: 16),
                    _tierPriceBadge('Enterprise', '₹5,999/yr', AppTheme.emerald),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _backupDatabase() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dbFile = File('${docDir.path}/objectbox/data.mdb');

      if (!dbFile.existsSync()) {
        throw Exception('Database file not found!');
      }

      String? outputPath;
      if (Platform.isWindows) {
        // Fallback for Windows if Downloads directory isn't strictly standard
        final downloadsPath =
            '${Platform.environment['USERPROFILE']}\\Downloads';
        outputPath = downloadsPath;
      } else {
        final dir = await getDownloadsDirectory();
        outputPath = dir?.path;
      }

      if (outputPath == null) {
        throw Exception('Could not locate Downloads folder');
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final backupPath = '$outputPath/mediposs_backup_$timestamp.mdb';

      await dbFile.copy(backupPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Backup saved to: $backupPath'),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Backup failed: $e'),
          backgroundColor: AppTheme.danger,
        ));
      }
    }
  }

  Future<void> _restoreDatabase() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);

      if (result == null || result.files.isEmpty) return;

      final selectedFile = File(result.files.single.path!);
      if (!selectedFile.path.endsWith('.mdb')) {
        throw Exception('Invalid file type! Please select a .mdb backup file.');
      }

      final docDir = await getApplicationDocumentsDirectory();
      final dbFile = File('${docDir.path}/objectbox/data.mdb');

      await selectedFile.copy(dbFile.path);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Restore Successful', style: TextStyle(color: AppTheme.success)),
            content: const Text('The database has been successfully restored.\n\nThe application must now restart to secure the new data lock. Please close the app and open it again.'),
            actions: [
              ElevatedButton(
                onPressed: () => exit(0),
                child: const Text('Exit App'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Restore failed: $e'), backgroundColor: AppTheme.danger));
      }
    }
  }

  Future<void> _generateAuditReport() async {
    try {
      final file = await AuditExportService.generateAuditReport();
      if (file != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Audit Report Saved: ${file.path.split('/').last}'),
          backgroundColor: AppTheme.success,
        ));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to generate Audit Report'),
          backgroundColor: AppTheme.danger,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e'), backgroundColor: AppTheme.danger));
      }
    }
  }

  Future<void> _backupJsonGranular() async {
    try {
      final file = await BackupRestoreService.exportToJsonBackup();
      if (file != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('JSON Backup Saved: ${file.path.split('/').last}'),
          backgroundColor: AppTheme.success,
        ));
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
                ElevatedButton(onPressed: () => exit(0), child: const Text('Exit App')),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e'), backgroundColor: AppTheme.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final serverRunning = LocalServerService.instance.isRunning;

    return Scaffold(
      backgroundColor: context.surfaceColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: const Text('Settings'),
            pinned: true,
            floating: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  context.read<NavigationProvider>().selectDestination('dashboard');
                }
              },
            ),
            forceElevated: innerBoxIsScrolled,
            elevation: innerBoxIsScrolled ? 4 : 0,
          ),
        ],
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20).copyWith(bottom: 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSection(
                'Licensing & Subscriptions',
                initiallyExpanded: true,
                children: [
                  _buildLicensingSection(context),
                ],
              ),
              _buildSection(
                'Store Details & General',
                initiallyExpanded: false,
                children: [
                  _field(_storeNameCtrl, 'Store Name'),
                  const SizedBox(height: 12),
                  _field(_addressCtrl, 'Physical Address'),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _field(_phoneCtrl, 'Contact Phone')),
                    const SizedBox(width: 16),
                    Expanded(child: _field(_gstCtrl, 'GST Number (Optional)')),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: context.borderColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SwitchListTile(
                      title: const Text('Composition Scheme Store',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          'If registered under GST Composition Scheme (tax locked to 0%, Bill of Supply headers, mandatory legal declarations on receipts)',
                          style: TextStyle(
                              color: context.textMutedColor, fontSize: 12)),
                      value: _isCompositionScheme,
                      activeTrackColor:
                          AppTheme.primaryLight.withValues(alpha: 0.3),
                      activeColor: AppTheme.primaryLight,
                      onChanged: (val) => setState(() => _isCompositionScheme = val),
                    ),
                  ),
                ],
              ),
              _buildSection(
                'Clinic / Doctor Details (for Clinical Dispenses)',
                children: [
                  _field(_clinicNameCtrl, 'Clinic / Doctor Name'),
                  const SizedBox(height: 12),
                  _field(_clinicAddressCtrl, 'Physical Address'),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _field(_clinicPhoneCtrl, 'Contact Phone')),
                    const SizedBox(width: 16),
                    Expanded(child: _field(_clinicRegCtrl, 'Medical Reg No.')),
                  ]),
                  const SizedBox(height: 16),
                  const Text('Default Prescribing Doctor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  DropdownButton<int?>(
                    isExpanded: true,
                    value: _selectedDefaultDoctorId,
                    dropdownColor: context.surfaceColor,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('None (Manual Entry)'),
                      ),
                      ..._doctors.map((d) => DropdownMenuItem<int?>(
                            value: d.id,
                            child: Text(d.name),
                          )),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedDefaultDoctorId = val;
                      });
                    },
                  ),
                ],
              ),
              _buildSection(
                'Printing & Receipt',
                children: [
                  _field(_footerCtrl, 'Receipt Footer Message'),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child:
                            _field(_currencyCtrl, 'Currency Symbol (e.g. ₹)')),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _field(
                            _taxCtrl,
                            _isCompositionScheme
                                ? 'Global Tax Rate (%) (Locked by Composition)'
                                : 'Global Tax Rate (%)',
                            keyboardType: TextInputType.number,
                            enabled: !_isCompositionScheme)),
                  ]),
                  const SizedBox(height: 24),
                  Text('Hardware Configuration',
                      style: TextStyle(
                          color: context.textMutedColor,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Paper Size',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: context.textMutedColor)),
                            DropdownButton<String>(
                              isExpanded: true,
                              value: ['A6', 'Letter', 'A4', 'Roll80']
                                      .contains(_paperSize)
                                  ? _paperSize
                                  : 'A6',
                              dropdownColor: context.surfaceColor,
                              items: const [
                                DropdownMenuItem(
                                    value: 'A6', child: Text('A6')),
                                DropdownMenuItem(
                                    value: 'Letter', child: Text('Letter')),
                                DropdownMenuItem(
                                    value: 'A4', child: Text('A4')),
                                DropdownMenuItem(
                                    value: 'Roll80',
                                    child: Text('Thermal Roll (80mm)')),
                              ],
                              onChanged: (val) {
                                if (val != null)
                                  setState(() => _paperSize = val);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Default Hardware Printer',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: context.textMutedColor)),
                            DropdownButton<String>(
                              isExpanded: true,
                              value: _printers
                                      .any((p) => p.name == _selectedPrinter)
                                  ? _selectedPrinter
                                  : (_selectedPrinter.isEmpty ? '' : null),
                              hint: const Text('Select OS Printer...'),
                              dropdownColor: context.surfaceColor,
                              items: [
                                const DropdownMenuItem(
                                    value: '',
                                    child: Text('None (Always Preview)')),
                                ..._printers.map((p) => DropdownMenuItem(
                                    value: p.name, child: Text(p.name))),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedPrinter = val);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: context.borderColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SwitchListTile(
                      title: const Text('Auto-Print on Checkout',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          'Instantly print without confirming via OS Print Preview window',
                          style: TextStyle(
                              color: context.textMutedColor, fontSize: 12)),
                      value: _autoPrint,
                      activeTrackColor:
                          AppTheme.primaryLight.withValues(alpha: 0.3),
                      activeColor: AppTheme.primaryLight,
                      onChanged: _selectedPrinter.isEmpty
                          ? null
                          : (val) => setState(() => _autoPrint = val),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: context.borderColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SwitchListTile(
                      title: const Text('Show Batch & Expiry (Retail)',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          'Show Batch number and Expiry date on retail receipts',
                          style: TextStyle(
                              color: context.textMutedColor, fontSize: 12)),
                      value: _showBatchExpiryRetail,
                      activeTrackColor:
                          AppTheme.primaryLight.withValues(alpha: 0.3),
                      activeColor: AppTheme.primaryLight,
                      onChanged: (val) => setState(() => _showBatchExpiryRetail = val),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: context.borderColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SwitchListTile(
                      title: const Text('Show Batch & Expiry (Dispense)',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          'Show Batch number and Expiry date on clinical dispense slips',
                          style: TextStyle(
                              color: context.textMutedColor, fontSize: 12)),
                      value: _showBatchExpiryClinical,
                      activeTrackColor:
                          AppTheme.primaryLight.withValues(alpha: 0.3),
                      activeColor: AppTheme.primaryLight,
                      onChanged: (val) => setState(() => _showBatchExpiryClinical = val),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: context.borderColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SwitchListTile(
                      title: const Text('Show OPD Transaction ID',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          'Show OPD ID on final dispense receipts',
                          style: TextStyle(
                              color: context.textMutedColor, fontSize: 12)),
                      value: _showOpdIdInPrint,
                      activeTrackColor:
                          AppTheme.primaryLight.withValues(alpha: 0.3),
                      activeColor: AppTheme.primaryLight,
                      onChanged: (val) => setState(() => _showOpdIdInPrint = val),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        _save(); // ensure settings are updated in memory before test
                        await PrintingService.instance.testPrint(context);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: AppTheme.primary),
                        foregroundColor: AppTheme.primary,
                      ),
                      icon: const Icon(Icons.print),
                      label: const Text('Test Current Configuration'),
                    ),
                  ),
                ],
              ),
              _buildSection(
                'App Preferences',
                children: [
                  Row(
                    children: [
                      Text('UI Theme Mode',
                          style: TextStyle(
                              color: context.textMutedColor,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      DropdownButton<String>(
                        value: _selectedTheme,
                        dropdownColor: context.surfaceColor,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(
                              value: 'system', child: Text('System Default')),
                          DropdownMenuItem(
                              value: 'light', child: Text('Light Mode')),
                          DropdownMenuItem(
                              value: 'dark', child: Text('Dark Mode')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedTheme = val);
                        },
                      ),
                    ],
                  ),
                  if (Platform.isAndroid && _displayModes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('Display Refresh Rate',
                            style: TextStyle(
                                color: context.textMutedColor,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        DropdownButton<double>(
                          value: _displayModes.any((m) =>
                                  m.refreshRate.toStringAsFixed(1) ==
                                  _selectedFPS.toStringAsFixed(1))
                              ? _selectedFPS
                              : -1.0,
                          dropdownColor: context.surfaceColor,
                          underline: const SizedBox(),
                          items: [
                            const DropdownMenuItem<double>(
                                value: -1.0, child: Text('Auto (Max)')),
                            ..._displayModes
                                .map((m) => m.refreshRate)
                                .where((rate) => rate > 0.0)
                                .toSet()
                                .toList()
                                .followedBy([])
                                .map((rate) => DropdownMenuItem<double>(
                                      value: rate,
                                      child: Text('${rate.toInt()} Hz'),
                                    ))
                                .toList()
                              ..sort((a, b) => b.value!.compareTo(a.value!)),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedFPS = val);
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              _buildSection(
                'Networking (Windows Hub)',
                children: [
                  _field(_portCtrl, 'Server Port',
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: serverRunning
                          ? AppTheme.success.withValues(alpha: 0.1)
                          : AppTheme.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: serverRunning
                              ? AppTheme.success.withValues(alpha: 0.5)
                              : AppTheme.danger.withValues(alpha: 0.5)),
                    ),
                    child: Row(children: [
                      Icon(serverRunning ? Icons.check_circle : Icons.cancel,
                          color: serverRunning
                              ? AppTheme.success
                              : AppTheme.danger,
                          size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                            serverRunning
                                ? 'Hub Server Running on port ${_portCtrl.text}'
                                : 'Hub Server Stopped',
                            style: TextStyle(
                                color: serverRunning
                                    ? AppTheme.success
                                    : AppTheme.danger,
                                fontWeight: FontWeight.bold)),
                      ),
                    ]),
                  ),
                ],
              ),
              _buildSection(
                'App Mode & Hybrid Connectivity (Hub / Companion)',
                initiallyExpanded: true,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: context.borderColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SwitchListTile(
                      title: const Text('Companion Terminal Mode',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          'Enable client mode to pair with a standalone Hub. Disable to run this device as the Hub/Server.',
                          style: TextStyle(
                              color: context.textMutedColor, fontSize: 12)),
                      value: _isWindowsClient,
                      activeTrackColor:
                          AppTheme.primaryLight.withValues(alpha: 0.3),
                      activeColor: AppTheme.primaryLight,
                      onChanged: (val) => setState(() => _isWindowsClient = val),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Configure how this app connects to the Windows Hub when you are away from the clinic.',
                    style:
                        TextStyle(color: context.textMutedColor, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text('Connection Mode',
                          style: TextStyle(
                              color: context.textMutedColor,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      DropdownButton<String>(
                        value: _connectionMode,
                        dropdownColor: context.surfaceColor,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(
                              value: 'auto', child: Text('Auto (Preferred)')),
                          DropdownMenuItem(
                              value: 'local', child: Text('Local WiFi Only')),
                          DropdownMenuItem(
                              value: 'cloudflare',
                              child: Text('Cloudflare Tunnel')),
                          DropdownMenuItem(
                              value: 'firebase', child: Text('Backup Cloud')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _connectionMode = val);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Shop ID / Partition',
                                style: TextStyle(
                                    color: context.textMutedColor,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(
                              context.watch<SettingsProvider>().settings.shopId.isNotEmpty
                                  ? context.watch<SettingsProvider>().settings.shopId
                                  : 'default_shop (Fallback to Store Name)',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          await showShopSelectionDialog(
                            context,
                            enterCloud: false,
                            onSelected: () {
                              setState(() {});
                              // Restart Firestore listeners with the new shop ID
                              SyncService.instance.initializeFirestoreRealTimeSync();
                            },
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.textMutedColor.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: context.borderColor.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.cloud_sync_rounded,
                                color: AppTheme.primaryLight, size: 18),
                            const SizedBox(width: 8),
                            Text('Cloudflare Tunnel Link',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: context.textMutedColor)),
                            const Spacer(),
                            if (_isFetchingHubStatus)
                              const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                            else
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.refresh, size: 16),
                                onPressed: _fetchHubStatus,
                                color: AppTheme.primary,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_cloudflareUrl.isEmpty)
                          Text('No active tunnel found. Is Hub running?',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: context.textMutedColor,
                                  fontStyle: FontStyle.italic))
                        else
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _cloudflareUrl,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.primaryLight,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 18),
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: _cloudflareUrl));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Link copied!')));
                                },
                                color: context.textMutedColor,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              _buildSection(
                'Data Management',
                children: [
                  Text(
                    'Create a backup of your entire store database, or restore an existing backup. Restoring a backup will overwrite all current data and immediately restart the app.',
                    style:
                        TextStyle(color: context.textMutedColor, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _backupDatabase,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.backup_rounded, size: 20),
                          label: const Text('BACKUP DB',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  letterSpacing: 0.5)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _restoreDatabase,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                            side: BorderSide(
                                color: AppTheme.danger.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.restore_rounded, size: 20),
                          label: const Text('RESTORE DB',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  letterSpacing: 0.5)),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _backupJsonGranular,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.purple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.data_object_rounded, size: 20),
                          label: const Text('GRANULAR BACKUP (JSON)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.5)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _restoreJsonGranular,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                            side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.settings_backup_restore_rounded, size: 20),
                          label: const Text('GRANULAR RESTORE', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.5)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              _buildSection(
                'Comprehensive Audits',
                children: [
                  Text('Includes stocks, internal transfers, sales, patients, and prescriptions in an Excel file.', style: TextStyle(color: context.textMutedColor, fontSize: 13)),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _generateAuditReport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.emerald,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.table_view_rounded, size: 20),
                      label: const Text('GENERATE AUDIT REPORT (.XLSX)'),
                    ),
                  ),
                ],
              ),
              _buildSection(
                'System Audit Logs Policy',
                children: [
                  Row(
                    children: [
                      Text('Keep Audit Logs For',
                          style: TextStyle(
                              color: context.textMutedColor,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      DropdownButton<int>(
                        value: _auditRetentionDays,
                        dropdownColor: context.surfaceColor,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Keep Forever')),
                          DropdownMenuItem(value: 30, child: Text('30 Days')),
                          DropdownMenuItem(value: 90, child: Text('90 Days')),
                          DropdownMenuItem(value: 180, child: Text('180 Days')),
                          DropdownMenuItem(value: 365, child: Text('1 Year')),
                          DropdownMenuItem(value: 730, child: Text('2 Years')),
                          DropdownMenuItem(value: 1095, child: Text('3 Years')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _auditRetentionDays = val);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              if (auth.isAdmin) ...[
                _buildSection(
                  'User & Medical Management',
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.people_rounded,
                            color: AppTheme.primary, size: 20),
                      ),
                      title: const Text('Manage Staff & Roles',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Add users, set permissions',
                          style: TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const UserManagementScreen())),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.medical_services_rounded,
                            color: Colors.teal, size: 20),
                      ),
                      title: const Text('Manage Doctors',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Edit list, fees and specializations',
                          style: TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const DoctorListScreen())),
                    ),
                  ],
                ),
                _buildSection(
                  'User Authentication',
                  children: [
                    ...auth.getAllUsers().map((u) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color:
                                context.textMutedColor.withValues(alpha: 0.03),
                            border: Border.all(
                                color:
                                    context.borderColor.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(u.name[0].toUpperCase(),
                                    style: const TextStyle(
                                        color: AppTheme.primary,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                            title: Text(u.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15)),
                            subtitle: Text(u.role.toUpperCase(),
                                style: TextStyle(
                                    color: context.textMutedColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5)),
                            trailing: u.role == 'admin' ||
                                    auth.currentUser?.id == u.id
                                ? TextButton.icon(
                                    onPressed: () =>
                                        _changePinDialog(context, u, auth),
                                    style: TextButton.styleFrom(
                                        foregroundColor: AppTheme.primary),
                                    icon: const Icon(Icons.password_rounded,
                                        size: 16),
                                    label: const Text('PIN',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11)),
                                  )
                                : null,
                          ),
                        )),
                  ],
                ),
              ],
              if (Platform.isAndroid) ...[
                _buildSection(
                  'Software Update',
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.system_update_rounded,
                            color: AppTheme.primary, size: 20),
                      ),
                      title: const Text('Check for Updates',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Check for new version on Firebase',
                          style: TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        OtaUpdateService.checkForUpdate(context, forceShowNoUpdate: true);
                      },
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16),
        decoration: BoxDecoration(
          color: context.surfaceColor.withValues(alpha: 0.9),
          border: Border(
              top: BorderSide(
                  color: context.borderColor.withValues(alpha: 0.2))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -8),
            )
          ],
        ),
        child: ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16))),
          child: const Text('SAVE ALL SETTINGS',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: Colors.white)),
        ),
      ),
    );
  }

  Widget _buildSection(String title,
      {required List<Widget> children, bool initiallyExpanded = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
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
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: RepaintBoundary(
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            iconColor: AppTheme.primary,
            collapsedIconColor: context.textMutedColor,
            title: Text(
              title.toUpperCase(),
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 1,
                  color: AppTheme.primaryLight),
            ),
            childrenPadding: const EdgeInsets.all(24).copyWith(top: 0),
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      {TextInputType? keyboardType, bool? enabled}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      enabled: enabled,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            color: context.textMutedColor,
            fontWeight: FontWeight.w600,
            fontSize: 13),
        isDense: true,
        filled: true,
        fillColor: context.textMutedColor.withValues(alpha: 0.03),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: context.borderColor.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: context.borderColor.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      ),
    );
  }

  void _changePinDialog(BuildContext context, AppUser user, AuthProvider auth) {
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('CHANGE PIN: ${user.name.toUpperCase()}',
            style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter a new 4 to 6 digit security PIN for this user.',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 20),
            _field(pinCtrl, 'NEW PIN', keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL',
                  style: TextStyle(
                      color: context.textMutedColor,
                      fontWeight: FontWeight.w700))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                if (pinCtrl.text.length >= 4) {
                  auth.updatePin(user.id, pinCtrl.text,
                      syncService: context.read<SyncService>());
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('✅ PIN updated successfully')));
                }
              },
              child: const Text('UPDATE PIN',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.white))),
        ],
      ),
    );
  }
}
