import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../shared/models/medicine.dart';
import '../shared/providers/inventory_provider.dart';
import '../shared/providers/auth_provider.dart';
import '../shared/services/objectbox_service.dart';
import '../shared/services/pdf_purchase_parser_service.dart';
import '../theme/app_theme.dart';
import '../objectbox.g.dart';

class PdfPurchaseImportDialog extends StatefulWidget {
  const PdfPurchaseImportDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PdfPurchaseImportDialog(),
    );
  }

  @override
  State<PdfPurchaseImportDialog> createState() => _PdfPurchaseImportDialogState();
}

class _PdfPurchaseImportDialogState extends State<PdfPurchaseImportDialog> {
  List<ParsedPurchaseInvoice> _parsedInvoices = [];
  bool _isLoading = false;
  String _selectedSummaryText = '';

  List<_EditablePurchaseRow> _rows = [];

  Future<void> _pickAndParsePdf() async {
    setState(() => _isLoading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final List<ParsedPurchaseInvoice> invoices = [];
        final List<_EditablePurchaseRow> newRows = [];

        if (!mounted) return;
        final allMedicines = context.read<InventoryProvider>().medicines;

        for (var file in result.files) {
          Uint8List? bytes = file.bytes;
          if (bytes == null && file.path != null) {
            bytes = await File(file.path!).readAsBytes();
          }

          if (bytes != null) {
            final invoice = PdfPurchaseParserService.parsePdfBytes(bytes);
            invoices.add(invoice);

            for (var item in invoice.items) {
              final match = _findBestMatch(item, allMedicines);

              newRows.add(_EditablePurchaseRow(
                invoiceNo: invoice.invoiceNo,
                supplierName: invoice.supplierName,
                billTo: invoice.billToName,
                targetLocation: invoice.targetLocation,
                originalItem: item,
                matchedMedicine: match,
                nameCtrl: TextEditingController(text: match?.name ?? item.name),
                hsnCtrl: TextEditingController(text: match?.hsnCode.isNotEmpty == true ? match!.hsnCode : item.hsn),
                batchCtrl: TextEditingController(text: item.batchNo),
                mrpCtrl: TextEditingController(text: (match?.sellingPrice ?? item.mrp).toStringAsFixed(2)),
                priceCtrl: TextEditingController(text: (match?.purchasePrice ?? item.purchasePrice).toStringAsFixed(2)),
                qtyCtrl: TextEditingController(text: item.qty.toString()),
                expiryDate: item.expiryDate,
              ));
            }
          }
        }

        _parsedInvoices = invoices;
        _rows = newRows;
        _selectedSummaryText = 'Importing ${invoices.length} PDF Invoices (${newRows.length} Items Total)';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to parse PDFs: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Medicine? _findBestMatch(ParsedPurchaseItem item, List<Medicine> all) {
    final search = item.name.toLowerCase().trim();
    if (search.isEmpty) return null;

    // Strict Exact Name match only
    for (var m in all) {
      if (m.name.toLowerCase().trim() == search) return m;
    }

    // Exact HSN Match if present
    if (item.hsn.isNotEmpty) {
      for (var m in all) {
        if (m.hsnCode.isNotEmpty && m.hsnCode == item.hsn) return m;
      }
    }

    // Default to null if name is different
    return null;
  }

  void _showMedicinePickerModal(_EditablePurchaseRow row) {
    final allMedicines = context.read<InventoryProvider>().medicines;
    final searchCtrl = TextEditingController(text: row.originalItem.name);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final query = searchCtrl.text.toLowerCase().trim();
          final filtered = allMedicines.where((m) {
            return query.isEmpty ||
                m.name.toLowerCase().contains(query) ||
                m.barcode.contains(query) ||
                m.hsnCode.contains(query);
          }).toList();

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.compare_arrows_rounded, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Link Medicine for "${row.originalItem.name}"',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 450,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Type to search existing inventory medicines...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    tileColor: AppTheme.warning.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    leading: const Icon(Icons.add_circle_outline, color: AppTheme.warning),
                    title: Text('Create as New Medicine ("${row.originalItem.name}")', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Will register a new medicine entry with the original PDF product name'),
                    onTap: () {
                      setState(() {
                        row.matchedMedicine = null;
                        row.nameCtrl.text = row.originalItem.name;
                        row.hsnCtrl.text = row.originalItem.hsn;
                      });
                      Navigator.pop(ctx);
                    },
                  ),
                  const Divider(height: 16),
                  const Text('OR Select an Existing Medicine to Link Stock:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No existing medicines found'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final m = filtered[i];
                              return ListTile(
                                leading: const Icon(Icons.medication_outlined, color: AppTheme.primary),
                                title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('HSN: ${m.hsnCode.isEmpty ? 'N/A' : m.hsnCode} | Price: ₹${m.sellingPrice} | Stock: ${m.mainStock + m.storeStock} Pcs'),
                                trailing: const Icon(Icons.check_circle_outline, color: AppTheme.success),
                                onTap: () {
                                  setState(() {
                                    row.matchedMedicine = m;
                                    row.nameCtrl.text = m.name;
                                    if (m.hsnCode.isNotEmpty) row.hsnCtrl.text = m.hsnCode;
                                    row.mrpCtrl.text = m.sellingPrice.toStringAsFixed(2);
                                    row.priceCtrl.text = m.purchasePrice.toStringAsFixed(2);
                                  });
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmAndImport() async {
    if (_rows.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final invProvider = context.read<InventoryProvider>();
      final actor = context.read<AuthProvider>().currentUser;

      int importedCount = 0;

      for (var row in _rows) {
        final name = row.nameCtrl.text.trim();
        final hsn = row.hsnCtrl.text.trim();
        final batchNo = row.batchCtrl.text.trim();
        final mrp = double.tryParse(row.mrpCtrl.text) ?? 0.0;
        final purchasePrice = double.tryParse(row.priceCtrl.text) ?? 0.0;
        final qty = int.tryParse(row.qtyCtrl.text) ?? 0;
        if (qty <= 0) continue;

        Medicine? medicine = row.matchedMedicine;
        medicine ??= ObjectBoxService.instance.medicineBox
            .query(Medicine_.name.equals(name))
            .build()
            .findFirst();

        if (medicine == null) {
          // Create new medicine
          final barcode = 'BC-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';
          medicine = Medicine(
            name: name,
            barcode: barcode,
            hsnCode: hsn,
            purchasePrice: purchasePrice,
            sellingPrice: mrp,
            mainStock: 0,
            storeStock: 0,
            bulkClinicStock: 0,
            bulkStoreStock: 0,
            createdAt: DateTime.now(),
          );
          ObjectBoxService.instance.medicineBox.put(medicine);
        } else {
          // Update HSN, purchase price and MRP if changed
          medicine.purchasePrice = purchasePrice;
          medicine.sellingPrice = mrp;
          if (hsn.isNotEmpty) medicine.hsnCode = hsn;
          ObjectBoxService.instance.medicineBox.put(medicine);
        }

        // Apply batch stock directly via InventoryProvider
        invProvider.addBatchStock(
          {medicine.id: 0},
          bulkClinicUpdates: row.targetLocation == 'bulkClinic' ? {medicine.id: qty} : {},
          bulkStoreUpdates: row.targetLocation == 'bulkStore' ? {medicine.id: qty} : {},
          batchNo: batchNo,
          expiryDate: row.expiryDate,
          supplier: row.supplierName,
          note: 'PDF Invoice ${row.invoiceNo} (${row.targetLocation == 'bulkClinic' ? 'Clinic Bulk' : 'Store Bulk'})',
          actor: actor,
        );

        importedCount++;
      }

      invProvider.load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully imported $importedCount items from ${_parsedInvoices.length} PDF Invoices!'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import stock: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 700;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isDesktop ? 1000 : double.infinity,
        height: isDesktop ? 700 : MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Upload PDF Purchase Invoices (Multi-PDF)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _selectedSummaryText.isEmpty
                            ? 'Select one or multiple tax invoice PDFs (e.g. Tridha Pharmaceuticals)'
                            : _selectedSummaryText,
                        style: TextStyle(fontSize: 12, color: context.textMutedColor),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 24),

            if (_parsedInvoices.isEmpty && !_isLoading) ...[
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_upload_outlined, size: 64, color: AppTheme.primary.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      const Text(
                        'Upload One or Multiple Purchase Invoice PDFs',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select multiple PDFs at once. Automatically parses invoice line items, batches, expiry dates, rates, and routes stock to Clinic Bulk or Store Bulk per invoice.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: context.textMutedColor),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _pickAndParsePdf,
                        icon: const Icon(Icons.file_open_rounded),
                        label: const Text('Select PDF Files (Multi-Select)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (_isLoading) ...[
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Parsing Multiple PDF Invoices & Matching Batches...'),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // Invoice Summary Header Cards
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _parsedInvoices.map((inv) {
                    final isClinic = inv.targetLocation == 'bulkClinic';
                    return Container(
                      margin: const EdgeInsets.only(right: 12, bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: (isClinic ? AppTheme.success : AppTheme.primary).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: (isClinic ? AppTheme.success : AppTheme.primary).withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Invoice ${inv.invoiceNo} (${inv.items.length} items)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          Text('Bill To: ${inv.billToName}', style: TextStyle(fontSize: 10, color: context.textMutedColor)),
                          Text(
                            isClinic ? '➔ CLINIC BULK' : '➔ STORE BULK',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isClinic ? AppTheme.success : AppTheme.primary),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),

              // Multi-Invoice Line Items Table
              Expanded(
                child: SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 10,
                    headingRowHeight: 40,
                    dataRowMinHeight: 56,
                    dataRowMaxHeight: 64,
                    columns: const [
                      DataColumn(label: Text('Invoice / Target', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      DataColumn(label: Text('Item Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      DataColumn(label: Text('HSN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      DataColumn(label: Text('Batch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      DataColumn(label: Text('Exp Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      DataColumn(label: Text('MRP ₹', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      DataColumn(label: Text('Cost Rate ₹', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      DataColumn(label: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                    ],
                    rows: _rows.map((row) {
                      final isMatched = row.matchedMedicine != null;
                      final isClinic = row.targetLocation == 'bulkClinic';

                      return DataRow(
                        cells: [
                          // Invoice & Target Location Column
                          DataCell(
                            SizedBox(
                              width: 110,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(row.invoiceNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  DropdownButton<String>(
                                    value: row.targetLocation,
                                    isDense: true,
                                    underline: const SizedBox(),
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isClinic ? AppTheme.success : AppTheme.primary),
                                    items: const [
                                      DropdownMenuItem(value: 'bulkClinic', child: Text('Clinic Bulk')),
                                      DropdownMenuItem(value: 'bulkStore', child: Text('Store Bulk')),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) setState(() => row.targetLocation = val);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Item Name & Match Status Column
                          DataCell(
                            SizedBox(
                              width: 210,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: row.nameCtrl,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.search, size: 16, color: AppTheme.primary),
                                        tooltip: 'Select / Link Existing Medicine',
                                        onPressed: () => _showMedicinePickerModal(row),
                                      ),
                                    ],
                                  ),
                                  InkWell(
                                    onTap: () => _showMedicinePickerModal(row),
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        isMatched ? '✓ Matched: ${row.matchedMedicine!.name}' : '+ New Item (Tap to Link)',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isMatched ? AppTheme.success : AppTheme.warning,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 70,
                              child: TextField(
                                controller: row.hsnCtrl,
                                style: const TextStyle(fontSize: 11),
                                decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 85,
                              child: TextField(
                                controller: row.batchCtrl,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${row.expiryDate.month.toString().padLeft(2, '0')}/${row.expiryDate.year}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 60,
                              child: TextField(
                                controller: row.mrpCtrl,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 11),
                                decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 60,
                              child: TextField(
                                controller: row.priceCtrl,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                                decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 45,
                              child: TextField(
                                controller: row.qtyCtrl,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),

              const Divider(),
              // Bottom Action Bar
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickAndParsePdf,
                    icon: const Icon(Icons.file_open_rounded, size: 16),
                    label: const Text('Select More PDFs'),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _confirmAndImport,
                    icon: const Icon(Icons.check_circle_rounded),
                    label: Text('Confirm & Add All ${_rows.length} Items to Stock'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditablePurchaseRow {
  final String invoiceNo;
  final String supplierName;
  final String billTo;
  String targetLocation; // 'bulkClinic' or 'bulkStore'
  final ParsedPurchaseItem originalItem;
  Medicine? matchedMedicine;
  final TextEditingController nameCtrl;
  final TextEditingController hsnCtrl;
  final TextEditingController batchCtrl;
  final TextEditingController mrpCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController qtyCtrl;
  DateTime expiryDate;

  _EditablePurchaseRow({
    required this.invoiceNo,
    required this.supplierName,
    required this.billTo,
    required this.targetLocation,
    required this.originalItem,
    this.matchedMedicine,
    required this.nameCtrl,
    required this.hsnCtrl,
    required this.batchCtrl,
    required this.mrpCtrl,
    required this.priceCtrl,
    required this.qtyCtrl,
    required this.expiryDate,
  });
}
