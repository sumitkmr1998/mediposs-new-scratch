import 'dart:convert';
import 'dart:math';
import '../models/medicine.dart';
import '../models/sale.dart';
import '../models/doctor.dart';
import '../models/patient.dart';
import 'objectbox_service.dart';

class DataPopulationService {
  final _random = Random();
  final ObjectBoxService _boxService = ObjectBoxService.instance;

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

    return Sale(
      invoiceNo: 'INV-${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}-${_random.nextInt(10000)}',
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
