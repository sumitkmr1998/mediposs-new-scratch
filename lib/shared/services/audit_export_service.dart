import 'dart:io';
import 'dart:convert';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'objectbox_service.dart';
import '../models/medicine.dart';
import '../models/stock_transfer.dart';
import '../models/sale.dart';
import '../models/patient.dart';
import '../models/prescription.dart';

class AuditExportService {
  /// Generates a comprehensive Excel Audit Report
  static Future<File?> generateAuditReport({String? customPath}) async {
    try {
      final db = ObjectBoxService.instance;
      var excel = Excel.createExcel();
      
      // Clean up default sheet
      if (excel.sheets.keys.contains('Sheet1')) {
        excel.delete('Sheet1');
      }

      // 1. Stock / Inventory
      final medicines = db.medicineBox.getAll();
      _exportInventory(excel, medicines, db.batchBox.getAll());

      // 2. Internal Transfers
      final medMap = {for (var m in medicines) m.id: m.name};
      _exportTransfers(excel, db.transferBox.getAll(), medMap);

      // 3. Sales / Dispense
      _exportSales(excel, db.saleBox.getAll());

      // 4. Patients
      _exportPatients(excel, db.patientBox.getAll());

      // 5. Prescriptions
      _exportPrescriptions(excel, db.prescriptionBox.getAll());

      // Save file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final fileName = 'MediPoss_Audit_Report_$timestamp.xlsx';
      final file = File(customPath ?? p.join(tempDir.path, fileName));
      
      final bytes = excel.save();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
        return file;
      }
      return null;
    } catch (e) {
      debugPrint('Audit Export Error: $e');
      return null;
    }
  }

  static void _exportInventory(Excel excel, List<Medicine> medicines, List<MedicineBatch> batches) {
    Sheet sheet = excel['Inventory'];
    sheet.appendRow([
      TextCellValue('Medicine ID'),
      TextCellValue('Name'),
      TextCellValue('Category'),
      TextCellValue('Total Stock'),
      TextCellValue('Batches Info'),
    ]);

    for (var m in medicines) {
      final mBatches = batches.where((b) => b.medicine.targetId == m.id).toList();
      String batchInfo = mBatches.map((b) => '${b.batchNo} (Qty: ${b.mainStock + b.storeStock}, Exp: ${b.expiryDate.toIso8601String().split('T').first})').join(' | ');
      
      sheet.appendRow([
        IntCellValue(m.id),
        TextCellValue(m.name),
        TextCellValue(m.category),
        IntCellValue(m.totalStock),
        TextCellValue(batchInfo),
      ]);
    }
  }

  static void _exportTransfers(Excel excel, List<StockTransfer> transfers, Map<int, String> medMap) {
    Sheet sheet = excel['Transfers'];
    sheet.appendRow([
      TextCellValue('Transfer ID'),
      TextCellValue('Date'),
      TextCellValue('Medicine ID'),
      TextCellValue('Medicine Name'),
      TextCellValue('Batch'),
      TextCellValue('Quantity'),
      TextCellValue('Type'),
      TextCellValue('Status'),
    ]);

    for (var t in transfers) {
      final medName = medMap[t.medicineId] ?? 'Unknown Medicine';
      sheet.appendRow([
        IntCellValue(t.id),
        TextCellValue(t.transferredAt.toIso8601String()),
        IntCellValue(t.medicineId),
        TextCellValue(medName),
        TextCellValue(t.batchNo ?? ''),
        IntCellValue(t.qty),
        TextCellValue('${t.fromWarehouse} to ${t.toWarehouse}'),
        TextCellValue(t.note),
      ]);
    }
  }

  static void _exportSales(Excel excel, List<Sale> sales) {
    Sheet sheet = excel['Sales'];
    sheet.appendRow([
      TextCellValue('Sale ID'),
      TextCellValue('Date'),
      TextCellValue('Receipt No'),
      TextCellValue('Total Amount'),
      TextCellValue('Discount'),
      TextCellValue('Items'),
      TextCellValue('Status'),
    ]);

    for (var s in sales) {
      List<dynamic> items = [];
      try {
        items = jsonDecode(s.itemsJson);
      } catch (_) {}
      
      String itemsInfo = items.map((i) => '${i['medicineName']} x${i['qty']}').join(', ');
      sheet.appendRow([
        IntCellValue(s.id),
        TextCellValue(s.createdAt.toIso8601String()),
        TextCellValue(s.invoiceNo),
        DoubleCellValue(s.total),
        DoubleCellValue(s.discount),
        TextCellValue(itemsInfo),
        TextCellValue(s.isReturn ? 'RETURN' : 'COMPLETED'),
      ]);
    }
  }

  static void _exportPatients(Excel excel, List<Patient> patients) {
    Sheet sheet = excel['Patients'];
    sheet.appendRow([
      TextCellValue('Patient ID'),
      TextCellValue('UHID'),
      TextCellValue('Name'),
      TextCellValue('Phone'),
      TextCellValue('Gender'),
      TextCellValue('Age'),
      TextCellValue('Registered Date'),
    ]);

    for (var p in patients) {
      sheet.appendRow([
        IntCellValue(p.id),
        TextCellValue(p.uhid),
        TextCellValue(p.name),
        TextCellValue(p.phone),
        TextCellValue(p.gender),
        IntCellValue(p.age),
        TextCellValue(p.createdAt.toIso8601String()),
      ]);
    }
  }

  static void _exportPrescriptions(Excel excel, List<Prescription> prescriptions) {
    Sheet sheet = excel['Prescriptions'];
    sheet.appendRow([
      TextCellValue('Prescription ID'),
      TextCellValue('Date'),
      TextCellValue('Patient UHID'),
      TextCellValue('Doctor ID'),
      TextCellValue('Medicines'),
      TextCellValue('Notes'),
    ]);

    for (var pr in prescriptions) {
      List<dynamic> items = [];
      try {
        items = jsonDecode(pr.itemsJson);
      } catch (_) {}
      
      String medInfo = items.map((m) => '${m['medicineName']} (${m['dosage'] ?? ''})').join(', ');
      sheet.appendRow([
        IntCellValue(pr.id),
        TextCellValue(pr.createdAt.toIso8601String()),
        TextCellValue('${pr.patientName} (ID: ${pr.patientId})'),
        TextCellValue('${pr.doctorName} (ID: ${pr.doctorId})'),
        TextCellValue(medInfo),
        TextCellValue(pr.notes),
      ]);
    }
  }
}
