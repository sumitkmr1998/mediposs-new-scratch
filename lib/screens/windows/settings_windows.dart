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
import 'package:excel/excel.dart' as excel_pkg;
import '../../shared/providers/inventory_provider.dart';
import '../../shared/models/medicine.dart';

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

  Future<void> _exportExcel() async {
    final inv = context.read<InventoryProvider>();
    final medicines = inv.medicines;
    if (medicines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No medicines to export.'),
      ));
      return;
    }

    try {
      var excel = excel_pkg.Excel.createExcel();
      var sheet = excel['Sheet1'];

      // Header row
      sheet.appendRow([
        excel_pkg.TextCellValue('ID'),
        excel_pkg.TextCellValue('Medicine Name'),
        excel_pkg.TextCellValue('Barcode'),
        excel_pkg.TextCellValue('Category'),
        excel_pkg.TextCellValue('Unit'),
        excel_pkg.TextCellValue('Purchase Price'),
        excel_pkg.TextCellValue('Selling Rate'),
        excel_pkg.TextCellValue('Main Hub Stock'),
        excel_pkg.TextCellValue('Store Front Stock'),
        excel_pkg.TextCellValue('Low Stock Threshold'),
      ]);

      for (var med in medicines) {
        sheet.appendRow([
          excel_pkg.IntCellValue(med.id),
          excel_pkg.TextCellValue(med.name),
          excel_pkg.TextCellValue(med.barcode),
          excel_pkg.TextCellValue(med.category),
          excel_pkg.TextCellValue(med.unit),
          excel_pkg.DoubleCellValue(med.purchasePrice),
          excel_pkg.DoubleCellValue(med.sellingPrice),
          excel_pkg.IntCellValue(med.mainStock),
          excel_pkg.IntCellValue(med.storeStock),
          excel_pkg.IntCellValue(med.lowStockThreshold),
        ]);
      }

      String? outputPath;
      if (Platform.isWindows) {
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
      final String filePath = '$outputPath/medicines_export_$timestamp.xlsx';

      final fileBytes = excel.save();
      if (fileBytes != null) {
        File(filePath).writeAsBytesSync(fileBytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ Excel Export successful: $filePath'),
            backgroundColor: AppTheme.success,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Excel Export failed: $e'),
          backgroundColor: AppTheme.danger,
        ));
      }
    }
  }

  Future<void> _importExcel() async {
    final auth = context.read<AuthProvider>();
    if (!auth.hasInventoryWriteAccess) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('You do not have permission to modify inventory.'),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result != null && result.files.single.path != null) {
      try {
        final file = File(result.files.single.path!);
        var bytes = file.readAsBytesSync();
        var excel = excel_pkg.Excel.decodeBytes(bytes);

        if (excel.tables.keys.isEmpty) return;

        final String firstSheet = excel.tables.keys.first;
        final table = excel.tables[firstSheet];
        if (table == null) return;

        int added = 0;
        int updated = 0;
        final inv = context.read<InventoryProvider>();

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
          throw Exception(
              "Could not find a header row containing 'Medicine Name'.");
        }

        // 2. Map columns
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

        final nameIdx =
            getColIdx(['medicine name', 'item name', 'product name']);
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

        // 3. Process rows
        for (int i = headerRowIndex + 1; i < table.maxRows; i++) {
          final row = table.row(i);

          String getCellStr(int idx, String def) =>
              (idx != -1 && idx < row.length)
                  ? (row[idx]?.value?.toString().trim() ?? def)
                  : def;
          double getCellDbl(int idx, double def) => (idx != -1 &&
                  idx < row.length)
              ? (double.tryParse(row[idx]?.value?.toString().trim() ?? '') ??
                  def)
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

          final existing = inv.medicines
              .where((m) => m.name.toLowerCase() == nameCell.toLowerCase())
              .firstOrNull;

          if (existing != null) {
            final updatedMed = Medicine(
              id: existing.id,
              name: nameCell,
              barcode: barcode.isNotEmpty ? barcode : existing.barcode,
              category: category,
              unit: unit,
              purchasePrice:
                  purchasePrice > 0 ? purchasePrice : existing.purchasePrice,
              sellingPrice:
                  sellingPrice > 0 ? sellingPrice : existing.sellingPrice,
              mainStock: mainStock > 0 ? mainStock : existing.mainStock,
              storeStock: storeStock > 0 ? storeStock : existing.storeStock,
              lowStockThreshold: lowStock,
              synced: false,
            );
            inv.updateMedicine(updatedMed);
            updated++;
          } else {
            final newMed = Medicine(
              name: nameCell,
              barcode: barcode,
              category: category,
              unit: unit,
              purchasePrice: purchasePrice,
              sellingPrice: sellingPrice,
              mainStock: mainStock,
              storeStock: storeStock,
              lowStockThreshold: lowStock,
            );
            inv.addMedicine(newMed);
            added++;
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '✅ Excel Import Complete: Added $added new, Updated $updated existing medicines.'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('❌ Excel Import failed: $e'),
            backgroundColor: AppTheme.danger,
          ));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final serverRunning = LocalServerService.instance.isRunning;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExpansionTile(
              initiallyExpanded: true,
              title: _sectionHeader('Store Details & Printing'),
              childrenPadding: const EdgeInsets.all(16),
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
            ExpansionTile(
              title: _sectionHeader('Printing Settings'),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                _field(_footerCtrl, 'Receipt Footer Message'),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: _field(_currencyCtrl, 'Currency Symbol (e.g. ₹)')),
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
                                  fontSize: 12, color: context.textMutedColor)),
                          DropdownButton<String>(
                            isExpanded: true,
                            value: ['A6', 'Letter', 'A4', 'Roll80']
                                    .contains(_paperSize)
                                ? _paperSize
                                : 'A6',
                            dropdownColor: context.surfaceColor,
                            items: const [
                              DropdownMenuItem(value: 'A6', child: Text('A6')),
                              DropdownMenuItem(
                                  value: 'Letter', child: Text('Letter')),
                              DropdownMenuItem(value: 'A4', child: Text('A4')),
                              DropdownMenuItem(
                                  value: 'Roll80',
                                  child: Text('Thermal Roll (80mm)')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _paperSize = val);
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
                                  fontSize: 12, color: context.textMutedColor)),
                          DropdownButton<String>(
                            isExpanded: true,
                            value:
                                _printers.any((p) => p.name == _selectedPrinter)
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
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Auto-Print on Checkout'),
                  subtitle: Text(
                      'Instantly print without confirming via OS Print Preview window',
                      style: TextStyle(
                          color: context.textMutedColor, fontSize: 12)),
                  value: _autoPrint,
                  activeThumbColor: AppTheme.primaryLight,
                  onChanged: _selectedPrinter.isEmpty
                      ? null
                      : (val) => setState(() => _autoPrint = val),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      _save(); // ensure settings are updated in memory before test
                      await PrintingService.instance.testPrint(context);
                    },
                    icon: const Icon(Icons.print),
                    label: const Text('Test Current Configuration'),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: _sectionHeader('App Preferences'),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Text('UI Theme Mode',
                        style: TextStyle(color: context.textMutedColor)),
                    const Spacer(),
                    DropdownButton<String>(
                      value: _selectedTheme,
                      dropdownColor: context.surfaceColor,
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
            ExpansionTile(
              title: _sectionHeader('Networking (Windows Hub)'),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                _field(_portCtrl, 'Server Port',
                    keyboardType: TextInputType.number),
                const SizedBox(height: 12),
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: serverRunning
                          ? AppTheme.success.withValues(alpha: 0.15)
                          : AppTheme.danger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: serverRunning
                              ? AppTheme.success
                              : AppTheme.danger),
                    ),
                    child: Row(children: [
                      Icon(serverRunning ? Icons.check_circle : Icons.cancel,
                          color: serverRunning
                              ? AppTheme.success
                              : AppTheme.danger,
                          size: 16),
                      const SizedBox(width: 6),
                      Text(
                          serverRunning
                              ? 'Hub Server Running on :${_portCtrl.text}'
                              : 'Hub Server Stopped',
                          style: TextStyle(
                              color: serverRunning
                                  ? AppTheme.success
                                  : AppTheme.danger,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ]),
              ],
            ),
            ExpansionTile(
              title: _sectionHeader('Data Management (Excel Import/Export)'),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Bulk import medicines from an Excel file or export your current inventory list.',
                  style: TextStyle(color: context.textMutedColor, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.file_upload),
                      label: const Text('Import Medicines'),
                      onPressed: _importExcel,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.file_download,
                          color: AppTheme.primary),
                      label: const Text('Export Medicines',
                          style: TextStyle(color: AppTheme.primary)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.primary)),
                      onPressed: _exportExcel,
                    ),
                  ],
                ),
              ],
            ),
            ExpansionTile(
              title: _sectionHeader('Data Management (Backup & Restore)'),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Create a backup of your entire store database, or restore an existing backup. Restoring a backup will overwrite all current data and immediately restart the app.',
                  style: TextStyle(color: context.textMutedColor, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('Backup DB'),
                      onPressed: _backupDatabase,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.restore, color: AppTheme.danger),
                      label: const Text('Restore DB',
                          style: TextStyle(color: AppTheme.danger)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.danger)),
                      onPressed: _restoreDatabase,
                    ),
                  ],
                ),
              ],
            ),
            if (auth.isAdmin)
              ExpansionTile(
                title: _sectionHeader('User Management'),
                childrenPadding: const EdgeInsets.all(16),
                children: [
                  ...auth.getAllUsers().map((u) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                AppTheme.primary.withValues(alpha: 0.15),
                            child: Text(u.name[0].toUpperCase(),
                                style:
                                    const TextStyle(color: AppTheme.primary)),
                          ),
                          title: Text(u.name),
                          subtitle: Text(u.role),
                          trailing:
                              u.role == 'admin' || auth.currentUser?.id == u.id
                                  ? TextButton(
                                      onPressed: () =>
                                          _changePinDialog(context, u, auth),
                                      child: const Text('Change PIN'))
                                  : null,
                        ),
                      )),
                ],
              ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('Save All Settings',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Text(title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryLight,
          ));

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
