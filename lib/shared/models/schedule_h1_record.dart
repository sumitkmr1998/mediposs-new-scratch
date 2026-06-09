import 'package:objectbox/objectbox.dart';
import '../utils/date_helper.dart';

@Entity()
class ScheduleH1Record {
  @Id()
  int id = 0;

  @Property(type: PropertyType.date)
  DateTime saleDate;

  String medicineName;
  String batchNo;
  int quantity;

  // Patient Info
  String patientName;
  String patientAddress;
  String patientPhone;

  // Doctor Info
  String doctorName;
  String doctorAddress;
  String doctorRegistrationNo;

  int linkedSaleId;
  String invoiceNo;

  ScheduleH1Record({
    this.id = 0,
    required this.saleDate,
    required this.medicineName,
    required this.batchNo,
    required this.quantity,
    required this.patientName,
    required this.patientAddress,
    required this.patientPhone,
    required this.doctorName,
    required this.doctorAddress,
    this.doctorRegistrationNo = '',
    required this.linkedSaleId,
    required this.invoiceNo,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'saleDate': saleDate.toIso8601String(),
        'medicineName': medicineName,
        'batchNo': batchNo,
        'quantity': quantity,
        'patientName': patientName,
        'patientAddress': patientAddress,
        'patientPhone': patientPhone,
        'doctorName': doctorName,
        'doctorAddress': doctorAddress,
        'doctorRegistrationNo': doctorRegistrationNo,
        'linkedSaleId': linkedSaleId,
        'invoiceNo': invoiceNo,
      };

  factory ScheduleH1Record.fromJson(Map<String, dynamic> json) => ScheduleH1Record(
        id: json['id'] ?? 0,
        saleDate: DateHelper.parseDateTime(json['saleDate']) ?? DateTime.now(),
        medicineName: json['medicineName'] ?? '',
        batchNo: json['batchNo'] ?? '',
        quantity: json['quantity'] ?? 0,
        patientName: json['patientName'] ?? '',
        patientAddress: json['patientAddress'] ?? '',
        patientPhone: json['patientPhone'] ?? '',
        doctorName: json['doctorName'] ?? '',
        doctorAddress: json['doctorAddress'] ?? '',
        doctorRegistrationNo: json['doctorRegistrationNo'] ?? '',
        linkedSaleId: json['linkedSaleId'] ?? 0,
        invoiceNo: json['invoiceNo'] ?? '',
      );
}
