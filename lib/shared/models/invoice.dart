import 'package:intl/intl.dart';

class Invoice {
  final String invoiceNo;
  final String patientId;
  final String clinicName;
  final String clinicAddress;
  final String registrationNo;
  final String doctorName;
  final String patientName;
  final String diagnosis;
  final DateTime date;
  final List<InvoiceItem> items;
  final double totalAmount;

  final bool isClinicalDispense;

  Invoice({
    required this.invoiceNo,
    required this.patientId,
    required this.clinicName,
    required this.clinicAddress,
    required this.registrationNo,
    required this.doctorName,
    required this.patientName,
    required this.diagnosis,
    required this.date,
    required this.items,
    required this.totalAmount,
    this.isClinicalDispense = false,
  });

  String get formattedDate => DateFormat('dd/MM/yyyy').format(date);
}

class InvoiceItem {
  final String name;
  final int quantity;
  final double rate;
  final String batchNo;
  final String expiryDate;

  InvoiceItem({
    required this.name,
    required this.quantity,
    required this.rate,
    this.batchNo = '',
    this.expiryDate = '',
  });

  double get amount => quantity * rate;
}
