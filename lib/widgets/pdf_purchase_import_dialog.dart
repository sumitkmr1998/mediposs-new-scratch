import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../shared/models/medicine.dart';
import '../shared/models/purchase_record.dart';
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
  Set<String> _duplicateInvoices = {};

  List<_EditablePurchaseRow> _rows = [];

  void _removeInvoice(String invoiceNo) {
    setState(() {
      _parsedInvoices.removeWhere((inv) => inv.invoiceNo == invoiceNo);
      _rows.removeWhere((row) => row.invoiceNo == invoiceNo);
      _duplicateInvoices.remove(invoiceNo);
      _selectedSummaryText = _parsedInvoices.isEmpty
          ? ''
          : 'Importing ${_parsedInvoices.length} PDF Invoices (${_rows.length} Items Total)';
    });
  }

  void _removeRow(_EditablePurchaseRow row) {
    setState(() {
      _rows.remove(row);
      // Check if invoice has any remaining rows
      final invNo = row.invoiceNo;
      if (!_rows.any((r) => r.invoiceNo == invNo)) {
        _parsedInvoices.removeWhere((inv) => inv.invoiceNo == invNo);
        _duplicateInvoices.remove(invNo);
      }
      _selectedSummaryText = _parsedInvoices.isEmpty
          ? ''
          : 'Importing ${_parsedInvoices.length} PDF Invoices (${_rows.length} Items Total)';
    });
  }

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
        final Set<String> dupes = {};

        // Query active PurchaseRecords to check if invoice entry is currently active in purchase logs
        final activePurchases = ObjectBoxService.instance.purchaseBox.getAll();
        final pastInvoiceNosInLogs = <String>{};
        for (var p in activePurchases) {
          if (p.note.isNotEmpty && p.note.contains('Invoice')) {
            final match = RegExp(r'Invoice\s+([A-Z0-9-]+)').firstMatch(p.note);
            if (match != null && match.group(1) != null) {
              pastInvoiceNosInLogs.add(match.group(1)!);
            }
          }
        }

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

            if (pastInvoiceNosInLogs.contains(invoice.invoiceNo)) {
              dupes.add(invoice.invoiceNo);
            }

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
        _duplicateInvoices = dupes;
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

    // 1. Strict Exact Name match
    if (search.isNotEmpty) {
      for (var m in all) {
        if (m.name.toLowerCase().trim() == search) return m;
      }
    }

    // 2. Exact HSN Code Match (Matches medicines that were previously saved/linked with this HSN!)
    if (item.hsn.isNotEmpty) {
      for (var m in all) {
        if (m.hsnCode.isNotEmpty && m.hsnCode == item.hsn) return m;
      }
    }

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

          final isMobile = MediaQuery.of(context).size.width < 700;

          return AlertDialog(
            insetPadding: isMobile ? const EdgeInsets.symmetric(horizontal: 10, vertical: 16) : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            title: Row(
              children: [
                const Icon(Icons.compare_arrows_rounded, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Link Medicine for "${row.originalItem.name}"',
                    style: TextStyle(fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: isMobile ? MediaQuery.of(context).size.width * 0.95 : 550,
              height: isMobile ? MediaQuery.of(context).size.height * 0.75 : 480,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    style: TextStyle(fontSize: isMobile ? 12 : 14),
                    decoration: InputDecoration(
                      hintText: 'Type to search existing medicines...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    dense: isMobile,
                    tileColor: AppTheme.warning.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    leading: const Icon(Icons.add_circle_outline, color: AppTheme.warning),
                    title: Text(
                      'Create as New Medicine ("${row.originalItem.name}")',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 11 : 13),
                    ),
                    subtitle: Text(
                      'Will register a new medicine entry with the original PDF product name',
                      style: TextStyle(fontSize: isMobile ? 9 : 11),
                    ),
                    onTap: () {
                      setState(() {
                        row.matchedMedicine = null;
                        row.nameCtrl.text = row.originalItem.name;
                        row.hsnCtrl.text = row.originalItem.hsn;
                      });
                      Navigator.pop(ctx);
                    },
                  ),
                  const Divider(height: 12),
                  Text(
                    'OR Select an Existing Medicine to Link Stock:',
                    style: TextStyle(fontSize: isMobile ? 10 : 12, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No existing medicines found'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final m = filtered[i];
                              return Card(
                                elevation: 0.5,
                                margin: const EdgeInsets.only(bottom: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                                ),
                                child: ListTile(
                                  dense: isMobile,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  leading: const Icon(Icons.medication_outlined, color: AppTheme.primary, size: 20),
                                  title: Text(
                                    m.name,
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 11 : 13),
                                  ),
                                  subtitle: Text(
                                    'HSN: ${m.hsnCode.isEmpty ? 'N/A' : m.hsnCode} | Price: ₹${m.sellingPrice} | Stock: ${m.mainStock + m.storeStock} Pcs',
                                    style: TextStyle(fontSize: isMobile ? 9 : 11),
                                  ),
                                  trailing: const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 18),
                                  onTap: () {
                                    setState(() {
                                      row.matchedMedicine = m;
                                      row.nameCtrl.text = m.name;

                                      // Save HSN Code to medicine object so future invoices auto-match!
                                      if (row.originalItem.hsn.isNotEmpty) {
                                        m.hsnCode = row.originalItem.hsn;
                                        row.hsnCtrl.text = m.hsnCode;
                                        ObjectBoxService.instance.medicineBox.put(m);
                                      } else if (m.hsnCode.isNotEmpty) {
                                        row.hsnCtrl.text = m.hsnCode;
                                      }

                                      row.mrpCtrl.text = m.sellingPrice.toStringAsFixed(2);
                                      row.priceCtrl.text = m.purchasePrice.toStringAsFixed(2);
                                    });
                                    Navigator.pop(ctx);
                                  },
                                ),
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

    // Show Confirmation Warning Dialog if any invoice is duplicate in active Purchase Logs
    if (_duplicateInvoices.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 28),
              SizedBox(width: 10),
              Text('Duplicate Purchase Invoice Warning'),
            ],
          ),
          content: Text(
            'Purchase entry for Invoice(s) "${_duplicateInvoices.join(', ')}" has already been made in active purchase logs.\n\nAre you sure you want to add duplicate stock entry for this invoice?',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.warning,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, Duplicate Entry'),
            ),
          ],
        ),
      );

      if (proceed != true) return;
    }

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
          // Update HSN, purchase price and MRP
          medicine.purchasePrice = purchasePrice;
          medicine.sellingPrice = mrp;
          if (hsn.isNotEmpty) medicine.hsnCode = hsn;
          ObjectBoxService.instance.medicineBox.put(medicine);
        }

        // Apply batch stock directly via InventoryProvider (Creates active PurchaseRecord entry)
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
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 700;
    final dialogWidth = isMobile ? screenSize.width * 0.96 : (screenSize.width * 0.94).clamp(900.0, 1250.0);
    final dialogHeight = isMobile ? screenSize.height * 0.95 : (screenSize.height * 0.90).clamp(600.0, 850.0);

    return Dialog(
      insetPadding: isMobile ? const EdgeInsets.symmetric(horizontal: 8, vertical: 12) : const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        padding: EdgeInsets.all(isMobile ? 12 : 20),
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
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upload PDF Invoices (Multi-PDF)',
                        style: TextStyle(fontSize: isMobile ? 15 : 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _selectedSummaryText.isEmpty
                            ? 'Select tax invoice PDFs (e.g. Tridha Pharma)'
                            : _selectedSummaryText,
                        style: TextStyle(fontSize: isMobile ? 11 : 12, color: context.textMutedColor),
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
            const Divider(height: 16),

            // Duplicate Invoice Warning Banner with Remove Cross Button
            if (_duplicateInvoices.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.warning),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '⚠️ WARNING: Invoice Entry Already Made!',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _duplicateInvoices.map((invNo) {
                        return Chip(
                          backgroundColor: Colors.orange.withValues(alpha: 0.2),
                          label: Text(
                            'Invoice $invNo [Remove]',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 14, color: AppTheme.danger),
                          onDeleted: () => _removeInvoice(invNo),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],

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
              // Invoice Summary Header Badges with Remove Cross Button
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _parsedInvoices.map((inv) {
                    final isClinic = inv.targetLocation == 'bulkClinic';
                    final isDupe = _duplicateInvoices.contains(inv.invoiceNo);

                    return Container(
                      margin: const EdgeInsets.only(right: 8, bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (isDupe ? AppTheme.warning : (isClinic ? AppTheme.success : AppTheme.primary)).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isDupe ? AppTheme.warning : (isClinic ? AppTheme.success : AppTheme.primary).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('Invoice ${inv.invoiceNo}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  if (isDupe) const Text(' [DUPLICATE]', style: TextStyle(color: AppTheme.warning, fontWeight: FontWeight.bold, fontSize: 9)),
                                ],
                              ),
                              Text(
                                isClinic ? '➔ CLINIC BULK' : '➔ STORE BULK',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isClinic ? AppTheme.success : AppTheme.primary),
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _removeInvoice(inv.invoiceNo),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: AppTheme.danger.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: AppTheme.danger),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 4),

              // Responsive Content: Android Card List vs Desktop DataTable
              Expanded(
                child: isMobile
                    ? ListView.builder(
                        itemCount: _rows.length,
                        itemBuilder: (ctx, idx) {
                          final row = _rows[idx];
                          final isMatched = row.matchedMedicine != null;
                          final isClinic = row.targetLocation == 'bulkClinic';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Invoice & Location Header
                                  Row(
                                    children: [
                                      Text(
                                        'Invoice ${row.invoiceNo}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                      const SizedBox(width: 8),
                                      DropdownButton<String>(
                                        value: row.targetLocation,
                                        isDense: true,
                                        underline: const SizedBox(),
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isClinic ? AppTheme.success : AppTheme.primary),
                                        items: const [
                                          DropdownMenuItem(value: 'bulkClinic', child: Text('Clinic Bulk')),
                                          DropdownMenuItem(value: 'bulkStore', child: Text('Store Bulk')),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) setState(() => row.targetLocation = val);
                                        },
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 16, color: AppTheme.danger),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        tooltip: 'Remove Item',
                                        onPressed: () => _removeRow(row),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  // Item Name Input
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: row.nameCtrl,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                          decoration: InputDecoration(
                                            labelText: 'Medicine Name',
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.search, color: AppTheme.primary),
                                        onPressed: () => _showMedicinePickerModal(row),
                                      ),
                                    ],
                                  ),
                                  InkWell(
                                    onTap: () => _showMedicinePickerModal(row),
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                                      child: Text(
                                        isMatched ? '✓ Matched: ${row.matchedMedicine!.name}' : '+ New Item (Tap to Link)',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isMatched ? AppTheme.success : AppTheme.warning,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Touch Input Fields Grid (2-Column)
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: row.hsnCtrl,
                                          style: const TextStyle(fontSize: 11),
                                          decoration: InputDecoration(
                                            labelText: 'HSN',
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: row.batchCtrl,
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                          decoration: InputDecoration(
                                            labelText: 'Batch',
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Exp: ${row.expiryDate.month.toString().padLeft(2, '0')}/${row.expiryDate.year}',
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: row.mrpCtrl,
                                          keyboardType: TextInputType.number,
                                          style: const TextStyle(fontSize: 11),
                                          decoration: InputDecoration(
                                            labelText: 'MRP ₹',
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: row.priceCtrl,
                                          keyboardType: TextInputType.number,
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                                          decoration: InputDecoration(
                                            labelText: 'Cost Rate ₹',
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: row.qtyCtrl,
                                          keyboardType: TextInputType.number,
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                          decoration: InputDecoration(
                                            labelText: 'Qty',
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columnSpacing: 14,
                            headingRowHeight: 42,
                            dataRowMinHeight: 60,
                            dataRowMaxHeight: 68,
                            columns: const [
                              DataColumn(label: SizedBox(width: 130, child: Text('Invoice / Target', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                              DataColumn(label: SizedBox(width: 230, child: Text('Item Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                              DataColumn(label: SizedBox(width: 95, child: Text('HSN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                              DataColumn(label: SizedBox(width: 110, child: Text('Batch No.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                              DataColumn(label: SizedBox(width: 90, child: Text('Exp Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                              DataColumn(label: SizedBox(width: 90, child: Text('MRP ₹', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                              DataColumn(label: SizedBox(width: 95, child: Text('Cost Rate ₹', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                              DataColumn(label: SizedBox(width: 70, child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                              DataColumn(label: SizedBox(width: 40, child: Text('', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                            ],
                            rows: _rows.map((row) {
                              final isMatched = row.matchedMedicine != null;
                              final isClinic = row.targetLocation == 'bulkClinic';

                              return DataRow(
                                cells: [
                                  DataCell(
                                    SizedBox(
                                      width: 130,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(row.invoiceNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                          DropdownButton<String>(
                                            value: row.targetLocation,
                                            isDense: true,
                                            underline: const SizedBox(),
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isClinic ? AppTheme.success : AppTheme.primary),
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
                                  DataCell(
                                    SizedBox(
                                      width: 230,
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
                                                  decoration: InputDecoration(
                                                    isDense: true,
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.search, size: 18, color: AppTheme.primary),
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
                                      width: 95,
                                      child: TextField(
                                        controller: row.hsnCtrl,
                                        style: const TextStyle(fontSize: 12),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: 110,
                                      child: TextField(
                                        controller: row.batchCtrl,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: 90,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '${row.expiryDate.month.toString().padLeft(2, '0')}/${row.expiryDate.year}',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: 90,
                                      child: TextField(
                                        controller: row.mrpCtrl,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(fontSize: 12),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: 95,
                                      child: TextField(
                                        controller: row.priceCtrl,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: 70,
                                      child: TextField(
                                        controller: row.qtyCtrl,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 16, color: AppTheme.danger),
                                      tooltip: 'Remove Item',
                                      onPressed: () => _removeRow(row),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
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
                    label: Text(isMobile ? 'More' : 'Select More PDFs'),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _confirmAndImport,
                    icon: const Icon(Icons.check_circle_rounded),
                    label: Text(isMobile ? 'Confirm (${_rows.length})' : 'Confirm & Add All ${_rows.length} Items to Stock'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 12),
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
