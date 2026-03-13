import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/models/app_user.dart';
import '../../theme/app_theme.dart';
import '../../shared/services/local_server_service.dart';
import '../../shared/services/printing_service.dart';
import 'package:printing/printing.dart';

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

  String _selectedTheme = 'system';
  List<Printer> _printers = [];
  String _selectedPrinter = '';
  bool _autoPrint = false;
  String _paperSize = 'A6';

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
    _selectedTheme = ['system', 'light', 'dark'].contains(s.themeMode)
        ? s.themeMode
        : 'system';

    _selectedPrinter = s.defaultPrinterName;
    _autoPrint = s.autoPrintReceipt;
    _paperSize = s.receiptPaperSize;

    _loadPrinters();
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

  void _save() {
    final settingsProv = context.read<SettingsProvider>();
    final s = settingsProv.settings;
    s
      ..storeName = _storeNameCtrl.text
      ..storeAddress = _addressCtrl.text
      ..storePhone = _phoneCtrl.text
      ..gstNumber = _gstCtrl.text
      ..receiptFooterMessage = _footerCtrl.text
      ..taxRate = double.tryParse(_taxCtrl.text) ?? 0
      ..currencySymbol = _currencyCtrl.text
      ..themeMode = _selectedTheme
      ..defaultPrinterName = _selectedPrinter
      ..autoPrintReceipt = _autoPrint
      ..receiptPaperSize = _paperSize
      ..serverPort = int.tryParse(_portCtrl.text) ?? 8080;

    settingsProv.save(s);

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('✅ Settings saved'),
      backgroundColor: AppTheme.success,
    ));
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
      final result = await FilePicker.platform.pickFiles(
        type:
            FileType.any, // .mdb might not have standard mime types registered
      );

      if (result == null || result.files.isEmpty) return; // User cancelled

      final selectedFile = File(result.files.single.path!);
      if (!selectedFile.path.endsWith('.mdb')) {
        throw Exception('Invalid file type! Please select a .mdb backup file.');
      }

      final docDir = await getApplicationDocumentsDirectory();
      final dbFile = File('${docDir.path}/objectbox/data.mdb');

      // Crucial: Copy the selected file OVER the active database file
      await selectedFile.copy(dbFile.path);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Restore Successful',
                style: TextStyle(color: AppTheme.success)),
            content: const Text(
                'The database has been successfully restored.\n\nThe application must now restart to secure the new data lock. Please close the app and open it again.'),
            actions: [
              ElevatedButton(
                onPressed: () {
                  // Forcefully close the app so ObjectBox completely unbinds its Store pointers
                  SystemNavigator.pop();
                },
                child: const Text('Exit App'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Restore failed: $e'),
          backgroundColor: AppTheme.danger,
        ));
      }
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
                'Store Details & General',
                initiallyExpanded: true,
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
                        child: _field(_taxCtrl, 'Global Tax Rate (%)',
                            keyboardType: TextInputType.number)),
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
                          icon: const Icon(Icons.download),
                          label: const Text('Backup DB'),
                          style: ElevatedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16)),
                          onPressed: _backupDatabase,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon:
                              const Icon(Icons.restore, color: AppTheme.danger),
                          label: const Text('Restore DB',
                              style: TextStyle(color: AppTheme.danger)),
                          style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: const BorderSide(color: AppTheme.danger)),
                          onPressed: _restoreDatabase,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (auth.isAdmin)
                _buildSection(
                  'User Authentication',
                  children: [
                    ...auth.getAllUsers().map((u) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color:
                                    context.borderColor.withValues(alpha: 0.5)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppTheme.primary.withValues(alpha: 0.15),
                              child: Text(u.name[0].toUpperCase(),
                                  style: const TextStyle(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.bold)),
                            ),
                            title: Text(u.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text('Role: ${u.role}',
                                style:
                                    TextStyle(color: context.textMutedColor)),
                            trailing: u.role == 'admin' ||
                                    auth.currentUser?.id == u.id
                                ? TextButton.icon(
                                    onPressed: () =>
                                        _changePinDialog(context, u, auth),
                                    icon: const Icon(Icons.password, size: 18),
                                    label: const Text('Change PIN'),
                                  )
                                : null,
                          ),
                        )),
                  ],
                ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -4),
            )
          ],
        ),
        child: ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
          child: const Text('Save All Settings',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ),
      ),
    );
  }

  Widget _buildSection(String title,
      {required List<Widget> children, bool initiallyExpanded = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
          initiallyExpanded: initiallyExpanded,
          title: Text(
            title,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppTheme.primaryLight),
          ),
          childrenPadding: const EdgeInsets.all(20).copyWith(top: 0),
          children: children,
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }

  void _changePinDialog(BuildContext context, AppUser user, AuthProvider auth) {
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Change PIN — ${user.name}'),
        content: TextField(
          controller: pinCtrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: 'New PIN'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () {
                if (pinCtrl.text.length >= 4) {
                  auth.updatePin(user.id, pinCtrl.text);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('PIN updated')));
                }
              },
              child: const Text('Update')),
        ],
      ),
    );
  }
}
