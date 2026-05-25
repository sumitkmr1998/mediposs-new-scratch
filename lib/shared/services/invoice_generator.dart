import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/invoice.dart';

class InvoiceGenerator {
  static Future<Uint8List> generate(Invoice invoice, PdfPageFormat format) async {
    final doc = pw.Document();
    
    final bool isSmall = format.width < 400;
    final double m = isSmall ? 16 : 32;

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: pw.EdgeInsets.all(m),
        build: (pw.Context context) => [
          _buildHeader(invoice, isSmall),
          pw.SizedBox(height: isSmall ? 10 : 20),
          _buildPatientInfo(invoice, isSmall),
          pw.SizedBox(height: isSmall ? 10 : 20),
          _buildInvoiceTable(invoice, isSmall),
          pw.SizedBox(height: isSmall ? 15 : 30),
          _buildTotal(invoice, isSmall),
          pw.SizedBox(height: isSmall ? 25 : 50),
          _buildFooter(invoice, isSmall),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildHeader(Invoice invoice, bool isSmall) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    invoice.clinicName.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: isSmall ? 16 : 24,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(invoice.clinicAddress, style: pw.TextStyle(fontSize: isSmall ? 8 : 10)),
                  if (invoice.registrationNo.isNotEmpty && invoice.registrationNo != 'N/A')
                    pw.Text(
                      invoice.isClinicalDispense 
                          ? 'Reg No: ${invoice.registrationNo}' 
                          : 'GST: ${invoice.registrationNo}', 
                      style: pw.TextStyle(fontSize: isSmall ? 8 : 10)
                    ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  invoice.isClinicalDispense ? 'CLINICAL DISPENSE' : 'INVOICE',
                  style: pw.TextStyle(
                    fontSize: isSmall 
                        ? (invoice.isClinicalDispense ? 12 : 18) 
                        : (invoice.isClinicalDispense ? 20 : 30), 
                    fontWeight: pw.FontWeight.bold, 
                    color: PdfColors.grey700
                  )
                ),
                pw.Text('No: ${invoice.invoiceNo}', style: pw.TextStyle(fontSize: isSmall ? 9 : 12, fontWeight: pw.FontWeight.bold)),
                pw.Text('Date: ${invoice.formattedDate}', style: pw.TextStyle(fontSize: isSmall ? 9 : 12)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: isSmall ? 6 : 10),
        pw.Divider(thickness: 2, color: PdfColors.blue900),
      ],
    );
  }

  static pw.Widget _buildPatientInfo(Invoice invoice, bool isSmall) {
    return pw.Container(
      padding: pw.EdgeInsets.all(isSmall ? 8 : 12),
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
                child: _buildInfoRow('Patient:', invoice.patientName, isSmall),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                child: _buildInfoRow('Doctor:', invoice.doctorName, isSmall),
              ),
            ],
          ),
          pw.SizedBox(height: isSmall ? 4 : 8),
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildInfoRow('Diagnosis:', invoice.diagnosis, isSmall),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                child: _buildInfoRow('UHID:', invoice.patientId, isSmall),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildInfoRow(String label, String value, bool isSmall) {
    final double fs = isSmall ? 8 : 11;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fs)),
        pw.SizedBox(width: 4),
        pw.Expanded(child: pw.Text(value, style: pw.TextStyle(fontSize: fs))),
      ],
    );
  }

  static pw.Widget _buildInvoiceTable(Invoice invoice, bool isSmall) {
    final headers = ['Description', 'Qty', 'Rate', 'Amount'];

    final data = invoice.items.map((item) {
      final desc = item.batchNo.isNotEmpty
          ? '${item.name}\nBatch: ${item.batchNo} | Exp: ${item.expiryDate}'
          : item.name;
      return [
        desc,
        '${item.quantity}',
        item.rate.toStringAsFixed(2),
        item.amount.toStringAsFixed(2),
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: null,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: isSmall ? 9 : 12),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
      cellHeight: isSmall ? 20 : 30,
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
      cellStyle: pw.TextStyle(fontSize: isSmall ? 8 : 10),
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: .5)),
      ),
    );
  }

  static pw.Widget _buildTotal(Invoice invoice, bool isSmall) {
    final double fs = isSmall ? 12 : 16;
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text(
            'Total Amount: ',
            style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Rs. ${invoice.totalAmount.toStringAsFixed(2)}',
            style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(Invoice invoice, bool isSmall) {
    final double fs = isSmall ? 8 : 10;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Disclaimer:',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fs),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    invoice.isClinicalDispense
                        ? 'Medicines dispensed as part of clinical treatment. Internal consumption only.'
                        : 'Goods once sold are subject to retail store return and exchange policies.',
                    style: pw.TextStyle(fontSize: fs),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Column(
              children: [
                pw.Container(
                  width: isSmall ? 80 : 150,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide(color: PdfColors.grey)),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text("Doctor's Signature", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fs)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: isSmall ? 20 : 40),
        pw.Center(
          child: pw.Text(
            'This is a computer generated invoice and does not require a physical seal.',
            style: pw.TextStyle(fontSize: isSmall ? 6 : 8, color: PdfColors.grey),
          ),
        ),
      ],
    );
  }
}
