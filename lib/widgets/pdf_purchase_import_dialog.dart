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
  ParsedPurchaseInvoice? _parsedInvoice;
  bool _isLoading = false;
  String _targetLocation = 'bulkStore'; // 'bulkClinic' or 'bulkStore'
  String _selectedFileName = '';
  final TextEditingController _invoiceNoCtrl = TextEditingController();
  final TextEditingController _supplierCtrl = TextEditingController();

  List<_EditablePurchaseRow> _rows = [];

  Future<void> _pickAndParsePdf() async {
    setState(() => _isLoading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        _selectedFileName = file.name;
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        }

        if (bytes != null) {
          final invoice = PdfPurchaseParserService.parsePdfBytes(bytes);
          _parsedInvoice = invoice;
          _targetLocation = invoice.targetLocation;
          _invoiceNoCtrl.text = invoice.invoiceNo;
          _supplierCtrl.text = invoice.supplierName;

          if (!mounted) return;
          final allMedicines = context.read<InventoryProvider>().medicines;
          _rows = invoice.items.map((item) {
            final match = allMedicines.where((m) {
              final n1 = m.name.toLowerCase().trim();
              final n2 = item.name.toLowerCase().trim();
              return n1 == n2;
            }).firstOrNull;

            return _EditablePurchaseRow(
              originalItem: item,
              matchedMedicine: match,
              nameCtrl: TextEditingController(text: item.name),
              hsnCtrl: TextEditingController(text: item.hsn),
              batchCtrl: TextEditingController(text: item.batchNo),
              mrpCtrl: TextEditingController(text: item.mrp.toStringAsFixed(2)),
              priceCtrl: TextEditingController(text: item.purchasePrice.toStringAsFixed(2)),
              qtyCtrl: TextEditingController(text: item.qty.toString()),
              expiryDate: item.expiryDate,
            );
          }).toList();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to parse PDF: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmAndImport() async {
    if (_rows.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final invProvider = context.read<InventoryProvider>();
      final actor = context.read<AuthProvider>().currentUser;
      final supplierName = _supplierCtrl.text.trim();
      final invoiceNo = _invoiceNoCtrl.text.trim();

      for (var row in _rows) {
        final name = row.nameCtrl.text.trim();
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
          // Update purchase price and MRP if changed
          medicine.purchasePrice = purchasePrice;
          medicine.sellingPrice = mrp;
          ObjectBoxService.instance.medicineBox.put(medicine);
        }

        // Apply batch stock directly via InventoryProvider
        invProvider.addBatchStock(
          {medicine.id: 0},
          bulkClinicUpdates: _targetLocation == 'bulkClinic' ? {medicine.id: qty} : {},
          bulkStoreUpdates: _targetLocation == 'bulkStore' ? {medicine.id: qty} : {},
          batchNo: batchNo,
          expiryDate: row.expiryDate,
          supplier: supplierName,
          note: 'PDF Invoice $invoiceNo (${_targetLocation == 'bulkClinic' ? 'Clinic Bulk' : 'Store Bulk'})',
          actor: actor,
        );
      }

      invProvider.load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully imported purchase invoice $invoiceNo to ${_targetLocation == 'bulkClinic' ? 'Clinic Bulk' : 'Store Bulk'}!'),
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
        width: isDesktop ? 900 : double.infinity,
        height: isDesktop ? 650 : MediaQuery.of(context).size.height * 0.9,
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
                        'Upload PDF Purchase Invoice',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _selectedFileName.isEmpty
                            ? 'Select a tax invoice PDF (e.g. Tridha Pharmaceuticals)'
                            : _selectedFileName,
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

            if (_parsedInvoice == null && !_isLoading) ...[
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_upload_outlined, size: 64, color: AppTheme.primary.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      const Text(
                        'Upload Supplier Purchase Invoice PDF',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Automatically parses line items, batches, expiry dates, purchase rates, and routes stock to Clinic Bulk or Store Bulk based on Bill To.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: context.textMutedColor),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _pickAndParsePdf,
                        icon: const Icon(Icons.file_open_rounded),
                        label: const Text('Select PDF File'),
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
                      Text('Parsing PDF Invoice & Matching Batches...'),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // Invoice Summary Bar & Target Location Selector
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SUPPLIER: ${_parsedInvoice!.supplierName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('Bill To: ${_parsedInvoice!.billToName}', style: TextStyle(fontSize: 11, color: context.textMutedColor)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _targetLocation,
                        decoration: const InputDecoration(
                          labelText: 'Stock Target Bulk Location',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'bulkClinic',
                            child: Row(
                              children: [
                                Icon(Icons.medical_services_outlined, size: 16, color: AppTheme.success),
                                SizedBox(width: 6),
                                Text('CLINIC BULK (Dispense)', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.success)),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'bulkStore',
                            child: Row(
                              children: [
                                Icon(Icons.storefront_outlined, size: 16, color: AppTheme.primary),
                                SizedBox(width: 6),
                                Text('STORE BULK (Retail)', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _targetLocation = val);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Parsed Line Items Table
              Expanded(
                child: SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 12,
                    headingRowHeight: 40,
                    dataRowMinHeight: 48,
                    dataRowMaxHeight: 56,
                    columns: const [
                      DataColumn(label: Text('Item Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('HSN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('Batch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('Exp Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('MRP ₹', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('Cost Rate ₹', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    ],
                    rows: _rows.map((row) {
                      final isMatched = row.matchedMedicine != null;
                      return DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: 180,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  TextField(
                                    controller: row.nameCtrl,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                                  ),
                                  Text(
                                    isMatched ? '✓ Matched' : '+ New Item',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isMatched ? AppTheme.success : AppTheme.warning,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 75,
                              child: TextField(
                                controller: row.hsnCtrl,
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: row.batchCtrl,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${row.expiryDate.month.toString().padLeft(2, '0')}/${row.expiryDate.year}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 65,
                              child: TextField(
                                controller: row.mrpCtrl,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 65,
                              child: TextField(
                                controller: row.priceCtrl,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                                decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 50,
                              child: TextField(
                                controller: row.qtyCtrl,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
                    label: const Text('Choose Another PDF'),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _confirmAndImport,
                    icon: const Icon(Icons.check_circle_rounded),
                    label: Text('Confirm & Add to ${_targetLocation == 'bulkClinic' ? 'Clinic Bulk' : 'Store Bulk'}'),
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
  final ParsedPurchaseItem originalItem;
  final Medicine? matchedMedicine;
  final TextEditingController nameCtrl;
  final TextEditingController hsnCtrl;
  final TextEditingController batchCtrl;
  final TextEditingController mrpCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController qtyCtrl;
  DateTime expiryDate;

  _EditablePurchaseRow({
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
