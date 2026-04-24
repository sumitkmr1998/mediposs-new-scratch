import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/invoice.dart';

class InvoiceGenerator {
  static Future<Uint8List> generate(Invoice invoice, PdfPageFormat format) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          _buildHeader(invoice),
          pw.SizedBox(height: 20),
          _buildPatientInfo(invoice),
          pw.SizedBox(height: 20),
          _buildInvoiceTable(invoice),
          pw.SizedBox(height: 30),
          _buildTotal(invoice),
          pw.SizedBox(height: 50),
          _buildFooter(invoice),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildHeader(Invoice invoice) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  invoice.clinicName.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(invoice.clinicAddress, style: const pw.TextStyle(fontSize: 10)),
                pw.Text('Reg No: ${invoice.registrationNo}', style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('INVOICE', style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                pw.Text('No: ${invoice.invoiceNo}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text('Date: ${invoice.formattedDate}', style: const pw.TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 2, color: PdfColors.blue900),
      ],
    );
  }

  static pw.Widget _buildPatientInfo(Invoice invoice) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        color: PdfColors.grey100,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildInfoRow('Patient Name:', invoice.patientName),
              ),
              pw.Expanded(
                child: _buildInfoRow('Doctor:', invoice.doctorName),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildInfoRow('Diagnosis:', invoice.diagnosis),
              ),
              pw.Expanded(
                child: _buildInfoRow('UHID:', invoice.patientId),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildInfoRow(String label, String value) {
    return pw.Row(
      children: [
        pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        pw.SizedBox(width: 8),
        pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
      ],
    );
  }

  static pw.Widget _buildInvoiceTable(Invoice invoice) {
    final headers = ['Description', 'Qty', 'Rate', 'Amount'];

    final data = invoice.items.map((item) {
      return [
        item.name,
        '${item.quantity}',
        item.rate.toStringAsFixed(2),
        item.amount.toStringAsFixed(2),
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: null,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
      cellHeight: 30,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
      headerAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
      cellStyle: const pw.TextStyle(fontSize: 10),
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: .5)),
      ),
    );
  }

  static pw.Widget _buildTotal(Invoice invoice) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text(
            'Total Amount: ',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Rs. ${invoice.totalAmount.toStringAsFixed(2)}',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(Invoice invoice) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Disclaimer:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Medicines dispensed as part of clinical treatment',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
            pw.Column(
              children: [
                pw.Container(
                  width: 150,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide(color: PdfColors.grey)),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text("Doctor's Signature", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 40),
        pw.Center(
          child: pw.Text(
            'This is a computer generated invoice and does not require a physical seal.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
          ),
        ),
      ],
    );
  }
}
