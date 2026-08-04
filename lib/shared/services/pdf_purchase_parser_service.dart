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
    final document = PdfLoadedDocument(bytes);
    final extractor = PdfTextExtractor(document);
    final String fullText = extractor.extractText();
    document.dispose();

    debugPrint('PdfPurchaseParserService: Full Extracted Text:\n$fullText');

    return parseInvoiceText(fullText);
  }

  static ParsedPurchaseInvoice parseInvoiceText(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // 1. Supplier Name
    String supplierName = 'TRIDHA PHARMACEUTICALS';
    for (var line in lines.take(10)) {
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
      final billToSection = text.substring(billToIndex, (billToIndex + 300).clamp(0, text.length));
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

    // Pattern matching lines:
    // e.g.: "1 ULTRA CLEAR & CLEAR 33049910 CC260180 03/2028 365.00 270 Pcs ₹ 96.00 ₹ 4,665.60 (18.0%) ₹ 30,585.60"
    // e.g.: "2 SWISSGLOW-3D CREAM 33041000 BM6-120 05/2029 395.00 99 Pcs ₹ 78.00 ₹ 1,389.96 (18.0%) ₹ 9,111.96"
    // e.g.: "3 FREIGHT 84145140 1 - ₹ 1,200.00 ₹ 216.00 (18.0%) ₹ 1,416.00"

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Check for Freight charge
      if (line.toUpperCase().contains('FREIGHT')) {
        final amountMatch = RegExp(r'₹?\s*([\d,]+\.?\d*)').allMatches(line).toList();
        if (amountMatch.isNotEmpty) {
          final lastAmountStr = amountMatch.last.group(1)?.replaceAll(',', '') ?? '0';
          freightCharge = double.tryParse(lastAmountStr) ?? 0.0;
        }
        continue;
      }

      // Check if line looks like a line item (starts with a number 1..99)
      final itemLineRegex = RegExp(
        r'^\d+\s+([A-Z0-9\s&\-\.]+?)\s+(\d{4,8})\s+([A-Z0-9]+)\s+(\d{2}/\d{4})\s+([\d\.]+)\s+(?:\w+\s+)?(\d+)\s+(?:Pcs|Pcs\.|Box|Nos|Pack)?\s*₹?\s*([\d\.]+)',
        caseSensitive: false,
      );

      final match = itemLineRegex.firstMatch(line);
      if (match != null) {
        final name = match.group(1)?.trim() ?? '';
        final hsn = match.group(2)?.trim() ?? '';
        final batchNo = match.group(3)?.trim() ?? '';
        final expStr = match.group(4)?.trim() ?? '';
        final mrp = double.tryParse(match.group(5) ?? '') ?? 0.0;
        final qty = int.tryParse(match.group(6) ?? '') ?? 0;
        final purchasePrice = double.tryParse(match.group(7) ?? '') ?? 0.0;

        // Parse expiry MM/YYYY
        DateTime expiryDate = DateTime.now().add(const Duration(days: 365));
        if (expStr.contains('/')) {
          final expParts = expStr.split('/');
          final m = int.tryParse(expParts[0]) ?? 1;
          final y = int.tryParse(expParts[1]) ?? DateTime.now().year + 1;
          expiryDate = DateTime(y, m, 1);
        }

        // Try extracting GST percentage e.g. (18.0%)
        double gst = 0.0;
        final gstMatch = RegExp(r'\(\s*([\d\.]+)\s*%\s*\)').firstMatch(line);
        if (gstMatch != null) {
          gst = double.tryParse(gstMatch.group(1) ?? '') ?? 0.0;
        }

        double lineTotal = purchasePrice * qty;
        final amountMatch = RegExp(r'₹?\s*([\d,]+\.\d{2})').allMatches(line).toList();
        if (amountMatch.isNotEmpty) {
          final lastVal = double.tryParse(amountMatch.last.group(1)?.replaceAll(',', '') ?? '');
          if (lastVal != null && lastVal > 0) lineTotal = lastVal;
        }

        items.add(ParsedPurchaseItem(
          name: name,
          hsn: hsn,
          batchNo: batchNo,
          expiryDate: expiryDate,
          mrp: mrp,
          qty: qty,
          purchasePrice: purchasePrice,
          gstPercent: gst,
          lineTotal: lineTotal,
        ));
      } else {
        // Fallback flexible parser for multi-token lines
        _tryFallbackParse(line, items);
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

  static void _tryFallbackParse(String line, List<ParsedPurchaseItem> items) {
    if (line.contains('Total') || line.contains('Tax Invoice') || line.contains('Sub Total') || line.contains('Round off')) {
      return;
    }

    final dateMatch = RegExp(r'(\d{2}/\d{4})').firstMatch(line);
    final hsnMatch = RegExp(r'\b(\d{6,8})\b').firstMatch(line);

    if (dateMatch != null && hsnMatch != null) {
      final expStr = dateMatch.group(1)!;
      final hsn = hsnMatch.group(1)!;

      final tokens = line.split(RegExp(r'\s+'));
      String name = '';
      String batchNo = '';

      for (var t in tokens) {
        if (RegExp(r'^[A-Z\-\s&]{3,}$').hasMatch(t) && !t.contains('PCS') && !t.contains('GST')) {
          name += '$t ';
        } else if (RegExp(r'^[A-Z0-9]{5,10}$').hasMatch(t) && t != hsn && !t.contains('3304')) {
          if (batchNo.isEmpty) batchNo = t;
        }
      }

      // Numbers extraction
      final nums = RegExp(r'\b\d+(?:\.\d+)?\b')
          .allMatches(line)
          .map((m) => double.tryParse(m.group(0)!) ?? 0.0)
          .where((n) => n > 0 && n != double.parse(hsn))
          .toList();

      if (nums.length >= 3) {
        final mrp = nums.firstWhere((n) => n > 50, orElse: () => 100.0);
        final qty = nums.firstWhere((n) => n == n.roundToDouble() && n < 5000, orElse: () => 1.0).toInt();
        final price = nums.firstWhere((n) => n < mrp && n > 5, orElse: () => mrp * 0.7);

        final expParts = expStr.split('/');
        final m = int.tryParse(expParts[0]) ?? 1;
        final y = int.tryParse(expParts[1]) ?? DateTime.now().year + 1;

        if (name.isNotEmpty && batchNo.isNotEmpty && !items.any((x) => x.batchNo == batchNo)) {
          items.add(ParsedPurchaseItem(
            name: name.trim(),
            hsn: hsn,
            batchNo: batchNo,
            expiryDate: DateTime(y, m, 1),
            mrp: mrp,
            qty: qty,
            purchasePrice: price,
            lineTotal: price * qty,
          ));
        }
      }
    }
  }
}
