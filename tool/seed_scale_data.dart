// ignore_for_file: avoid_print
/// Seed a large ObjectBox dataset for local perf checks.
///
/// Usage (from project root, after `flutter pub get`):
///   dart run tool/seed_scale_data.dart
///
/// Profiles:
///   --profile=year5   (default) 3k meds, 20k patients, 100k sales, 50k appts
///   --profile=smoke   small set for CI
///
/// Writes into the normal app support DB path — use a throwaway machine or
/// backup first. Does not open Flutter bindings beyond ObjectBox init.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:medipos/shared/models/appointment.dart';
import 'package:medipos/shared/models/medicine.dart';
import 'package:medipos/shared/models/patient.dart';
import 'package:medipos/shared/models/sale.dart';
import 'package:medipos/shared/services/migration_service.dart';
import 'package:medipos/shared/services/objectbox_service.dart';
import 'package:medipos/shared/services/sales_fact_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Profile {
  final String name;
  final int medicines;
  final int patients;
  final int sales;
  final int appointments;

  const Profile({
    required this.name,
    required this.medicines,
    required this.patients,
    required this.sales,
    required this.appointments,
  });
}

const year5 = Profile(
  name: 'year5',
  medicines: 3000,
  patients: 20000,
  sales: 100000,
  appointments: 50000,
);

const smoke = Profile(
  name: 'smoke',
  medicines: 50,
  patients: 100,
  sales: 500,
  appointments: 200,
);

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  var profile = year5;
  for (final a in args) {
    if (a.startsWith('--profile=')) {
      final p = a.split('=').last;
      profile = p == 'smoke' ? smoke : year5;
    }
  }

  print('Seeding profile=${profile.name} …');
  final support = await getApplicationSupportDirectory();
  print('App support: ${support.path}');

  await ObjectBoxService.init(forceTerminal: true);
  await MigrationService.runIfNeeded();
  final db = ObjectBoxService.instance;
  final rng = Random(42);

  // Clear large boxes for clean bench (keeps users/settings).
  db.saleBox.removeAll();
  db.patientBox.removeAll();
  db.appointmentBox.removeAll();
  db.medicineBox.removeAll();
  db.salesFactBox.removeAll();

  print('Inserting ${profile.medicines} medicines…');
  final meds = <Medicine>[];
  for (var i = 0; i < profile.medicines; i++) {
    meds.add(Medicine(
      name: 'Med $i',
      barcode: 'B${i.toString().padLeft(8, '0')}',
      purchasePrice: 10 + (i % 50).toDouble(),
      sellingPrice: 15 + (i % 50).toDouble(),
      mainStock: 50 + (i % 100),
      storeStock: 20 + (i % 40),
      lowStockThreshold: 10,
    ));
    if (meds.length >= 500) {
      db.medicineBox.putMany(meds);
      meds.clear();
    }
  }
  if (meds.isNotEmpty) db.medicineBox.putMany(meds);
  final allMeds = db.medicineBox.getAll();
  print('  medicines=${allMeds.length}');

  print('Inserting ${profile.patients} patients…');
  final patients = <Patient>[];
  for (var i = 0; i < profile.patients; i++) {
    patients.add(Patient(
      uhid: 'OPD-SEED-${i.toString().padLeft(6, '0')}',
      name: 'Patient $i',
      phone: '9${(100000000 + i).toString().substring(0, 9)}',
    ));
    if (patients.length >= 500) {
      db.patientBox.putMany(patients);
      patients.clear();
    }
  }
  if (patients.isNotEmpty) db.patientBox.putMany(patients);
  print('  patients=${db.patientBox.count()}');

  print('Inserting ${profile.appointments} appointments…');
  final now = DateTime.now();
  final appts = <Appointment>[];
  for (var i = 0; i < profile.appointments; i++) {
    final day = now.subtract(Duration(days: i % 400));
    appts.add(Appointment(
      patientId: (i % max(1, db.patientBox.count())) + 1,
      patientName: 'Patient ${i % profile.patients}',
      doctorId: 1,
      doctorName: 'Dr Seed',
      tokenNumber: (i % 80) + 1,
      status: i % 20 == 0 ? kStatusWaiting : kStatusDone,
      scheduledAt: DateTime(day.year, day.month, day.day, 9 + (i % 8)),
      consultationFee: 300,
    ));
    if (appts.length >= 500) {
      db.appointmentBox.putMany(appts);
      appts.clear();
    }
  }
  if (appts.isNotEmpty) db.appointmentBox.putMany(appts);
  print('  appointments=${db.appointmentBox.count()}');

  print('Inserting ${profile.sales} sales…');
  final sales = <Sale>[];
  for (var i = 0; i < profile.sales; i++) {
    final day = now.subtract(Duration(days: i % 365));
    final med = allMeds[i % allMeds.length];
    final qty = 1 + rng.nextInt(5);
    final items = [
      {
        'medicineId': med.id,
        'medicineName': med.name,
        'qty': qty,
        'unitPrice': med.sellingPrice,
        'isProcedure': false,
      }
    ];
    sales.add(Sale(
      invoiceNo: 'INV-SEED-${i.toString().padLeft(7, '0')}',
      patientId: (i % max(1, db.patientBox.count())) + 1,
      patientName: 'Patient ${i % profile.patients}',
      subtotal: med.sellingPrice * qty,
      total: med.sellingPrice * qty,
      itemsJson: jsonEncode(items),
      createdAt: DateTime(day.year, day.month, day.day, 10 + (i % 10)),
    ));
    if (sales.length >= 500) {
      db.saleBox.putMany(sales);
      sales.clear();
      if (i % 10000 == 0) print('  … $i');
    }
  }
  if (sales.isNotEmpty) db.saleBox.putMany(sales);
  print('  sales=${db.saleBox.count()}');

  print('Backfilling sales facts…');
  final sw = Stopwatch()..start();
  final n = SalesFactService.instance.backfillFromSales(clearFirst: true);
  sw.stop();
  print('  facts from $n sales in ${sw.elapsedMilliseconds}ms');
  print('  fact rows=${db.salesFactBox.count()}');

  print('Done. Run: dart run tool/perf_bench.dart');
  exit(0);
}

int max(int a, int b) => a > b ? a : b;
