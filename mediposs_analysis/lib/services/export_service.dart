import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/sale.dart';
import '../models/medicine.dart';

class ExportService {
  // ... (CSV methods remain)

  /// Export medicines list as PDF
  static Future<String> exportMedicinesPDF(List<Medicine> medicines) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, text: 'Medicines Inventory Report'),
          pw.TableHelper.fromTextArray(
            headers: ['Name', 'Category', 'Price', 'Stock', 'Margin'],
            data: medicines
                .map(
                  (m) => [
                    m.name,
                    m.category,
                    'Rs.${m.sellingPrice.toStringAsFixed(2)}',
                    m.totalStock.toString(),
                    '${m.marginPercent.toStringAsFixed(0)}%',
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );
    return _savePDF('medicines_report', pdf);
  }

  /// Export sales data as PDF
  static Future<String> exportSalesPDF(List<Sale> sales) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, text: 'Sales Transaction Report'),
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'Invoice', 'Customer', 'Total', 'Status'],
            data: sales
                .map(
                  (s) => [
                    '${s.createdAt.day}/${s.createdAt.month}/${s.createdAt.year}',
                    s.invoiceNo,
                    s.patientName,
                    'Rs.${s.total.toStringAsFixed(2)}',
                    s.isReturn ? 'RETURN' : 'PAID',
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );
    return _savePDF('sales_report', pdf);
  }

  /// Export profitability report as PDF
  static Future<String> exportProfitabilityPDF(
    List<Medicine> medicines,
    int Function(int) totalUnitsSold,
    double Function(int) revenueForMedicine,
  ) async {
    final pdf = pw.Document();

    final data = medicines.where((m) => totalUnitsSold(m.id) > 0).map((m) {
      final sold = totalUnitsSold(m.id);
      final rev = revenueForMedicine(m.id);
      final profit = rev - (m.purchasePrice * sold);
      return [
        m.name,
        sold.toString(),
        'Rs.${rev.toStringAsFixed(0)}',
        'Rs.${profit.toStringAsFixed(0)}',
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, text: 'Profitability Analysis'),
          pw.TableHelper.fromTextArray(
            headers: ['Medicine', 'Units', 'Revenue', 'Profit'],
            data: data,
          ),
        ],
      ),
    );
    return _savePDF('profitability_report', pdf);
  }

  /// Export dead stock report as PDF
  static Future<String> exportDeadStockPDF(List<Medicine> deadStock) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, text: 'Dead Stock Identification'),
          pw.TableHelper.fromTextArray(
            headers: ['Medicine', 'Category', 'Stock', 'Value'],
            data: deadStock
                .map(
                  (m) => [
                    m.name,
                    m.category,
                    m.storeStock.toString(),
                    'Rs.${(m.storeStock * m.purchasePrice).toStringAsFixed(2)}',
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );
    return _savePDF('dead_stock_report', pdf);
  }

  /// Export reorder suggestions as PDF
  static Future<String> exportReorderPDF(
    List<Medicine> medicines,
    double Function(int) dailyConsumption,
    double Function(int) daysOfStockRemaining,
  ) async {
    final pdf = pw.Document();

    final data = medicines.where((m) => daysOfStockRemaining(m.id) < 14).map((
      m,
    ) {
      final daily = dailyConsumption(m.id);
      final days = daysOfStockRemaining(m.id);
      final suggest = daily > 0 ? ((30 * daily) - m.totalStock).ceil() : 0;
      return [
        m.name,
        m.totalStock.toString(),
        days.toStringAsFixed(0),
        suggest > 0 ? suggest.toString() : '0',
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, text: 'Reorder Suggestions'),
          pw.TableHelper.fromTextArray(
            headers: ['Medicine', 'Stock', 'Days Left', 'Suggest Qty'],
            data: data,
          ),
        ],
      ),
    );
    return _savePDF('reorder_report', pdf);
  }

  static Future<String> _savePDF(String name, pw.Document pdf) async {
    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${dir.path}/${name}_$timestamp.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Export medicines list as CSV
  static Future<String> exportMedicinesCSV(List<Medicine> medicines) async {
    final rows = <List<dynamic>>[
      [
        'ID',
        'Name',
        'Category',
        'Unit',
        'Barcode',
        'Purchase Price',
        'Selling Price',
        'Margin',
        'Margin %',
        'Store Stock',
        'Main Stock',
        'Total Stock',
        'Low Stock Threshold',
        'Low Stock?',
      ],
    ];

    for (final m in medicines) {
      rows.add([
        m.id,
        m.name,
        m.category,
        m.unit,
        m.barcode,
        m.purchasePrice,
        m.sellingPrice,
        m.profitMargin,
        '${m.marginPercent.toStringAsFixed(1)}%',
        m.storeStock,
        m.mainStock,
        m.totalStock,
        m.lowStockThreshold,
        m.isLowStock ? 'YES' : 'No',
      ]);
    }

    return _saveCSV('medicines_report', rows);
  }

  /// Export sales data as CSV
  static Future<String> exportSalesCSV(List<Sale> sales) async {
    final rows = <List<dynamic>>[
      [
        'Date',
        'Invoice',
        'Customer',
        'Subtotal',
        'Discount',
        'Tax',
        'Total',
        'Payment',
        'Return?',
        'Items',
      ],
    ];

    for (final s in sales) {
      final itemsList = s.items
          .map((i) => '${i.medicineName}×${i.qty}')
          .join(', ');
      rows.add([
        '${s.createdAt.day}/${s.createdAt.month}/${s.createdAt.year}',
        s.invoiceNo,
        s.patientName,
        s.subtotal,
        s.discount,
        s.taxAmount,
        s.total,
        s.paymentMethod,
        s.isReturn ? 'YES' : 'No',
        itemsList,
      ]);
    }

    return _saveCSV('sales_report', rows);
  }

  /// Export profitability report as CSV
  static Future<String> exportProfitabilityCSV(
    List<Medicine> medicines,
    int Function(int) totalUnitsSold,
    double Function(int) revenueForMedicine,
  ) async {
    final rows = <List<dynamic>>[
      [
        'Medicine',
        'Category',
        'Units Sold',
        'Revenue',
        'Cost',
        'Profit',
        'Margin %',
      ],
    ];

    for (final m in medicines) {
      final sold = totalUnitsSold(m.id);
      if (sold == 0) continue;
      final rev = revenueForMedicine(m.id);
      final cost = m.purchasePrice * sold;
      final profit = rev - cost;
      rows.add([
        m.name,
        m.category,
        sold,
        rev.toStringAsFixed(2),
        cost.toStringAsFixed(2),
        profit.toStringAsFixed(2),
        '${m.marginPercent.toStringAsFixed(1)}%',
      ]);
    }

    return _saveCSV('profitability_report', rows);
  }

  /// Export dead stock report as CSV
  static Future<String> exportDeadStockCSV(List<Medicine> deadStock) async {
    final rows = <List<dynamic>>[
      [
        'Medicine',
        'Category',
        'Unit',
        'Store Stock',
        'Purchase Price',
        'Capital Locked',
      ],
    ];

    for (final m in deadStock) {
      rows.add([
        m.name,
        m.category,
        m.unit,
        m.storeStock,
        m.purchasePrice,
        (m.storeStock * m.purchasePrice).toStringAsFixed(2),
      ]);
    }

    return _saveCSV('dead_stock_report', rows);
  }

  /// Export reorder suggestions as CSV
  static Future<String> exportReorderCSV(
    List<Medicine> medicines,
    double Function(int) dailyConsumption,
    double Function(int) daysOfStockRemaining,
  ) async {
    final rows = <List<dynamic>>[
      [
        'Medicine',
        'Category',
        'Current Stock',
        'Daily Avg',
        'Days Left',
        'Suggested Order Qty',
      ],
    ];

    for (final m in medicines) {
      final daily = dailyConsumption(m.id);
      final daysLeft = daysOfStockRemaining(m.id);
      if (daysLeft >= 14 || daysLeft >= 999) continue;
      final suggestedQty = daily > 0 ? ((30 * daily) - m.totalStock).ceil() : 0;
      rows.add([
        m.name,
        m.category,
        m.totalStock,
        daily.toStringAsFixed(1),
        daysLeft.toStringAsFixed(0),
        suggestedQty > 0 ? suggestedQty : 0,
      ]);
    }

    return _saveCSV('reorder_report', rows);
  }

  static Future<String> _saveCSV(String name, List<List<dynamic>> rows) async {
    // Manual robust CSV generation (handles quotes/escaping)
    final csv = rows
        .map((row) {
          return row
              .map((cell) {
                final str = cell?.toString() ?? '';
                if (str.contains(',') ||
                    str.contains('"') ||
                    str.contains('\n')) {
                  return '"${str.replaceAll('"', '""')}"';
                }
                return str;
              })
              .join(',');
        })
        .join('\n');

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${dir.path}/${name}_$timestamp.csv');
    await file.writeAsString(csv);
    return file.path;
  }
}
