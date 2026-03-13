import 'dart:io';
import 'package:excel/excel.dart';
import '../models/medicine.dart';

class ExcelImportService {
  /// Import medicines from an Excel file (XLS or XLSX)
  /// Returns a list of medicines and any errors encountered
  static Future<({List<Medicine> medicines, List<String> errors})> 
      importMedicinesFromExcel(File file) async {
    final errors = <String>[];
    final medicines = <Medicine>[];

    try {
      // Check if file exists and is readable
      if (!await file.exists()) {
        errors.add('File does not exist: ${file.path}');
        return (medicines: medicines, errors: errors);
      }

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        errors.add('File is empty: ${file.path}');
        return (medicines: medicines, errors: errors);
      }

      // Try to decode the Excel file
      Excel excel;
      try {
        excel = Excel.decodeBytes(bytes);
      } catch (e) {
        errors.add('Failed to decode Excel file: $e');
        return (medicines: medicines, errors: errors);
      }

      // Check if there are any sheets
      if (excel.sheets.isEmpty) {
        errors.add('No sheets found in the Excel file');
        return (medicines: medicines, errors: errors);
      }

      // Find the sheet with the most data (not just empty cells)
      Sheet? targetSheet;
      int maxRowCount = 0;
      
      for (final name in excel.sheets.keys) {
        final sheet = excel[name];
        if (sheet == null) continue;
        
        final rows = sheet.rows;
        int nonEmptyRowCount = 0;
        
        for (final row in rows.take(100)) { // Check first 100 rows
          final hasData = row.any((cell) => cell?.value != null && cell!.value.toString().trim().isNotEmpty);
          if (hasData) nonEmptyRowCount++;
        }
        
        if (nonEmptyRowCount > maxRowCount) {
          maxRowCount = nonEmptyRowCount;
          targetSheet = sheet;
        }
      }

      if (targetSheet == null) {
        errors.add('Could not find a sheet with data in the Excel file');
        return (medicines: medicines, errors: errors);
      }

      final rows = targetSheet.rows;
      if (rows.isEmpty) {
        errors.add('Excel sheet is empty');
        return (medicines: medicines, errors: errors);
      }

      // Find the header row by looking for recognizable column names
      int headerRowIndex = 0;
      List<String> headers = [];
      
      // Check first 10 rows for headers
      for (int i = 0; i < 10 && i < rows.length; i++) {
        final row = rows[i];
        final potentialHeaders = row
            .map((cell) => cell?.value?.toString().trim() ?? '')
            .toList();
        
        // Count how many cells look like column headers
        int headerMatchCount = 0;
        int nonEmptyCount = 0;
        
        for (final header in potentialHeaders) {
          if (header.isEmpty) continue;
          nonEmptyCount++;
          final lower = header.toLowerCase();
          
          // Check for common header keywords
          if (lower.contains('name') ||
              lower.contains('medicine') ||
              lower.contains('product') ||
              lower.contains('stock') ||
              lower.contains('quantity') ||
              lower.contains('price') ||
              lower.contains('cost') ||
              lower.contains('category') ||
              lower.contains('type') ||
              lower.contains('barcode') ||
              lower.contains('batch')) {
            headerMatchCount++;
          }
        }
        
        // If we found at least 2 header-like words in a non-empty row, it's likely the header
        if (nonEmptyCount > 1 && headerMatchCount >= 2) {
          headerRowIndex = i;
          headers = potentialHeaders.map((h) => h.toLowerCase()).toList();
          break;
        }
      }

      // If no headers found, try to infer data structure
      if (headers.isEmpty) {
        final firstRow = rows[0];
        headers = firstRow
            .map((cell) => cell?.value?.toString().trim().toLowerCase() ?? '')
            .toList();
      }

      // Find column indices
      final nameIndex = _findColumnIndex(headers, ['name', 'medicine', 'product']);
      final categoryIndex = _findColumnIndex(headers, ['category', 'type']);
      final barcodeIndex = _findColumnIndex(headers, ['barcode', 'batch', 'code']);
      final purchaseIndex = _findColumnIndex(headers, ['purchase', 'cost', 'buy', 'mrp']);
      final sellingIndex = _findColumnIndex(headers, ['selling', 'price', 'sell', 'rate', 'sp']);
      final stockIndex = _findColumnIndex(headers, ['stock', 'quantity', 'qty', 'balance']);

      if (nameIndex == -1) {
        errors.add('Could not find "Name" column in Excel file');
        if (headers.isNotEmpty) {
          errors.add('Available columns: ${headers.where((h) => h.isNotEmpty).join(", ")}');
        }
        return (medicines: medicines, errors: errors);
      }

      // Process each row (skip header row)
      for (int i = headerRowIndex + 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty) continue;

        // Check if this row has data
        final hasData = row.any((cell) => cell?.value != null && cell!.value.toString().trim().isNotEmpty);
        if (!hasData) continue;

        final name = row.length > nameIndex ? row[nameIndex]?.value?.toString().trim() : null;
        if (name == null || name.isEmpty) continue;

        try {
          final medicine = Medicine(
            id: DateTime.now().millisecondsSinceEpoch + i,
            name: name,
            category: categoryIndex != -1 && row.length > categoryIndex
                ? row[categoryIndex]?.value?.toString().trim() ?? 'General'
                : 'General',
            unit: 'Unit',
            barcode: barcodeIndex != -1 && row.length > barcodeIndex
                ? row[barcodeIndex]?.value?.toString().trim() ?? ''
                : '',
            purchasePrice: purchaseIndex != -1 && row.length > purchaseIndex
                ? _parseDouble(row[purchaseIndex]?.value) ?? 0.0
                : 0.0,
            sellingPrice: sellingIndex != -1 && row.length > sellingIndex
                ? _parseDouble(row[sellingIndex]?.value) ?? 0.0
                : 0.0,
            mainStock: stockIndex != -1 && row.length > stockIndex
                ? _parseInt(row[stockIndex]?.value) ?? 0
                : 0,
            storeStock: 0,
            lowStockThreshold: 10,
          );
          medicines.add(medicine);
        } catch (e) {
          errors.add('Error parsing row ${i + 1}: $e');
        }
      }
    } catch (e) {
      errors.add('Failed to read Excel file: $e');
    }

    return (medicines: medicines, errors: errors);
  }

  /// Find column index by looking for matching headers
  static int _findColumnIndex(List<String> headers, List<String> possibleNames) {
    for (int i = 0; i < headers.length; i++) {
      final header = headers[i];
      for (final possible in possibleNames) {
        if (header.contains(possible) || possible.contains(header)) {
          return i;
        }
      }
    }
    return -1;
  }

  /// Parse double from Excel cell value
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    try {
      if (value is num) {
        return value.toDouble();
      }
      final str = value.toString().trim().replaceAll(RegExp(r'[^\d.]'), '');
      if (str.isEmpty) return null;
      return double.parse(str);
    } catch (e) {
      return null;
    }
  }

  /// Parse int from Excel cell value
  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    try {
      if (value is num) {
        return value.toInt();
      }
      final str = value.toString().trim().replaceAll(RegExp(r'[^\d]'), '');
      if (str.isEmpty) return null;
      return int.parse(str);
    } catch (e) {
      return null;
    }
  }

  /// Get column names from Excel file for preview
  static Future<List<String>> getColumnNames(File file) async {
    try {
      if (!await file.exists()) return [];

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return [];

      final excel = Excel.decodeBytes(bytes);
      
      // Find the sheet with the most data
      Sheet? targetSheet;
      int maxRowCount = 0;
      
      for (final name in excel.sheets.keys) {
        final sheet = excel[name];
        if (sheet == null) continue;
        
        final rows = sheet.rows;
        int nonEmptyRowCount = 0;
        
        for (final row in rows.take(100)) {
          final hasData = row.any((cell) => cell?.value != null && cell!.value.toString().trim().isNotEmpty);
          if (hasData) nonEmptyRowCount++;
        }
        
        if (nonEmptyRowCount > maxRowCount) {
          maxRowCount = nonEmptyRowCount;
          targetSheet = sheet;
        }
      }

      if (targetSheet == null || targetSheet.rows.isEmpty) return [];

      // Try to find header row
      for (int i = 0; i < 10 && i < targetSheet.rows.length; i++) {
        final row = targetSheet.rows[i];
        final potentialHeaders = row
            .map((cell) => cell?.value?.toString().trim() ?? '')
            .toList();
        
        int headerMatchCount = 0;
        int nonEmptyCount = 0;
        
        for (final header in potentialHeaders) {
          if (header.isEmpty) continue;
          nonEmptyCount++;
          final lower = header.toLowerCase();
          
          if (lower.contains('name') ||
              lower.contains('medicine') ||
              lower.contains('stock') ||
              lower.contains('price') ||
              lower.contains('category')) {
            headerMatchCount++;
          }
        }
        
        if (nonEmptyCount > 1 && headerMatchCount >= 2) {
          return potentialHeaders.where((h) => h.isNotEmpty).toList();
        }
      }

      // Fallback to first row
      final headerRow = targetSheet.rows[0];
      return headerRow
          .map((cell) => cell?.value?.toString().trim() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Decode Excel file to text format for AI analysis
  /// Returns a formatted text representation of the Excel data
  static Future<String> decodeExcelToText(File file) async {
    try {
      if (!await file.exists()) {
        return 'Error: File does not exist: ${file.path}';
      }

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        return 'Error: File is empty: ${file.path}';
      }

      final excel = Excel.decodeBytes(bytes);
      
      if (excel.sheets.isEmpty) {
        return 'Error: No sheets found in the Excel file';
      }

      final buffer = StringBuffer();
      buffer.writeln('=== EXCEL FILE ANALYSIS ===');
      buffer.writeln('File: ${file.path.split('\\').last}');
      buffer.writeln('Total Sheets: ${excel.sheets.length}');
      buffer.writeln('');

      // Process each sheet
      for (final sheetName in excel.sheets.keys) {
        final sheet = excel[sheetName];
        if (sheet == null) continue;

        buffer.writeln('--- Sheet: $sheetName ---');
        
        final rows = sheet.rows;
        if (rows.isEmpty) {
          buffer.writeln('(Empty sheet)');
          buffer.writeln('');
          continue;
        }

        // Find header row
        int headerRowIndex = 0;
        List<String> headers = [];
        
        for (int i = 0; i < 10 && i < rows.length; i++) {
          final row = rows[i];
          final potentialHeaders = row
              .map((cell) => cell?.value?.toString().trim() ?? '')
              .toList();
          
          int headerMatchCount = 0;
          int nonEmptyCount = 0;
          
          for (final header in potentialHeaders) {
            if (header.isEmpty) continue;
            nonEmptyCount++;
            final lower = header.toLowerCase();
            
            if (lower.contains('name') ||
                lower.contains('medicine') ||
                lower.contains('product') ||
                lower.contains('stock') ||
                lower.contains('quantity') ||
                lower.contains('price') ||
                lower.contains('cost') ||
                lower.contains('category') ||
                lower.contains('type') ||
                lower.contains('barcode') ||
                lower.contains('batch')) {
              headerMatchCount++;
            }
          }
          
          if (nonEmptyCount > 1 && headerMatchCount >= 2) {
            headerRowIndex = i;
            headers = potentialHeaders;
            break;
          }
        }

        // If no headers found, use first row
        if (headers.isEmpty && rows.isNotEmpty) {
          headers = rows[0]
              .map((cell) => cell?.value?.toString().trim() ?? '')
              .toList();
        }

        // Display headers
        if (headers.isNotEmpty) {
          buffer.writeln('Columns: ${headers.where((h) => h.isNotEmpty).join(", ")}');
          buffer.writeln('');
        }

        // Display data rows (limit to first 20 rows for AI context)
        final maxRows = 20;
        final startRow = headers.isNotEmpty ? headerRowIndex + 1 : 0;
        int rowCount = 0;
        
        for (int i = startRow; i < rows.length && rowCount < maxRows; i++) {
          final row = rows[i];
          final hasData = row.any((cell) => cell?.value != null && cell!.value.toString().trim().isNotEmpty);
          
          if (!hasData) continue;
          
          final rowData = <String>[];
          for (int j = 0; j < headers.length && j < row.length; j++) {
            final cellValue = row[j]?.value?.toString().trim() ?? '';
            if (cellValue.isNotEmpty) {
              final headerName = headers[j].isNotEmpty ? headers[j] : 'Column${j + 1}';
              rowData.add('$headerName: $cellValue');
            }
          }
          
          if (rowData.isNotEmpty) {
            buffer.writeln('Row ${i + 1}: ${rowData.join(" | ")}');
            rowCount++;
          }
        }

        if (rows.length - startRow > maxRows) {
          buffer.writeln('');
          buffer.writeln('... and ${rows.length - startRow - maxRows} more rows');
        }

        buffer.writeln('');
      }

      return buffer.toString();
    } catch (e) {
      return 'Error decoding Excel file: $e';
    }
  }
}