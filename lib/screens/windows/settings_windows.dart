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
  late final TextEditingController _lowStockCtrl;
  late final TextEditingController _nearExpiryCtrl;

  String _selectedTheme = 'system';
  List<Printer> _printers = [];
  String _selectedPrinter = '';
  bool _autoPrint = false;
  String _paperSize = 'A6';
  int _selectedSection = 0;

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
    _lowStockCtrl = TextEditingController(text: '${s.lowStockThreshold}');
    _nearExpiryCtrl = TextEditingController(text: '${s.nearExpiryThresholdDays}');
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
      ..lowStockThreshold = int.tryParse(_lowStockCtrl.text) ?? 10
      ..nearExpiryThresholdDays = int.tryParse(_nearExpiryCtrl.text) ?? 90
      ..serverPort = int.tryParse(_portCtrl.text) ?? 8080;

    settingsProv.save(s);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(
        children: [
          Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
          SizedBox(width: 8),
          Text('Settings saved successfully'),
        ],
      ),
      backgroundColor: AppTheme.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          content: Text('Backup saved to: $backupPath'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Backup failed: $e'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
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
            title: const Text('Restore Successful',
                style: TextStyle(color: AppTheme.success)),
            content: const Text(
                'The database has been successfully restored.\n\nThe application must now restart.'),
            actions: [
              ElevatedButton(
                onPressed: () => SystemNavigator.pop(),
                child: const Text('Exit App'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Restore failed: $e'),
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
            content: Text('Excel Export successful: $filePath'),
            backgroundColor: AppTheme.success,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Excel Export failed: $e'),
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

        final headerRow = table.row(headerRowIndex);
        for (int j = 0; j < headerRow.length; j++) {
          final title =
              headerRow[j]?.value?.toString().trim().toLowerCase() ?? '';
          if (title.isNotEmpty) {
            colMap[title] = j;
          }
        }

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
          if (nameCell.isEmpty) continue;

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
                  'Import Complete: Added $added new, Updated $updated existing.'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Excel Import failed: $e'),
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

    final sections = [
      _NavItem(Icons.store_rounded, 'Store Details', AppTheme.primary),
      _NavItem(Icons.print_rounded, 'Printing', AppTheme.accent),
      _NavItem(Icons.palette_rounded, 'Appearance', const Color(0xFF7C3AED)),
      _NavItem(Icons.wifi_rounded, 'Networking', const Color(0xFF0EA5E9)),
      _NavItem(Icons.inventory_2_rounded, 'Inventory', Colors.orange),
      _NavItem(Icons.folder_rounded, 'Data', AppTheme.warning),
      if (auth.isAdmin)
        _NavItem(Icons.people_rounded, 'Users', AppTheme.success),
    ];

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 260,
            decoration: BoxDecoration(
              color: context.surfaceColor,
              border: Border(right: BorderSide(color: context.borderColor)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.settings_rounded,
                            color: AppTheme.primary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: context.borderColor),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: sections.length,
                    itemBuilder: (ctx, i) {
                      final s = sections[i];
                      final isSelected = _selectedSection == i;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: Material(
                          color: isSelected
                              ? s.color.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() => _selectedSection = i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? s.color
                                          : s.color.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(s.icon,
                                        size: 18,
                                        color: isSelected
                                            ? Colors.white
                                            : s.color),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(s.label,
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? s.color
                                            : context.textMutedColor,
                                      )),
                                  if (isSelected) ...[
                                    const Spacer(),
                                    Container(
                                      width: 4,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: s.color,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Save All Settings'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: context.bgColor,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_selectedSection == 0) _buildStoreDetailsSection(),
                    if (_selectedSection == 1) _buildPrintingSection(),
                    if (_selectedSection == 2) _buildAppearanceSection(),
                    if (_selectedSection == 3)
                      _buildNetworkingSection(serverRunning),
                    if (_selectedSection == 4) _buildInventorySection(),
                    if (_selectedSection == 5) _buildDataSection(),
                    if (auth.isAdmin && _selectedSection == 6)
                      _buildUsersSection(auth),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreDetailsSection() {
    return _SettingsCard(
      title: 'Store Information',
      icon: Icons.store_rounded,
      accentColor: AppTheme.primary,
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
    );
  }

  Widget _buildPrintingSection() {
    return Column(children: [
      _SettingsCard(
        title: 'Receipt Settings',
        icon: Icons.receipt_long_rounded,
        accentColor: AppTheme.accent,
        children: [
          _field(_footerCtrl, 'Receipt Footer Message'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _field(_currencyCtrl, 'Currency Symbol (e.g. ₹)')),
            const SizedBox(width: 16),
            Expanded(
                child: _field(_taxCtrl, 'Global Tax Rate (%)',
                    keyboardType: TextInputType.number)),
          ]),
        ],
      ),
      const SizedBox(height: 20),
      _SettingsCard(
        title: 'Hardware Configuration',
        icon: Icons.print_rounded,
        accentColor: AppTheme.accent,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Paper Size',
                        style: TextStyle(
                            fontSize: 12, color: context.textMutedColor)),
                    const SizedBox(height: 6),
                    DropdownButton<String>(
                      isExpanded: true,
                      value:
                          ['A6', 'Letter', 'A4', 'Roll80'].contains(_paperSize)
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
                  ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Default Printer',
                        style: TextStyle(
                            fontSize: 12, color: context.textMutedColor)),
                    const SizedBox(height: 6),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: _printers.any((p) => p.name == _selectedPrinter)
                          ? _selectedPrinter
                          : (_selectedPrinter.isEmpty ? '' : null),
                      hint: const Text('Select Printer...'),
                      dropdownColor: context.surfaceColor,
                      items: [
                        const DropdownMenuItem(
                            value: '', child: Text('None (Preview Only)')),
                        ..._printers.map((p) => DropdownMenuItem(
                            value: p.name, child: Text(p.name))),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedPrinter = val);
                      },
                    ),
                  ]),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: SwitchListTile(
                title: const Text('Auto-Print on Checkout',
                    style: TextStyle(fontSize: 13)),
                subtitle: Text('Print without preview',
                    style:
                        TextStyle(fontSize: 11, color: context.textMutedColor)),
                value: _autoPrint,
                activeTrackColor: AppTheme.success.withValues(alpha: 0.5),
                thumbColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppTheme.success;
                  }
                  return Colors.grey;
                }),
                onChanged: _selectedPrinter.isEmpty
                    ? null
                    : (val) => setState(() => _autoPrint = val),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              _save();
              await PrintingService.instance.testPrint(context);
            },
            icon: const Icon(Icons.print, size: 18),
            label: const Text('Test Print'),
          ),
        ],
      ),
    ]);
  }

  Widget _buildAppearanceSection() {
    return _SettingsCard(
      title: 'UI Theme',
      icon: Icons.palette_rounded,
      accentColor: const Color(0xFF7C3AED),
      children: [
        Row(children: [
          Text('Theme Mode', style: TextStyle(color: context.textMutedColor)),
          const Spacer(),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'system', label: Text('System')),
              ButtonSegment(value: 'light', label: Text('Light')),
              ButtonSegment(value: 'dark', label: Text('Dark')),
            ],
            selected: {_selectedTheme},
            onSelectionChanged: (vals) =>
                setState(() => _selectedTheme = vals.first),
          ),
        ]),
      ],
    );
  }

  Widget _buildInventorySection() {
    return _SettingsCard(
      title: 'Inventory Alert Thresholds',
      icon: Icons.inventory_2_rounded,
      accentColor: Colors.orange,
      children: [
        _field(_lowStockCtrl, 'Global Low Stock Warning Level',
            keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        _field(_nearExpiryCtrl, 'Near Expiry Warning Period (Days)',
            keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        Text(
          'These thresholds control the alerts shown on your dashboard health bar.',
          style: TextStyle(fontSize: 12, color: context.textMutedColor),
        ),
      ],
    );
  }

  Widget _buildNetworkingSection(bool serverRunning) {
    return _SettingsCard(
      title: 'Windows Hub Server',
      icon: Icons.wifi_rounded,
      accentColor: const Color(0xFF0EA5E9),
      children: [
        _field(_portCtrl, 'Server Port', keyboardType: TextInputType.number),
        const SizedBox(height: 16),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: serverRunning
                  ? AppTheme.success.withValues(alpha: 0.15)
                  : AppTheme.danger.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: serverRunning ? AppTheme.success : AppTheme.danger),
            ),
            child: Row(children: [
              Icon(serverRunning ? Icons.check_circle : Icons.cancel,
                  color: serverRunning ? AppTheme.success : AppTheme.danger,
                  size: 16),
              const SizedBox(width: 8),
              Text(
                serverRunning
                    ? 'Running on port ${_portCtrl.text}'
                    : 'Server Stopped',
                style: TextStyle(
                    color: serverRunning ? AppTheme.success : AppTheme.danger,
                    fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        ]),
      ],
    );
  }

  Widget _buildDataSection() {
    return Column(children: [
      _SettingsCard(
        title: 'Excel Import / Export',
        icon: Icons.table_chart_rounded,
        accentColor: AppTheme.warning,
        children: [
          Text(
              'Bulk import medicines from Excel or export your inventory list.',
              style: TextStyle(fontSize: 13, color: context.textMutedColor)),
          const SizedBox(height: 16),
          Row(children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.file_upload, size: 18),
              label: const Text('Import'),
              onPressed: _importExcel,
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.file_download, size: 18),
              label: const Text('Export'),
              style:
                  OutlinedButton.styleFrom(foregroundColor: AppTheme.primary),
              onPressed: _exportExcel,
            ),
          ]),
        ],
      ),
      const SizedBox(height: 20),
      _SettingsCard(
        title: 'Backup & Restore',
        icon: Icons.backup_rounded,
        accentColor: AppTheme.warning,
        children: [
          Text('Create a backup or restore your database.',
              style: TextStyle(fontSize: 13, color: context.textMutedColor)),
          const SizedBox(height: 16),
          Row(children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Backup'),
              onPressed: _backupDatabase,
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Restore'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
              onPressed: _restoreDatabase,
            ),
          ]),
        ],
      ),
    ]);
  }

  Widget _buildUsersSection(AuthProvider auth) {
    return _SettingsCard(
      title: 'User Management',
      icon: Icons.people_rounded,
      accentColor: AppTheme.success,
      children: [
        ...auth.getAllUsers().map((u) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                  child: Text(u.name[0].toUpperCase(),
                      style: const TextStyle(color: AppTheme.primary)),
                ),
                title: Text(u.name),
                subtitle: Text(u.role),
                trailing: u.role == 'admin' || auth.currentUser?.id == u.id
                    ? TextButton(
                        onPressed: () => _changePinDialog(context, u, auth),
                        child: const Text('Change PIN'))
                    : null,
              ),
            )),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
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
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('PIN updated'),
                      backgroundColor: AppTheme.success));
                }
              },
              child: const Text('Update')),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final Color color;
  _NavItem(this.icon, this.label, this.color);
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final List<Widget> children;

  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: accentColor),
              ),
              const SizedBox(width: 12),
              Text(title,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: accentColor)),
            ]),
          ),
          Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: children)),
        ],
      ),
    );
  }
}
