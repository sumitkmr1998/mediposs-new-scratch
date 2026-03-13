import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/sale.dart';
import '../models/medicine.dart';

class DataPersistenceService {
  static final DataPersistenceService _instance = DataPersistenceService._();
  static DataPersistenceService get instance => _instance;

  DataPersistenceService._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'mediposs_data.db');

    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS medicines (
        id INTEGER PRIMARY KEY,
        name TEXT,
        category TEXT,
        unit TEXT,
        barcode TEXT,
        purchasePrice REAL,
        sellingPrice REAL,
        mainStock INTEGER,
        storeStock INTEGER,
        lowStockThreshold INTEGER,
        updatedAt TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id INTEGER PRIMARY KEY,
        invoiceNo TEXT,
        patientName TEXT,
        subtotal REAL,
        discount REAL,
        taxAmount REAL,
        total REAL,
        paymentMethod TEXT,
        createdAt TEXT,
        isReturn INTEGER,
        itemsJson TEXT,
        updatedAt TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sales_createdAt ON sales(createdAt)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_medicines_id ON medicines(id)
    ''');
  }

  // ========== MEDICINES OPERATIONS ==========

  Future<void> saveMedicines(List<Medicine> medicines) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();

    for (final med in medicines) {
      batch.insert(
        'medicines',
        {
          'id': med.id,
          'name': med.name,
          'category': med.category,
          'unit': med.unit,
          'barcode': med.barcode,
          'purchasePrice': med.purchasePrice,
          'sellingPrice': med.sellingPrice,
          'mainStock': med.mainStock,
          'storeStock': med.storeStock,
          'lowStockThreshold': med.lowStockThreshold,
          'updatedAt': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Medicine>> loadMedicines() async {
    final db = await database;
    final maps = await db.query('medicines', orderBy: 'name ASC');
    return maps.map((m) => Medicine(
      id: m['id'] as int,
      name: m['name'] as String,
      category: m['category'] as String? ?? 'General',
      unit: m['unit'] as String? ?? 'Pcs',
      barcode: m['barcode'] as String? ?? '',
      purchasePrice: (m['purchasePrice'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (m['sellingPrice'] as num?)?.toDouble() ?? 0.0,
      mainStock: m['mainStock'] as int? ?? 0,
      storeStock: m['storeStock'] as int? ?? 0,
      lowStockThreshold: m['lowStockThreshold'] as int? ?? 10,
    )).toList();
  }

  // ========== SALES OPERATIONS ==========

  Future<void> saveSales(List<Sale> sales) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();

    for (final sale in sales) {
      final itemsList = sale.items.map((item) => {
        'medicineId': item.medicineId,
        'medicineName': item.medicineName,
        'qty': item.qty,
        'unitPrice': item.unitPrice,
      }).toList();

      batch.insert(
        'sales',
        {
          'id': sale.id,
          'invoiceNo': sale.invoiceNo,
          'patientName': sale.patientName,
          'subtotal': sale.subtotal,
          'discount': sale.discount,
          'taxAmount': sale.taxAmount,
          'total': sale.total,
          'paymentMethod': sale.paymentMethod,
          'createdAt': sale.createdAt.toIso8601String(),
          'isReturn': sale.isReturn ? 1 : 0,
          'itemsJson': jsonEncode(itemsList),
          'updatedAt': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Sale>> loadSales() async {
    final db = await database;
    final maps = await db.query('sales', orderBy: 'createdAt DESC');
    
    return maps.map((m) {
      List<SaleItem> items = [];
      final itemsJson = m['itemsJson'] as String?;
      if (itemsJson != null && itemsJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(itemsJson) as List;
          items = decoded.map((e) => SaleItem.fromJson(e as Map<String, dynamic>)).toList();
        } catch (_) {}
      }

      return Sale(
        id: m['id'] as int,
        invoiceNo: m['invoiceNo'] as String? ?? '',
        patientName: m['patientName'] as String? ?? 'Unknown',
        subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0.0,
        discount: (m['discount'] as num?)?.toDouble() ?? 0.0,
        taxAmount: (m['taxAmount'] as num?)?.toDouble() ?? 0.0,
        total: (m['total'] as num?)?.toDouble() ?? 0.0,
        paymentMethod: m['paymentMethod'] as String? ?? 'cash',
        createdAt: DateTime.parse(m['createdAt'] as String),
        isReturn: (m['isReturn'] as int?) == 1,
        items: items,
      );
    }).toList();
  }

  // ========== UTILITY METHODS ==========

  Future<DateTime?> getLastUpdateTime() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT MAX(updatedAt) as lastUpdate FROM (SELECT updatedAt FROM medicines UNION ALL SELECT updatedAt FROM sales)"
    );
    if (result.isNotEmpty && result.first['lastUpdate'] != null) {
      return DateTime.tryParse(result.first['lastUpdate'] as String);
    }
    return null;
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('medicines');
    await db.delete('sales');
  }

  Future<int> getSalesCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM sales');
    return result.first['count'] as int? ?? 0;
  }

  Future<int> getMedicinesCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM medicines');
    return result.first['count'] as int? ?? 0;
  }
}
