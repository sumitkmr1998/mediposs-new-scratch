import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../models/invoice.dart';
import '../models/prescription.dart';
import '../models/patient.dart';
import '../services/objectbox_service.dart';
import '../services/invoice_generator.dart';
import '../../objectbox.g.dart';
import 'package:objectbox/objectbox.dart';

class PrintingService {
  static final PrintingService instance = PrintingService._();

  PrintingService._();
  
  Future<Uint8List> _generateReceiptBytes(Sale sale, PdfPageFormat format) async {
    final settings = ObjectBoxService.instance.settings;
    
    // Resolve header details based on whether this is a Clinical Dispense
    final headerName = sale.isClinicalDispense 
        ? ((settings.clinicName?.isNotEmpty ?? false) ? settings.clinicName! : 'MediPoss Clinic')
        : ((settings.storeName?.isNotEmpty ?? false) ? settings.storeName! : 'MediPoss Store');
        
    final headerAddress = sale.isClinicalDispense
        ? ((settings.clinicAddress?.isNotEmpty ?? false) ? settings.clinicAddress! : 'Address not set')
        : ((settings.storeAddress?.isNotEmpty ?? false) ? settings.storeAddress! : 'Address not set');
        
    final headerPhone = sale.isClinicalDispense
        ? ((settings.clinicPhone?.isNotEmpty ?? false) ? settings.clinicPhone! : 'Phone not set')
        : ((settings.storePhone?.isNotEmpty ?? false) ? settings.storePhone! : 'Phone not set');

    // Try to resolve related doctor name for display on the receipt
    String doctorName = '';
    Prescription? prescription;
    if (sale.linkedAppointmentId != 0) {
      prescription = ObjectBoxService.instance.store.box<Prescription>()
          .query(Prescription_.appointmentId.equals(sale.linkedAppointmentId))
          .build()
          .findFirst();
    }
    if (prescription == null && sale.patientId != 0) {
      prescription = ObjectBoxService.instance.store.box<Prescription>()
          .query(Prescription_.patientId.equals(sale.patientId))
          .order(Prescription_.createdAt, flags: Order.descending)
          .build()
          .findFirst();
    }
    if (prescription != null) {
      doctorName = prescription.doctorName;
    }

    final doc = pw.Document();

    // Rehydrate sale items from JSON
    final List<dynamic> decoded = jsonDecode(sale.itemsJson);
    final items = decoded.map((j) => SaleItem.fromJson(j)).toList();

    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(12),
        build: (pw.Context context) {
          final isRoll = format == PdfPageFormat.roll80;
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: isRoll ? pw.MainAxisSize.min : pw.MainAxisSize.max,
            children: [
              // Store Header
              pw.Text(headerName,
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 16),
                  textAlign: pw.TextAlign.center),
              if (headerAddress.isNotEmpty && headerAddress != 'Address not set')
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Text(headerAddress,
                      style: const pw.TextStyle(fontSize: 10),
                      textAlign: pw.TextAlign.center),
                ),
              if (headerPhone.isNotEmpty && headerPhone != 'Phone not set')
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Text('Tel: $headerPhone',
                      style: const pw.TextStyle(fontSize: 10),
                      textAlign: pw.TextAlign.center),
                ),
              if (sale.isClinicalDispense) ...[
                if (settings.clinicRegNo != null && settings.clinicRegNo!.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Text('Reg No: ${settings.clinicRegNo}',
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.center),
                  ),
              ] else ...[
                if (settings.gstNumber != null && settings.gstNumber!.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Text('GST: ${settings.gstNumber}',
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.center),
                  ),
              ],
              pw.SizedBox(height: 8),

              // Title: Cash vs Return
              pw.Text(
                sale.isClinicalDispense
                    ? 'CLINICAL DISPENSE SLIP'
                    : (settings.isCompositionScheme
                        ? (sale.isReturn ? 'BILL OF SUPPLY (RETURN)' : 'BILL OF SUPPLY')
                        : (sale.isReturn ? 'RETURN RECEIPT' : 'CASH RECEIPT')),
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
              ),
              if (settings.isCompositionScheme && !sale.isClinicalDispense) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  'Composition taxable person, not eligible to collect tax on supplies',
                  style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
              ],
              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              // Meta
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Invoice: ${sale.invoiceNo}',
                      style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(DateFormat('dd/MM/yyyy HH:mm').format(sale.createdAt),
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              if (sale.patientName.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Patient: ${sale.patientName}',
                        style: const pw.TextStyle(fontSize: 10)),
                    if (sale.patientPhone.isNotEmpty)
                      pw.Text(sale.patientPhone,
                          style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ],
              if (doctorName.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Doctor: Dr. $doctorName',
                        style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ],
              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              // Items Header
              pw.Row(
                children: [
                  pw.Expanded(
                      flex: 3,
                      child: pw.Text('Item',
                          style: const pw.TextStyle(fontSize: 10))),
                  pw.Expanded(
                      flex: 1,
                      child: pw.Text('Qty',
                          style: const pw.TextStyle(fontSize: 10),
                          textAlign: pw.TextAlign.right)),
                  pw.Expanded(
                      flex: 2,
                      child: pw.Text('Price',
                          style: const pw.TextStyle(fontSize: 10),
                          textAlign: pw.TextAlign.right)),
                  pw.Expanded(
                      flex: 2,
                      child: pw.Text('Total',
                          style: const pw.TextStyle(fontSize: 10),
                          textAlign: pw.TextAlign.right)),
                ],
              ),
              pw.SizedBox(height: 4),

              // Items List
              ...items.map((item) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                            flex: 3,
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                    item.isProcedure
                                        ? '[P] ${item.medicineName}'
                                        : item.medicineName,
                                    style: const pw.TextStyle(fontSize: 10)),
                                if (!item.isProcedure &&
                                    item.batchNo.isNotEmpty &&
                                    (sale.isClinicalDispense
                                        ? settings.showBatchExpiryInClinicalPrint
                                        : settings.showBatchExpiryInRetailPrint))
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.only(top: 1),
                                    child: pw.Text(
                                        'Batch: ${item.batchNo} | Exp: ${item.expiryDate}',
                                        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                                  ),
                              ],
                            )),
                        pw.Expanded(
                            flex: 1,
                            child: pw.Text('${item.qty.abs()}',
                                style: const pw.TextStyle(fontSize: 10),
                                textAlign: pw.TextAlign.right)),
                        pw.Expanded(
                            flex: 2,
                            child: pw.Text(item.unitPrice.toStringAsFixed(2),
                                style: const pw.TextStyle(fontSize: 10),
                                textAlign: pw.TextAlign.right)),
                        pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                                item.lineTotal.abs().toStringAsFixed(2),
                                style: const pw.TextStyle(fontSize: 10),
                                textAlign: pw.TextAlign.right)),
                      ],
                    ),
                  )),

              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              // Totals
              _buildTotalRow('Subtotal', sale.subtotal),
              if (sale.discount > 0) _buildTotalRow('Discount', sale.discount),
              if (sale.taxAmount > 0 && !sale.isClinicalDispense) _buildTotalRow('Tax', sale.taxAmount),

              pw.SizedBox(height: 2),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Net Total',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 13)),
                  pw.Text('Rs. ${sale.total.abs().toStringAsFixed(2)}',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 13)),
                ],
              ),
              pw.SizedBox(height: 4),

              // Payment Split (if any)
              if (sale.paymentMethod == 'mixed') ...[
                if (sale.cashAmount.abs() > 0)
                  _buildTotalRow('Paid Cash', sale.cashAmount),
                if (sale.upiAmount.abs() > 0)
                  _buildTotalRow('Paid UPI', sale.upiAmount),
                if (sale.cardAmount.abs() > 0)
                  _buildTotalRow('Paid Card', sale.cardAmount),
              ] else ...[
                _buildTotalRow('Paid via', 0,
                    stringValue: sale.paymentMethod.toUpperCase()),
              ],

              if (isRoll) pw.SizedBox(height: 12) else pw.Spacer(),
              // Footer
              if (settings.receiptFooterMessage.isNotEmpty)
                pw.Text(settings.receiptFooterMessage,
                    style: const pw.TextStyle(fontSize: 10),
                    textAlign: pw.TextAlign.center),
              pw.Text('Powered by MediPoss',
                  style:
                      const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  textAlign: pw.TextAlign.center),
            ],
          );
        },
      ),
    );

    return doc.save();
  }
  
  Future<Uint8List> _generateTestPrintBytes(PdfPageFormat format) async {
    final settings = ObjectBoxService.instance.settings;
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(12),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          mainAxisSize: settings.receiptPaperSize == 'Roll80'
              ? pw.MainAxisSize.min
              : pw.MainAxisSize.max,
          children: [
            pw.Text('TEST PRINT SUCCESSFUL',
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
            pw.SizedBox(height: 8),
            pw.Text(
                'Hardware: ${settings.defaultPrinterName.isNotEmpty ? settings.defaultPrinterName : "None (Preview)"}'),
            pw.Text('Auto Print: ${settings.autoPrintReceipt ? "ON" : "OFF"}'),
            pw.Text('Paper Size: ${settings.receiptPaperSize}'),
            if (settings.gstNumber.isNotEmpty)
              pw.Text('GST Registered: ${settings.gstNumber}'),
            pw.SizedBox(height: 24),
            pw.Text(
                'If this printed cleanly and the margins look correct, your configuration is perfect.'),
            if (format == PdfPageFormat.roll80)
              pw.SizedBox(height: 12)
            else
              pw.Spacer(),
            pw.Divider(borderStyle: pw.BorderStyle.dashed),
            if (settings.receiptFooterMessage.isNotEmpty)
              pw.Text(settings.receiptFooterMessage,
                  textAlign: pw.TextAlign.center),
            pw.Text('Powered by MediPoss',
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        );
      },
    ));
    return doc.save();
  }

  Future<void> printReceipt(BuildContext context, Sale sale) async {
    final settings = ObjectBoxService.instance.settings;

    // Resolve Page Format
    PdfPageFormat format;
    switch (settings.receiptPaperSize) {
      case 'A6':
        format = PdfPageFormat.a6;
        break;
      case 'Letter':
        format = PdfPageFormat.letter;
        break;
      case 'A4':
        format = PdfPageFormat.a4;
        break;
      case 'Roll80':
      default:
        format = PdfPageFormat.roll80;
        break;
    }

    if (settings.autoPrintReceipt && settings.defaultPrinterName.isNotEmpty) {
      final bytes = await _generateReceiptBytes(sale, format);
      await Printing.directPrintPdf(
        printer: Printer(url: settings.defaultPrinterName),
        onLayout: (PdfPageFormat f) async => bytes,
        name: 'Receipt_${sale.invoiceNo}',
      );
    } else {
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): () async {
                final bytes = await _generateReceiptBytes(sale, format);
                await Printing.layoutPdf(
                  onLayout: (PdfPageFormat f) async => bytes,
                  name: 'Receipt_${sale.invoiceNo}',
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              const SingleActivator(LogicalKeyboardKey.escape): () {
                if (ctx.mounted) Navigator.pop(ctx);
              },
            },
            child: Focus(
              autofocus: true,
              child: Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(24),
                child: Container(
                  width: 500,
                  height: 700,
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: PdfPreview(
                      build: (f) async => await _generateReceiptBytes(sale, f),
                      initialPageFormat: format,
                      allowSharing: false,
                      canChangeOrientation: false,
                      canChangePageFormat: true,
                      pageFormats: const {
                        'A4': PdfPageFormat.a4,
                        'A5': PdfPageFormat.a5,
                        'A6': PdfPageFormat.a6,
                        'Letter': PdfPageFormat.letter,
                        'Roll 80mm': PdfPageFormat.roll80,
                      },
                      canDebug: false,
                      pdfFileName: 'Receipt_${sale.invoiceNo}.pdf',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
  }

  pw.Widget _buildTotalRow(String label, double amount, {String? stringValue}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          pw.Text(stringValue ?? amount.abs().toStringAsFixed(2),
              style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  Future<void> printInvoice(BuildContext context, Invoice invoice) async {
    final settings = ObjectBoxService.instance.settings;
    PdfPageFormat format;
    switch (settings.receiptPaperSize) {
      case 'A6':
        format = PdfPageFormat.a6;
        break;
      case 'Letter':
        format = PdfPageFormat.letter;
        break;
      case 'A4':
        format = PdfPageFormat.a4;
        break;
      case 'Roll80':
      default:
        format = PdfPageFormat.roll80;
        break;
    }

    if (settings.autoPrintReceipt && settings.defaultPrinterName.isNotEmpty) {
      final pdfBytes = await InvoiceGenerator.generate(invoice, format);
      await Printing.directPrintPdf(
        printer: Printer(url: settings.defaultPrinterName),
        onLayout: (PdfPageFormat f) async => pdfBytes,
        name: 'Invoice_${invoice.patientName}_${invoice.formattedDate}',
      );
    } else {
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): () async {
                await Printing.layoutPdf(
                  onLayout: (PdfPageFormat f) async => await InvoiceGenerator.generate(invoice, f),
                  name: 'Invoice_${invoice.patientName}_${invoice.formattedDate}',
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              const SingleActivator(LogicalKeyboardKey.escape): () {
                if (ctx.mounted) Navigator.pop(ctx);
              },
            },
            child: Focus(
              autofocus: true,
              child: Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(24),
                child: Container(
                  width: 600,
                  height: 800,
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: PdfPreview(
                      build: (f) async => await InvoiceGenerator.generate(invoice, f),
                      initialPageFormat: format,
                      allowSharing: true,
                      canChangeOrientation: true,
                      canChangePageFormat: true,
                      pageFormats: const {
                        'A4': PdfPageFormat.a4,
                        'A5': PdfPageFormat.a5,
                        'A6': PdfPageFormat.a6,
                        'Letter': PdfPageFormat.letter,
                        'Roll 80mm': PdfPageFormat.roll80,
                      },
                      canDebug: false,
                      pdfFileName: 'Invoice_${invoice.patientName}.pdf',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> printSaleAsInvoice(BuildContext context, Sale sale) async {
    final settings = ObjectBoxService.instance.settings;
    
    // Decode items
    final List<dynamic> decoded = jsonDecode(sale.itemsJson);
    final saleItems = decoded.map((j) => SaleItem.fromJson(j)).toList();
    
    // Map to InvoiceItem
    final invoiceItems = saleItems
        .map((si) => InvoiceItem(
              name: si.isProcedure ? '[P] ${si.medicineName}' : si.medicineName,
              quantity: si.qty.abs(),
              rate: si.unitPrice,
              batchNo: si.batchNo,
              expiryDate: si.expiryDate,
            ))
        .toList();

    // Try to find a related prescription for diagnosis/doctor
    String diagnosis = 'General Consultation';
    String doctorName = 'On-Duty Doctor';
    
    // Fetch latest prescription for this patient to get diagnosis/doctor if possible
    Prescription? prescription;
    if (sale.linkedAppointmentId != 0) {
      prescription = ObjectBoxService.instance.store.box<Prescription>()
          .query(Prescription_.appointmentId.equals(sale.linkedAppointmentId))
          .build()
          .findFirst();
    }
    if (prescription == null && sale.patientId != 0) {
      prescription = ObjectBoxService.instance.store.box<Prescription>()
          .query(Prescription_.patientId.equals(sale.patientId))
          .order(Prescription_.createdAt, flags: Order.descending)
          .build()
          .findFirst();
    }
    if (prescription != null) {
      diagnosis = prescription.diagnosis;
      doctorName = prescription.doctorName;
    }

    // Fetch patient UHID
    String patientUhid = 'Walk-in';
    if (sale.patientId != 0) {
      final patient = ObjectBoxService.instance.store.box<Patient>().get(sale.patientId);
      if (patient != null) {
        patientUhid = patient.uhid;
      }
    }

    final invoiceClinicName = sale.isClinicalDispense
        ? ((settings.clinicName?.isNotEmpty ?? false) ? settings.clinicName! : 'MediPoss Clinic')
        : ((settings.storeName?.isNotEmpty ?? false) ? settings.storeName! : 'MediPoss Store');
        
    final invoiceClinicAddress = sale.isClinicalDispense
        ? ((settings.clinicAddress?.isNotEmpty ?? false) ? settings.clinicAddress! : 'Address not set')
        : ((settings.storeAddress?.isNotEmpty ?? false) ? settings.storeAddress! : 'Address not set');
        
    final regNo = sale.isClinicalDispense
        ? ((settings.clinicRegNo?.isNotEmpty ?? false) ? settings.clinicRegNo! : 'N/A')
        : ((settings.gstNumber?.isNotEmpty ?? false) ? settings.gstNumber! : 'N/A');

    final invoice = Invoice(
      invoiceNo: sale.invoiceNo,
      patientId: patientUhid,
      clinicName: invoiceClinicName,
      clinicAddress: invoiceClinicAddress,
      registrationNo: regNo,
      doctorName: doctorName,
      patientName: sale.patientName.isNotEmpty ? sale.patientName : 'Walk-in Patient',
      diagnosis: diagnosis.isNotEmpty ? diagnosis : 'General',
      date: sale.createdAt,
      items: invoiceItems,
      totalAmount: sale.total.abs(),
      isClinicalDispense: sale.isClinicalDispense,
    );

    await printInvoice(context, invoice);
  }

  Future<void> testPrint(BuildContext context) async {
    final settings = ObjectBoxService.instance.settings;

    PdfPageFormat format;
    switch (settings.receiptPaperSize) {
      case 'A6':
        format = PdfPageFormat.a6;
        break;
      case 'Letter':
        format = PdfPageFormat.letter;
        break;
      case 'A4':
        format = PdfPageFormat.a4;
        break;
      case 'Roll80':
      default:
        format = PdfPageFormat.roll80;
        break;
    }

    if (settings.autoPrintReceipt && settings.defaultPrinterName.isNotEmpty) {
      final bytes = await _generateTestPrintBytes(format);
      await Printing.directPrintPdf(
        printer: Printer(url: settings.defaultPrinterName),
        onLayout: (PdfPageFormat f) async => bytes,
        name: 'Test_Print',
      );
    } else {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(24),
            child: Container(
              width: 500,
              height: 700,
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: PdfPreview(
                  build: (f) async => await _generateTestPrintBytes(f),
                  initialPageFormat: format,
                  allowSharing: false,
                  canChangeOrientation: false,
                  canChangePageFormat: true,
                  pageFormats: const {
                    'A4': PdfPageFormat.a4,
                    'A5': PdfPageFormat.a5,
                    'A6': PdfPageFormat.a6,
                    'Letter': PdfPageFormat.letter,
                    'Roll 80mm': PdfPageFormat.roll80,
                  },
                  canDebug: false,
                  pdfFileName: 'Test_Print.pdf',
                ),
              ),
            ),
          ),
        );
      }
    }
  }
}
