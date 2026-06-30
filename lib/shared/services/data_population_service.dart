import 'dart:convert';
import 'dart:math';
import '../models/medicine.dart';
import '../models/sale.dart';
import '../models/doctor.dart';
import '../models/patient.dart';
import '../models/appointment.dart';
import '../models/prescription.dart';
import '../models/stock_transfer.dart';
import 'objectbox_service.dart';

class DataPopulationService {
  final _random = Random();
  final ObjectBoxService _boxService = ObjectBoxService.instance;

  Future<void> populateCustomDataFor6Months() async {
    print('Starting custom Mediposs data population (6 months)...');
    
    // Ensure we have doctors
    var doctors = _boxService.doctorBox.getAll();
    if (doctors.isEmpty) {
      doctors = _generateDoctors();
      _boxService.doctorBox.putMany(doctors);
    }
    
    // Ensure we have medicines
    var medicines = _boxService.medicineBox.getAll();
    if (medicines.isEmpty) {
      medicines = _generateMedicines();
      _boxService.medicineBox.putMany(medicines);
      
      // Re-fetch to get correct ObjectBox IDs
      medicines = _boxService.medicineBox.getAll();
    }

    final now = DateTime.now();
    final startDate = now.subtract(const Duration(days: 180)); // 6 months
    
    final allSales = <Sale>[];
    final allTransfers = <StockTransfer>[];

    int patientCounter = 1;
    int tokenCounter = 1;
    
    for (int i = 0; i < 180; i++) {
      final date = startDate.add(Duration(days: i));
      
      // 1. Generate 30 patients daily
      final dailyPatients = <Patient>[];
      for (int p = 0; p < 30; p++) {
        final createdTime = DateTime(date.year, date.month, date.day, 8 + _random.nextInt(12), _random.nextInt(60));
        final patient = Patient(
          name: 'Patient ${patientCounter++}',
          uhid: 'OPD-${date.day.toString().padLeft(2, '0')}${date.month.toString().padLeft(2, '0')}${date.year.toString().substring(2)}-${(1000 + _random.nextInt(9000))}',
          phone: '9${100000000 + _random.nextInt(900000000)}',
          gender: _random.nextBool() ? 'Male' : 'Female',
          age: 18 + _random.nextInt(60),
          address: 'Street ${_random.nextInt(100)}, City',
          bloodGroup: ['A+', 'B+', 'O+', 'AB+'][_random.nextInt(4)],
          createdAt: createdTime,
          updatedAt: createdTime,
        );
        dailyPatients.add(patient);
      }
      
      // Save patients so we get valid IDs for Appointments and Prescriptions
      _boxService.patientBox.putMany(dailyPatients);
      
      // 2. Generate 30 dispenses daily (Linked Appointment, Prescription, and Sale)
      for (int d = 0; d < 30; d++) {
        final patient = dailyPatients[d % dailyPatients.length];
        final doctor = doctors[_random.nextInt(doctors.length)];
        final appointmentTime = DateTime(date.year, date.month, date.day, 9 + _random.nextInt(8), _random.nextInt(60));
        
        final appointment = Appointment(
          patientId: patient.id,
          patientName: patient.name,
          patientPhone: patient.phone,
          doctorId: doctor.id,
          doctorName: doctor.name,
          tokenNumber: tokenCounter++,
          status: kStatusDone,
          consultationFee: doctor.consultationFee,
          scheduledAt: appointmentTime,
          createdAt: appointmentTime,
          updatedAt: appointmentTime,
          isWalkIn: _random.nextBool(),
          consultationBilled: true,
          paymentMethod: _random.nextBool() ? 'cash' : 'upi',
        );
        appointment.completedAt = appointmentTime.add(Duration(minutes: 15 + _random.nextInt(30)));
        _boxService.appointmentBox.put(appointment);
        
        // Items logic: Average 5 items, average cart value 1500
        final itemsCount = 3 + _random.nextInt(4); // 3 to 6 items
        final prescriptionItems = <PrescriptionItem>[];
        final saleItems = <SaleItem>[];
        
        final targetSubtotal = 1200 + _random.nextInt(600); // 1200 - 1800, average 1500
        double currentTotal = 0;
        
        for (int itemIdx = 0; itemIdx < itemsCount; itemIdx++) {
          final med = medicines[_random.nextInt(medicines.length)];
          final remainingTarget = targetSubtotal - currentTotal;
          final itemTarget = remainingTarget / (itemsCount - itemIdx);
          
          int qty = (itemTarget / med.sellingPrice).round();
          if (qty <= 0) qty = 1;
          if (qty > 15) qty = 15;
          
          prescriptionItems.add(PrescriptionItem(
            medicineId: med.id,
            medicineName: med.name,
            qty: qty,
            dosage: '1-0-1',
            days: 5,
            isAvailable: true,
          ));
          
          saleItems.add(SaleItem(
            medicineId: med.id,
            medicineName: med.name,
            qty: qty,
            unitPrice: med.sellingPrice,
            batchNo: med.batches.isNotEmpty ? med.batches.first.batchNo : 'B-100',
            expiryDate: med.batches.isNotEmpty ? med.batches.first.expiryDate.toIso8601String() : DateTime.now().add(const Duration(days: 365)).toIso8601String(),
          ));
          currentTotal += med.sellingPrice * qty;
        }
        
        final prescription = Prescription(
          appointmentId: appointment.id,
          patientId: patient.id,
          patientName: patient.name,
          doctorId: doctor.id,
          doctorName: doctor.name,
          dispensed: true,
          itemsJson: jsonEncode(prescriptionItems.map((pi) => pi.toJson()).toList()),
          createdAt: appointmentTime,
          updatedAt: appointmentTime,
        );
        _boxService.prescriptionBox.put(prescription);
        
        final dateStr = '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
        final timeStr = '${appointmentTime.hour.toString().padLeft(2, '0')}${appointmentTime.minute.toString().padLeft(2, '0')}${appointmentTime.second.toString().padLeft(2, '0')}';
        final invoiceNo = 'DISP-$dateStr-$timeStr-$d';
        
        final sale = Sale(
          invoiceNo: invoiceNo,
          patientId: patient.id,
          patientName: patient.name,
          patientPhone: patient.phone,
          patientUhid: patient.uhid,
          subtotal: currentTotal,
          discount: 0,
          total: currentTotal,
          paymentMethod: _random.nextBool() ? 'cash' : 'upi',
          createdAt: appointmentTime.add(const Duration(minutes: 10)),
          updatedAt: appointmentTime.add(const Duration(minutes: 10)),
          isClinicalDispense: true,
          linkedAppointmentId: appointment.id,
          itemsJson: jsonEncode(saleItems.map((si) => si.toJson()).toList()),
        );
        allSales.add(sale);
      }

      // 3. Generate 20 sales daily (retail/walk-in, isClinicalDispense = false)
      for (int s = 0; s < 20; s++) {
        final saleTime = DateTime(date.year, date.month, date.day, 10 + _random.nextInt(10), _random.nextInt(60));
        final itemsCount = 3 + _random.nextInt(4); // 3 to 6 items
        final saleItems = <SaleItem>[];
        final targetSubtotal = 1200 + _random.nextInt(600); // 1200 - 1800, average 1500
        double currentTotal = 0;
        
        for (int itemIdx = 0; itemIdx < itemsCount; itemIdx++) {
          final med = medicines[_random.nextInt(medicines.length)];
          final remainingTarget = targetSubtotal - currentTotal;
          final itemTarget = remainingTarget / (itemsCount - itemIdx);
          
          int qty = (itemTarget / med.sellingPrice).round();
          if (qty <= 0) qty = 1;
          if (qty > 15) qty = 15;
          
          saleItems.add(SaleItem(
            medicineId: med.id,
            medicineName: med.name,
            qty: qty,
            unitPrice: med.sellingPrice,
            batchNo: med.batches.isNotEmpty ? med.batches.first.batchNo : 'B-100',
            expiryDate: med.batches.isNotEmpty ? med.batches.first.expiryDate.toIso8601String() : DateTime.now().add(const Duration(days: 365)).toIso8601String(),
          ));
          currentTotal += med.sellingPrice * qty;
        }

        final dateStr = '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
        final timeStr = '${saleTime.hour.toString().padLeft(2, '0')}${saleTime.minute.toString().padLeft(2, '0')}${saleTime.second.toString().padLeft(2, '0')}';
        final invoiceNo = 'RET-$dateStr-$timeStr-$s';
        
        final patient = _random.nextBool() ? dailyPatients[_random.nextInt(dailyPatients.length)] : null;

        final sale = Sale(
          invoiceNo: invoiceNo,
          patientId: patient?.id ?? 0,
          patientName: patient?.name ?? 'Walk-in Customer',
          patientPhone: patient?.phone ?? '',
          patientUhid: patient?.uhid ?? '',
          subtotal: currentTotal,
          discount: 0,
          total: currentTotal,
          paymentMethod: _random.nextBool() ? 'cash' : 'upi',
          createdAt: saleTime,
          updatedAt: saleTime,
          isClinicalDispense: false,
          itemsJson: jsonEncode(saleItems.map((si) => si.toJson()).toList()),
        );
        allSales.add(sale);
      }

      // 4. Generate 10 transfers daily
      for (int t = 0; t < 10; t++) {
        final med = medicines[_random.nextInt(medicines.length)];
        final qty = 5 + _random.nextInt(25);
        final transferTime = DateTime(date.year, date.month, date.day, 9 + _random.nextInt(9), _random.nextInt(60));
        
        final transfer = StockTransfer(
          medicineId: med.id,
          medicineName: med.name,
          qty: qty,
          fromWarehouse: _random.nextBool() ? 'main' : 'store',
          toWarehouse: _random.nextBool() ? 'store' : 'main',
          batchNo: med.batches.isNotEmpty ? med.batches.first.batchNo : 'B-100',
          expiryDate: med.batches.isNotEmpty ? med.batches.first.expiryDate : DateTime.now().add(const Duration(days: 365)),
          transferredAt: transferTime,
          note: 'Daily stock transfer balancing',
          transferredBy: 'Admin',
        );
        allTransfers.add(transfer);
      }
      
      // Save to database in chunks to prevent memory overhead
      if (allSales.length >= 500) {
        _boxService.saleBox.putMany(allSales);
        allSales.clear();
      }
      if (allTransfers.length >= 500) {
        _boxService.transferBox.putMany(allTransfers);
        allTransfers.clear();
      }

      if (i % 15 == 0) {
        print('Generated day $i/180 ($date)...');
      }
    }

    if (allSales.isNotEmpty) {
      _boxService.saleBox.putMany(allSales);
    }
    if (allTransfers.isNotEmpty) {
      _boxService.transferBox.putMany(allTransfers);
    }

    print('Custom population of 6-months data complete!');
  }

  Future<void> populateOneYearData() async {
    print('Starting Mediposs data population...');

    // 1. Generate Doctors
    final doctors = _generateDoctors();
    _boxService.doctorBox.putMany(doctors);

    // 2. Generate Patients
    final patients = _generatePatients();
    _boxService.patientBox.putMany(patients);

    // 3. Generate Medicines
    final medicines = _generateMedicines();
    _boxService.medicineBox.putMany(medicines);

    final now = DateTime.now();
    final yearAgo = now.subtract(const Duration(days: 365));

    final allSales = <Sale>[];

    // 2. Iterate through each day of the past year
    for (int i = 0; i <= 365; i++) {
      final date = yearAgo.add(Duration(days: i));
      
      // Generate Sales for this day
      final dailySalesCount = 3 + _random.nextInt(8); // 3-10 sales
      for (int s = 0; s < dailySalesCount; s++) {
        allSales.add(_generateSale(date, medicines, s));
      }

      if (i % 30 == 0) {
        print('Generated data up to $date...');
      }
    }

    _boxService.saleBox.putMany(allSales);

    print('Population complete!');
    print('Total Medicines created: ${medicines.length}');
    print('Total Sales created: ${allSales.length}');
  }

  List<Doctor> _generateDoctors() {
    final doctorData = [
      ['Dr. Sarah Smith', 'Cardiologist', 500.0, 'MD, DM', '9876543210'],
      ['Dr. James Wilson', 'Pediatrician', 300.0, 'MD', '9876543211'],
      ['Dr. Anita Sharma', 'Dermatologist', 400.0, 'MD, DDVL', '9876543212'],
      ['Dr. Robert Brown', 'Orthopedic', 450.0, 'MS', '9876543213'],
      ['Dr. Emily Davis', 'Gynecologist', 500.0, 'MS, DNB', '9876543214'],
    ];

    return doctorData.map((data) => Doctor(
      name: data[0] as String,
      specialization: data[1] as String,
      consultationFee: (data[2] as num).toDouble(),
      qualifications: data[3] as String,
      phone: data[4] as String,
      isActive: true,
    )).toList();
  }

  List<Patient> _generatePatients() {
    final patientNames = [
      'John Doe', 'Jane Smith', 'Michael Johnson', 'Emily Brown', 'Chris Wilson',
      'David Miller', 'Linda Taylor', 'Robert Moore', 'Lisa Anderson', 'Sarah Thomas'
    ];
    
    return patientNames.map((name) => Patient(
      name: name,
      uhid: 'UHID-${1000 + _random.nextInt(9000)}',
      phone: '90000${10000 + _random.nextInt(90000)}',
      gender: _random.nextBool() ? 'Male' : 'Female',
      age: 18 + _random.nextInt(60),
      address: 'Lane ${_random.nextInt(100)}, City',
      bloodGroup: ['A+', 'B+', 'O+', 'AB+'][_random.nextInt(4)],
    )).toList();
  }

  List<Medicine> _generateMedicines() {
    final medicineData = [
      ['Paracetamol 500mg', 'General', 'Tab', 15.0, 20.0],
      ['Amoxicillin 250mg', 'Antibiotic', 'Cap', 40.0, 55.0],
      ['Cetirizine 10mg', 'Allergy', 'Tab', 10.0, 15.0],
      ['Ibuprofen 400mg', 'Painkiller', 'Tab', 20.0, 30.0],
      ['Pantoprazole 40mg', 'Gastric', 'Tab', 60.0, 90.0],
      ['Azithromycin 500mg', 'Antibiotic', 'Tab', 150.0, 220.0],
      ['Amlodipine 5mg', 'BP', 'Tab', 30.0, 55.0],
      ['Metformin 500mg', 'Diabetes', 'Tab', 20.0, 40.0],
      ['Cough Syrup 100ml', 'Syrup', 'Bottle', 35.0, 50.0],
      ['Multivitamin Gold', 'Supplements', 'Tab', 50.0, 100.0],
      ['Ofloxacin Drops', 'Eye Drop', 'Vial', 300.0, 550.0],
      ['Diclofenac Gel', 'Painkiller', 'Tube', 40.0, 65.0],
      ['Vitamin D3 Sachet', 'Supplements', 'Sachet', 12.0, 30.0],
      ['Atorvastatin 10mg', 'Cholesterol', 'Tab', 80.0, 140.0],
      ['Losartan 50mg', 'BP', 'Tab', 50.0, 90.0],
    ];

    return medicineData.map((data) {
      final m = Medicine(
        name: data[0] as String,
        barcode: '110${_random.nextInt(1000)}',
        category: data[1] as String,
        unit: data[2] as String,
        purchasePrice: (data[3] as num).toDouble(),
        sellingPrice: (data[4] as num).toDouble(),
        mainStock: 1000,
        storeStock: 200,
      );

      // Add batches
      for (int j = 0; j < 2; j++) {
        final batch = MedicineBatch(
          batchNo: 'B-${2000 + _random.nextInt(1000)}',
          expiryDate: DateTime.now().add(Duration(days: 30 + _random.nextInt(600))),
          mainStock: 300 + _random.nextInt(200),
          storeStock: 50 + _random.nextInt(50),
        );
        batch.medicine.target = m;
        m.batches.add(batch);
      }
      return m;
    }).toList();
  }

  Sale _generateSale(DateTime date, List<Medicine> medicines, int index) {
    final saleTime = DateTime(date.year, date.month, date.day, 9 + _random.nextInt(12), _random.nextInt(60));
    
    final itemCount = 1 + _random.nextInt(3);
    final saleItems = <Map<String, dynamic>>[];
    double subtotal = 0;

    for (int i = 0; i < itemCount; i++) {
      final med = medicines[_random.nextInt(medicines.length)];
      final qty = 1 + _random.nextInt(5);
      saleItems.add({
        'medicineId': med.id, // Note: id will be 0 initially unless medicines saved first
        'medicineName': med.name,
        'qty': qty,
        'unitPrice': med.sellingPrice,
      });
      subtotal += med.sellingPrice * qty;
    }

    final dateStr = '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final timeStr = '${date.hour.toString().padLeft(2, '0')}${date.minute.toString().padLeft(2, '0')}${date.second.toString().padLeft(2, '0')}';
    final invoiceNo = 'INV-$dateStr-$timeStr';

    return Sale(
      invoiceNo: invoiceNo,
      patientName: 'Customer ${_random.nextInt(1000)}',
      subtotal: subtotal,
      discount: 0,
      taxAmount: 0,
      total: subtotal,
      paymentMethod: _random.nextBool() ? 'cash' : 'upi',
      createdAt: saleTime,
      isReturn: false,
    )..itemsJson = jsonEncode(saleItems);
  }
}
