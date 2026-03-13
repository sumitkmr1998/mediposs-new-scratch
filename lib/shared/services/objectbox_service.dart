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
import '../../objectbox.g.dart';

class ObjectBoxService {
  static ObjectBoxService? _instance;
  static ObjectBoxService get instance => _instance!;

  late final Store _store;

  late final Box<Medicine> medicineBox;
  late final Box<StockTransfer> transferBox;
  late final Box<Sale> saleBox;
  late final Box<AppUser> userBox;
  late final Box<AppSettings> settingsBox;
  late final Box<PurchaseRecord> purchaseBox;
  late final Box<MedicineBatch> batchBox;

  // OPD Boxes
  late final Box<Patient> patientBox;
  late final Box<Doctor> doctorBox;
  late final Box<Appointment> appointmentBox;
  late final Box<Prescription> prescriptionBox;
  late final Box<PrescriptionTemplate> templateBox;
  late final Box<PatientImage> patientImageBox;

  ObjectBoxService._();

  static Future<ObjectBoxService> init() async {
    if (_instance != null) return _instance!;


    final svc = ObjectBoxService._();
    svc._store = await openStore();

    svc.medicineBox = svc._store.box<Medicine>();
    svc.transferBox = svc._store.box<StockTransfer>();
    svc.saleBox = svc._store.box<Sale>();
    svc.userBox = svc._store.box<AppUser>();
    svc.settingsBox = svc._store.box<AppSettings>();
    svc.purchaseBox = svc._store.box<PurchaseRecord>();
    svc.batchBox = svc._store.box<MedicineBatch>();

    // OPD boxes
    svc.patientBox = svc._store.box<Patient>();
    svc.doctorBox = svc._store.box<Doctor>();
    svc.appointmentBox = svc._store.box<Appointment>();
    svc.prescriptionBox = svc._store.box<Prescription>();
    svc.templateBox = svc._store.box<PrescriptionTemplate>();
    svc.patientImageBox = svc._store.box<PatientImage>();

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

    // Seed sample medicines
    if (svc.medicineBox.isEmpty()) {
      final sampleMedicines = [
        Medicine(
            name: 'Paracetamol 500mg',
            barcode: '10001',
            category: 'General',
            unit: 'Tab',
            purchasePrice: 15.0,
            sellingPrice: 20.0)
          ..mainStock = 500
          ..storeStock = 100,
        Medicine(
            name: 'Amoxicillin 250mg',
            barcode: '10002',
            category: 'Antibiotic',
            unit: 'Cap',
            purchasePrice: 40.0,
            sellingPrice: 55.0)
          ..mainStock = 200
          ..storeStock = 50,
        Medicine(
            name: 'Cetirizine 10mg',
            barcode: '10003',
            category: 'Allergy',
            unit: 'Tab',
            purchasePrice: 10.0,
            sellingPrice: 15.0)
          ..mainStock = 300
          ..storeStock = 150,
        Medicine(
            name: 'Ibuprofen 400mg',
            barcode: '10004',
            category: 'Painkiller',
            unit: 'Tab',
            purchasePrice: 20.0,
            sellingPrice: 30.0)
          ..mainStock = 400
          ..storeStock = 80,
        Medicine(
            name: 'Cough Syrup 100ml',
            barcode: '10005',
            category: 'Syrup',
            unit: 'Bottle',
            purchasePrice: 35.0,
            sellingPrice: 50.0)
          ..mainStock = 100
          ..storeStock = 20,
      ];

      for (var i = 0; i < sampleMedicines.length; i++) {
        final m = sampleMedicines[i];
        final expDate = i == 0 
            ? DateTime.now().subtract(const Duration(days: 10)) // Expired
            : i == 1 
                ? DateTime.now().add(const Duration(days: 15)) // Near expiry
                : DateTime.now().add(const Duration(days: 400)); // Normal
        
        final batch = MedicineBatch(
          batchNo: 'BAT-${100 + i}',
          expiryDate: expDate,
          mainStock: m.mainStock,
          storeStock: m.storeStock,
        );
        batch.medicine.target = m;
        m.batches.add(batch);
        svc.medicineBox.put(m);
      }
    }

    _instance = svc;
    return svc;
  }

  Store get store => _store;

  AppSettings get settings => settingsBox.getAll().isNotEmpty
      ? settingsBox.getAll().first
      : AppSettings();
}
