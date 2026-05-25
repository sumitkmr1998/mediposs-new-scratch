import 'dart:io';
import 'package:flutter/foundation.dart';
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
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../objectbox.g.dart';

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

  // OPD Boxes
  late final Box<Patient> patientBox;
  late final Box<Doctor> doctorBox;
  late final Box<Appointment> appointmentBox;
  late final Box<Prescription> prescriptionBox;
  late final Box<PrescriptionTemplate> templateBox;
  late final Box<PatientImage> patientImageBox;
  late final Box<Procedure> procedureBox;
  late final Box<ProcedureRecord> procedureRecordBox;

  ObjectBoxService._();

  static Future<ObjectBoxService> init() async {
    if (_instance != null) return _instance!;


    final svc = ObjectBoxService._();
    
    // Explicitly set directory for desktop consistency
    final appSupportDir = await getApplicationSupportDirectory();
    svc._dbDirectory = p.join(appSupportDir.path, 'mediposs_db');
    
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

    // OPD boxes
    svc.patientBox = svc._store.box<Patient>();
    svc.doctorBox = svc._store.box<Doctor>();
    svc.appointmentBox = svc._store.box<Appointment>();
    svc.prescriptionBox = svc._store.box<Prescription>();
    svc.templateBox = svc._store.box<PrescriptionTemplate>();
    svc.patientImageBox = svc._store.box<PatientImage>();
    svc.procedureBox = svc._store.box<Procedure>();
    svc.procedureRecordBox = svc._store.box<ProcedureRecord>();

    // Seed default settings if empty
    if (svc.settingsBox.isEmpty()) {
      svc.settingsBox.put(AppSettings());
    }

    if (svc.userBox.isEmpty()) {
      svc.userBox.put(AppUser(
        name: 'Admin',
        role: 'Admin',
        pin: '1234',
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

    // Self-healing: if the Hub's local DB was overwritten by a sync call, restore PINs to default
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux)) {
      final allUsers = svc.userBox.getAll();
      for (var u in allUsers) {
        if (u.pin == 'xxxx') {
          u.pin =
              '1234'; // Restore to default since 'xxxx' is invalid for local login
          svc.userBox.put(u);
        }
      }
    }



    _instance = svc;
    return svc;
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
