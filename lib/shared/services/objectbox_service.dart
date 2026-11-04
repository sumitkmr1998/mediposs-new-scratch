import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/medicine.dart';
import '../models/stock_transfer.dart';
import '../models/sale.dart';
import '../models/app_user.dart';
import '../models/patient.dart';
import '../models/doctor.dart';
import '../models/appointment.dart';
import '../models/prescription.dart';
import '../models/prescription_template.dart';
import '../models/patient_image.dart';
import '../models/purchase_record.dart';
import '../models/restock_request.dart';
import '../models/sync_queue_item.dart';
import '../models/procedure.dart';
import '../models/audit_log.dart';
import '../models/attendance_record.dart';
import '../models/daily_medicine_sales_fact.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../objectbox.g.dart';
import 'device_identity_service.dart';

class ObjectBoxService {
  static ObjectBoxService? _instance;
  static bool get isInitialized => _instance != null;
  static ObjectBoxService get instance => _instance!;

  late Store _store;
  late String _dbDirectory;
  String _currentShopId = 'default_shop';
  String get currentShopId => _currentShopId;

  late Box<Medicine> medicineBox;
  late Box<StockTransfer> transferBox;
  late Box<Sale> saleBox;
  late Box<AppUser> userBox;
  late Box<AppSettings> settingsBox;
  late Box<PurchaseRecord> purchaseBox;
  late Box<MedicineBatch> batchBox;
  late Box<RestockRequest> restockRequestBox;
  late Box<SyncQueueItem> syncQueueBox;
  late Box<AuditLog> auditLogBox;
  late Box<AttendanceRecord> attendanceBox;

  // OPD Boxes
  late Box<Patient> patientBox;
  late Box<Doctor> doctorBox;
  late Box<Appointment> appointmentBox;
  late Box<Prescription> prescriptionBox;
  late Box<PrescriptionTemplate> templateBox;
  late Box<PatientImage> patientImageBox;
  late Box<Procedure> procedureBox;
  late Box<ProcedureRecord> procedureRecordBox;
  late Box<DailyMedicineSalesFact> salesFactBox;

  ObjectBoxService._();

  static String sanitizeShopId(String shopId) {
    final sanitized = shopId.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return sanitized.isNotEmpty ? sanitized : 'default_shop';
  }

  void _bindBoxes() {
    medicineBox = _store.box<Medicine>();
    transferBox = _store.box<StockTransfer>();
    saleBox = _store.box<Sale>();
    userBox = _store.box<AppUser>();
    settingsBox = _store.box<AppSettings>();
    purchaseBox = _store.box<PurchaseRecord>();
    batchBox = _store.box<MedicineBatch>();
    restockRequestBox = _store.box<RestockRequest>();
    syncQueueBox = _store.box<SyncQueueItem>();
    auditLogBox = _store.box<AuditLog>();
    attendanceBox = _store.box<AttendanceRecord>();

    // OPD boxes
    patientBox = _store.box<Patient>();
    doctorBox = _store.box<Doctor>();
    appointmentBox = _store.box<Appointment>();
    prescriptionBox = _store.box<Prescription>();
    templateBox = _store.box<PrescriptionTemplate>();
    patientImageBox = _store.box<PatientImage>();
    procedureBox = _store.box<Procedure>();
    procedureRecordBox = _store.box<ProcedureRecord>();
    salesFactBox = _store.box<DailyMedicineSalesFact>();
  }

  static Future<ObjectBoxService> init({bool forceTerminal = false}) async {
    if (_instance != null) return _instance!;

    final svc = ObjectBoxService._();
    
    // Explicitly set directory for desktop consistency
    final appSupportDir = await getApplicationSupportDirectory();
    final prefs = await SharedPreferences.getInstance();
    final isTerminalMode = forceTerminal || (prefs.getBool('isTerminalMode') ?? false);
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    if (isMobile || isTerminalMode) {
      String activeShop = prefs.getString('activeShopId') ?? '';
      if (activeShop.isEmpty) {
        activeShop = 'default_shop';
      }
      final cleanShop = sanitizeShopId(activeShop);
      svc._currentShopId = cleanShop;
      svc._dbDirectory = p.join(appSupportDir.path, 'partitions', cleanShop);

      // Legacy migration: if legacy DB exists and partitions/cleanShop does not, migrate
      final legacyDir = Directory(p.join(appSupportDir.path, isTerminalMode ? 'mediposs_terminal_db' : 'mediposs_db'));
      final targetDir = Directory(svc._dbDirectory);
      if (legacyDir.existsSync() && !targetDir.existsSync()) {
        try {
          debugPrint('ObjectBoxService: Migrating legacy DB to partition $cleanShop');
          await targetDir.create(recursive: true);
          await svc._copyDir(legacyDir, targetDir);
        } catch (e) {
          debugPrint('ObjectBoxService: Migration error: $e');
        }
      }
    } else {
      svc._dbDirectory = p.join(appSupportDir.path, 'mediposs_db');
    }
    debugPrint('ObjectBoxService.init: isTerminalMode=$isTerminalMode, dbDirectory=${svc._dbDirectory}');
    
    final dir = Directory(svc._dbDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    svc._store = await openStore(directory: svc._dbDirectory);
    svc._bindBoxes();

    // Seed default settings if empty
    if (svc.settingsBox.isEmpty()) {
      svc.settingsBox.put(AppSettings()
        ..isWindowsClient = isTerminalMode
        ..shopId = svc._currentShopId);
    } else {
      final existing = svc.settingsBox.getAll().first;
      if (existing.isWindowsClient != isTerminalMode) {
        existing.isWindowsClient = isTerminalMode;
      }
      if (isMobile || isTerminalMode) {
        existing.shopId = svc._currentShopId;
      }
      if (existing.autoLoginPin != null) existing.autoLoginPin = null;
      svc.settingsBox.put(existing);
    }

    // Initialize device identity asynchronously
    DeviceIdentityService.initDeviceId();

    if (svc.userBox.isEmpty() && Platform.isWindows && !isTerminalMode) {
      svc.userBox.put(AppUser(
        name: 'Admin',
        role: 'Admin',
        pin: 'SETUP_REQUIRED',
        canAccessSettings: true,
        canManageUsers: true,
        canViewDashboard: true,
        canViewInventory: true,
        canEditInventory: true,
        canViewWarehouse: true,
        canTransferStock: true,
        canEditTransfers: true,
        canAccessPOS: true,
        canDiscountSales: true,
        canViewSalesHistory: true,
        canVoidSales: true,
        canProcessReturns: true,
      ));
    }

    _repairMissingTimestamps(svc);

    _instance = svc;
    return svc;
  }

  static void _repairMissingTimestamps(ObjectBoxService svc) {
    final epoch = DateTime(2000);
    
    // 1. Medicine
    final badMeds = svc.medicineBox
        .query(Medicine_.updatedAt.lessThan(epoch.millisecondsSinceEpoch))
        .build();
    final meds = badMeds.find();
    badMeds.close();
    if (meds.isNotEmpty) {
      for (final m in meds) {
        m.updatedAt = m.createdAt.isBefore(epoch) ? DateTime.now() : m.createdAt;
      }
      svc.medicineBox.putMany(meds);
      debugPrint('ObjectBoxService: Repaired ${meds.length} medicines with missing timestamps.');
    }

    // 2. Patient
    final badPatients = svc.patientBox
        .query(Patient_.updatedAt.lessThan(epoch.millisecondsSinceEpoch))
        .build();
    final patients = badPatients.find();
    badPatients.close();
    if (patients.isNotEmpty) {
      for (final p in patients) {
        p.updatedAt = p.createdAt.isBefore(epoch) ? DateTime.now() : p.createdAt;
      }
      svc.patientBox.putMany(patients);
      debugPrint('ObjectBoxService: Repaired ${patients.length} patients with missing timestamps.');
    }

    // 3. Prescription
    final badPrescriptions = svc.prescriptionBox
        .query(Prescription_.updatedAt.lessThan(epoch.millisecondsSinceEpoch))
        .build();
    final prescriptions = badPrescriptions.find();
    badPrescriptions.close();
    if (prescriptions.isNotEmpty) {
      for (final pr in prescriptions) {
        pr.updatedAt = pr.createdAt.isBefore(epoch) ? DateTime.now() : pr.createdAt;
      }
      svc.prescriptionBox.putMany(prescriptions);
      debugPrint('ObjectBoxService: Repaired ${prescriptions.length} prescriptions with missing timestamps.');
    }

    // 4. Sale
    final badSales = svc.saleBox
        .query(Sale_.updatedAt.lessThan(epoch.millisecondsSinceEpoch))
        .build();
    final sales = badSales.find();
    badSales.close();
    if (sales.isNotEmpty) {
      for (final s in sales) {
        s.updatedAt = s.createdAt.isBefore(epoch) ? DateTime.now() : s.createdAt;
      }
      svc.saleBox.putMany(sales);
      debugPrint('ObjectBoxService: Repaired ${sales.length} sales with missing timestamps.');
    }
  }
 
  /// Switches active ObjectBox database partition to the specified shop.
  /// Used by companion clients (Android/iOS/Terminal) to maintain isolated local caches per shop.
  Future<void> switchToPartition(String shopId) async {
    final cleanShop = sanitizeShopId(shopId);
    if (_currentShopId == cleanShop) {
      debugPrint('ObjectBoxService: Already on partition $cleanShop');
      return;
    }

    final appSupportDir = await getApplicationSupportDirectory();
    final newDbDirectory = p.join(appSupportDir.path, 'partitions', cleanShop);

    debugPrint('ObjectBoxService: Switching partition from $_currentShopId to $cleanShop ($newDbDirectory)');

    // 1. Close current store
    _store.close();

    // 2. Open new store
    _currentShopId = cleanShop;
    _dbDirectory = newDbDirectory;
    final targetDir = Directory(newDbDirectory);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    _store = await openStore(directory: newDbDirectory);
    _bindBoxes();

    // 3. Persist activeShopId in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeShopId', cleanShop);

    // 4. Update or seed settings for this shop
    if (settingsBox.isEmpty()) {
      settingsBox.put(AppSettings()..shopId = cleanShop);
    } else {
      final s = settingsBox.getAll().first;
      s.shopId = cleanShop;
      settingsBox.put(s);
    }

    _repairMissingTimestamps(this);
    debugPrint('ObjectBoxService: Switched to partition $cleanShop successfully.');
  }

  Future<void> close() async {
    _store.close();
  }
 
  Future<void> createLocalSafetyBackup() async {
    final appSupportDir = await getApplicationSupportDirectory();
    final safetyBackupDir = Directory(p.join(appSupportDir.path, 'mediposs_safety_backup_${DateTime.now().millisecondsSinceEpoch}'));
    await safetyBackupDir.create(recursive: true);
    
    final dbDir = Directory(_dbDirectory);
    if (await dbDir.exists()) {
      await _copyDir(dbDir, Directory(p.join(safetyBackupDir.path, 'database')));
    }
  }
 
  Future<void> _copyDir(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list()) {
      final newPath = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDir(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  Store get store => _store;
  String get dbDirectory => _dbDirectory;

  AppSettings get settings => settingsBox.getAll().isNotEmpty
      ? settingsBox.getAll().first
      : AppSettings();
}
