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

  late final Store _store;
  late final String _dbDirectory;

  late final Box<Medicine> medicineBox;
  late final Box<StockTransfer> transferBox;
  late final Box<Sale> saleBox;
  late final Box<AppUser> userBox;
  late final Box<AppSettings> settingsBox;
  late final Box<PurchaseRecord> purchaseBox;
  late final Box<MedicineBatch> batchBox;
  late final Box<RestockRequest> restockRequestBox;
  late final Box<SyncQueueItem> syncQueueBox;
  late final Box<AuditLog> auditLogBox;
  late final Box<AttendanceRecord> attendanceBox;

  // OPD Boxes
  late final Box<Patient> patientBox;
  late final Box<Doctor> doctorBox;
  late final Box<Appointment> appointmentBox;
  late final Box<Prescription> prescriptionBox;
  late final Box<PrescriptionTemplate> templateBox;
  late final Box<PatientImage> patientImageBox;
  late final Box<Procedure> procedureBox;
  late final Box<ProcedureRecord> procedureRecordBox;
  late final Box<DailyMedicineSalesFact> salesFactBox;

  ObjectBoxService._();

  static Future<ObjectBoxService> init({bool forceTerminal = false}) async {
    if (_instance != null) return _instance!;


    final svc = ObjectBoxService._();
    
    // Explicitly set directory for desktop consistency
    final appSupportDir = await getApplicationSupportDirectory();
    final prefs = await SharedPreferences.getInstance();
    final isTerminalMode = forceTerminal || (prefs.getBool('isTerminalMode') ?? false);

    if (isTerminalMode) {
      svc._dbDirectory = p.join(appSupportDir.path, 'mediposs_terminal_db');
    } else {
      svc._dbDirectory = p.join(appSupportDir.path, 'mediposs_db');
    }
    debugPrint('ObjectBoxService.init: isTerminalMode=$isTerminalMode, dbDirectory=${svc._dbDirectory}');
    
    svc._store = await openStore(directory: svc._dbDirectory);

    svc.medicineBox = svc._store.box<Medicine>();
    svc.transferBox = svc._store.box<StockTransfer>();
    svc.saleBox = svc._store.box<Sale>();
    svc.userBox = svc._store.box<AppUser>();
    svc.settingsBox = svc._store.box<AppSettings>();
    svc.purchaseBox = svc._store.box<PurchaseRecord>();
    svc.batchBox = svc._store.box<MedicineBatch>();
    svc.restockRequestBox = svc._store.box<RestockRequest>();
    svc.syncQueueBox = svc._store.box<SyncQueueItem>();
    svc.auditLogBox = svc._store.box<AuditLog>();
    svc.attendanceBox = svc._store.box<AttendanceRecord>();

    // OPD boxes
    svc.patientBox = svc._store.box<Patient>();
    svc.doctorBox = svc._store.box<Doctor>();
    svc.appointmentBox = svc._store.box<Appointment>();
    svc.prescriptionBox = svc._store.box<Prescription>();
    svc.templateBox = svc._store.box<PrescriptionTemplate>();
    svc.patientImageBox = svc._store.box<PatientImage>();
    svc.procedureBox = svc._store.box<Procedure>();
    svc.procedureRecordBox = svc._store.box<ProcedureRecord>();
    svc.salesFactBox = svc._store.box<DailyMedicineSalesFact>();

    // Seed default settings if empty
    if (svc.settingsBox.isEmpty()) {
      svc.settingsBox.put(AppSettings()..isWindowsClient = isTerminalMode);
    } else {
      final existing = svc.settingsBox.getAll().first;
      if (existing.isWindowsClient != isTerminalMode) {
        existing.isWindowsClient = isTerminalMode;
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
