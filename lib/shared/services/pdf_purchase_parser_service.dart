import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class ParsedPurchaseItem {
  String name;
  String hsn;
  String batchNo;
  DateTime expiryDate;
  double mrp;
  int qty;
  double purchasePrice;
  double gstPercent;
  double lineTotal;

  ParsedPurchaseItem({
    required this.name,
    this.hsn = '',
    required this.batchNo,
    required this.expiryDate,
    required this.mrp,
    required this.qty,
    required this.purchasePrice,
    this.gstPercent = 0.0,
    required this.lineTotal,
  });
}

class ParsedPurchaseInvoice {
  String supplierName;
  String invoiceNo;
  DateTime invoiceDate;
  String billToName;
  String targetLocation; // 'bulkClinic' or 'bulkStore'
  List<ParsedPurchaseItem> items;
  double freightCharge;
  double invoiceTotal;

  ParsedPurchaseInvoice({
    required this.supplierName,
    required this.invoiceNo,
    required this.invoiceDate,
    required this.billToName,
    required this.targetLocation,
    required this.items,
    this.freightCharge = 0.0,
    this.invoiceTotal = 0.0,
  });
}

class PdfPurchaseParserService {
  static ParsedPurchaseInvoice parsePdfBytes(Uint8List bytes) {
    final document = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(document);
    final String fullText = extractor.extractText();
    document.dispose();

    debugPrint('PdfPurchaseParserService: Full Extracted Text:\n$fullText');

    return parseInvoiceText(fullText);
  }

  static ParsedPurchaseInvoice parseInvoiceText(String text) {
    final rawLines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // 1. Supplier Name
    String supplierName = 'TRIDHA PHARMACEUTICALS';
    for (var line in rawLines.take(10)) {
      if (line.toUpperCase().contains('PHARMA') ||
          line.toUpperCase().contains('TRIDHA') ||
          line.toUpperCase().contains('LIMITED') ||
          line.toUpperCase().contains('PVT')) {
        supplierName = line.replaceAll('Tax Invoice', '').replaceAll('ORIGINAL FOR RECIPIENT', '').trim();
        break;
      }
    }

    // 2. Invoice No
    String invoiceNo = '';
    final invReg = RegExp(r'Invoice\s*No\.?\s*[:\s]*([A-Z0-9-]+)', caseSensitive: false);
    final invMatch = invReg.firstMatch(text);
    if (invMatch != null && invMatch.groupCount >= 1) {
      invoiceNo = invMatch.group(1)?.trim() ?? '';
    }
    if (invoiceNo.isEmpty) {
      final fallbackInv = RegExp(r'\b(S\d{3,6}|INV-\d+|BILL-\d+)\b', caseSensitive: false);
      final fm = fallbackInv.firstMatch(text);
      if (fm != null) invoiceNo = fm.group(1) ?? '';
    }
    if (invoiceNo.isEmpty) {
      invoiceNo = 'PUR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    }

    // 3. Date
    DateTime invoiceDate = DateTime.now();
    final dateReg = RegExp(r'Date\s*[:\s]*(\d{2}[-/.]\d{2}[-/.]\d{4})', caseSensitive: false);
    final dateMatch = dateReg.firstMatch(text);
    if (dateMatch != null && dateMatch.groupCount >= 1) {
      final dStr = dateMatch.group(1)!;
      final parts = dStr.split(RegExp(r'[-/.]'));
      if (parts.length == 3) {
        final day = int.tryParse(parts[0]) ?? 1;
        final month = int.tryParse(parts[1]) ?? 1;
        final year = int.tryParse(parts[2]) ?? DateTime.now().year;
        invoiceDate = DateTime(year, month, day);
      }
    }

    // 4. Bill To & Target Location Classifier
    String billToName = '';
    String targetLocation = 'bulkStore'; // Default to Store Bulk

    int billToIndex = text.indexOf('Bill To');
    if (billToIndex != -1) {
      final billToSection = text.substring(billToIndex, (billToIndex + 350).clamp(0, text.length));
      final billToLines = billToSection.split('\n').map((l) => l.trim()).toList();
      for (var l in billToLines) {
        if (l.contains('Bill To') || l.isEmpty) continue;
        if (l.startsWith('#') || l.contains('Item Name') || l.contains('GSTIN')) continue;
        if (billToName.isEmpty && l.length > 2) {
          billToName = l;
          break;
        }
      }
    }

    final billUpper = text.toUpperCase();
    if (billUpper.contains('SUMIT KUMAR') || billUpper.contains('DR. SUMIT') || billUpper.contains('DR SUMIT')) {
      targetLocation = 'bulkClinic';
      if (billToName.isEmpty) billToName = 'DR. SUMIT KUMAR';
    } else if (billUpper.contains('RITA MEDICAL') || billUpper.contains('RITA')) {
      targetLocation = 'bulkStore';
      if (billToName.isEmpty) billToName = 'RITA MEDICAL STORE';
    }

    // 5. Line Items Extraction
    final List<ParsedPurchaseItem> items = [];
    double freightCharge = 0.0;

    // Check Freight
    final freightMatch = RegExp(r'FREIGHT\s+(\d+)\s+([\d,-]+)\s+₹?\s*([\d,]+\.?\d*)', caseSensitive: false).firstMatch(text);
    if (freightMatch != null) {
      freightCharge = double.tryParse(freightMatch.group(3)?.replaceAll(',', '') ?? '0') ?? 1200.0;
    }

    // Parse each line individually
    for (var line in rawLines) {
      if (line.toUpperCase().contains('FREIGHT') ||
          line.toUpperCase().contains('TAX INVOICE') ||
          line.contains('Sub Total') ||
          line.contains('Round off')) {
        continue;
      }

      // Check if line contains an HSN code (6-8 digits) AND an Expiry Date (MM/YYYY)
      final hsnMatch = RegExp(r'\b(3\d{7}|3\d{5}|8\d{7}|\d{6,8})\b').firstMatch(line);
      final expMatch = RegExp(r'\b(\d{2}/\d{4})\b').firstMatch(line);

      if (hsnMatch != null && expMatch != null) {
        final hsn = hsnMatch.group(1)!;
        final expStr = expMatch.group(1)!;

        int hsnPos = line.indexOf(hsn);
        int expPos = line.indexOf(expStr);

        // 1. Item Name: Everything before HSN (strip leading row index number e.g. "1 ", "2 ")
        String beforeHsn = line.substring(0, hsnPos).trim();
        String name = beforeHsn.replaceAll(RegExp(r'^\d+\s+'), '').trim();
        if (name.isEmpty) {
          name = 'MEDICINE ${items.length + 1}';
        }

        // 2. Batch Number: Everything between HSN and Exp Date
        String batchNo = '';
        if (expPos > hsnPos + hsn.length) {
          String between = line.substring(hsnPos + hsn.length, expPos).trim();
          final bTokens = between.split(RegExp(r'\s+')).where((t) => t.length >= 3).toList();
          if (bTokens.isNotEmpty) {
            batchNo = bTokens.last;
          }
        }
        if (batchNo.isEmpty) {
          batchNo = 'BATCH-${items.length + 1}';
        }

        // 3. Expiry Date
        final expParts = expStr.split('/');
        final m = int.tryParse(expParts[0]) ?? 1;
        final y = int.tryParse(expParts[1]) ?? DateTime.now().year + 1;
        final expiryDate = DateTime(y, m, 1);

        // 4. Numbers Section: Everything AFTER Exp Date
        String afterExp = line.substring(expPos + expStr.length).trim();

        double mrp = 0.0;
        int qty = 0;
        double purchasePrice = 0.0;

        // Extract MRP: First decimal value after exp date
        final mrpMatch = RegExp(r'([\d,]+\.\d{2})').firstMatch(afterExp);
        if (mrpMatch != null) {
          mrp = double.tryParse(mrpMatch.group(1)!.replaceAll(',', '')) ?? 0.0;
        }

        // Extract Quantity: Integer preceding "Pcs", "Box", "Nos", "Pack" OR standalone integer after MRP
        final qtyMatch = RegExp(r'\b(\d{1,5})\s*(?:Pcs|Pcs\.|Box|Nos|Pack)?\b', caseSensitive: false).firstMatch(afterExp);
        if (qtyMatch != null && qtyMatch.group(1) != null) {
          final qVal = int.tryParse(qtyMatch.group(1)!);
          if (qVal != null && qVal > 0 && qVal < 50000) {
            qty = qVal;
          }
        }

        // Extract Purchase Price (Cost Rate): decimal after '₹' or second decimal
        final priceMatch = RegExp(r'₹\s*([\d,]+\.\d{2})').firstMatch(afterExp);
        if (priceMatch != null && priceMatch.group(1) != null) {
          final pVal = double.tryParse(priceMatch.group(1)!.replaceAll(',', ''));
          if (pVal != null && pVal > 0) purchasePrice = pVal;
        }

        if (purchasePrice == 0.0) {
          final allDecimals = RegExp(r'[\d,]+\.\d{2}')
              .allMatches(afterExp)
              .map((m) => double.tryParse(m.group(0)!.replaceAll(',', '')) ?? 0.0)
              .where((d) => d > 0)
              .toList();
          if (allDecimals.length >= 2) {
            purchasePrice = allDecimals[1];
          }
        }

        if (purchasePrice == 0.0) purchasePrice = mrp > 0 ? mrp * 0.7 : 100.0;
        if (qty == 0) qty = 1;

        double lineTotal = purchasePrice * qty;

        if (!items.any((it) => it.batchNo == batchNo && it.name == name)) {
          items.add(ParsedPurchaseItem(
            name: name,
            hsn: hsn,
            batchNo: batchNo,
            expiryDate: expiryDate,
            mrp: mrp,
            qty: qty,
            purchasePrice: purchasePrice,
            lineTotal: lineTotal,
          ));
        }
      }
    }

    // 6. Total Amount
    double invoiceTotal = items.fold(0.0, (sum, item) => sum + item.lineTotal) + freightCharge;
    final totalMatch = RegExp(r'Total\s*₹?\s*([\d,]+\.?\d*)', caseSensitive: false).firstMatch(text);
    if (totalMatch != null) {
      final parsedTot = double.tryParse(totalMatch.group(1)?.replaceAll(',', '') ?? '');
      if (parsedTot != null && parsedTot > 0) invoiceTotal = parsedTot;
    }

    return ParsedPurchaseInvoice(
      supplierName: supplierName,
      invoiceNo: invoiceNo,
      invoiceDate: invoiceDate,
      billToName: billToName,
      targetLocation: targetLocation,
      items: items,
      freightCharge: freightCharge,
      invoiceTotal: invoiceTotal,
    );
  }
}
