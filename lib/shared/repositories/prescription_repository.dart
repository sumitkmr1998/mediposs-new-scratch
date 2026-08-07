import '../models/prescription.dart';
import '../services/objectbox_service.dart';
import '../../objectbox.g.dart';

class PrescriptionRepository {
  Box<Prescription> get _box => ObjectBoxService.instance.prescriptionBox;

  List<Prescription> inCreatedRange(DateTime start, DateTime end) {
    final q = _box
        .query(
          Prescription_.createdAt.between(
            start.millisecondsSinceEpoch,
            end.millisecondsSinceEpoch,
          ),
        )
        .order(Prescription_.createdAt, flags: Order.descending)
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  List<Prescription> recent({int limit = 200}) {
    final q = _box
        .query()
        .order(Prescription_.createdAt, flags: Order.descending)
        .build();
    try {
      q.limit = limit;
      return q.find();
    } finally {
      q.close();
    }
  }

  List<Prescription> forPatient(int patientId, {int limit = 50}) {
    final q = _box
        .query(Prescription_.patientId.equals(patientId))
        .order(Prescription_.createdAt, flags: Order.descending)
        .build();
    try {
      q.limit = limit;
      return q.find();
    } finally {
      q.close();
    }
  }

  List<Prescription> forAppointment(int appointmentId) {
    final q = _box
        .query(Prescription_.appointmentId.equals(appointmentId))
        .order(Prescription_.createdAt, flags: Order.descending)
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  int put(Prescription p) => _box.put(p);
}
