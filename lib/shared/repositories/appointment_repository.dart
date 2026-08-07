import '../models/appointment.dart';
import '../services/objectbox_service.dart';
import '../../objectbox.g.dart';

class AppointmentRepository {
  Box<Appointment> get _box => ObjectBoxService.instance.appointmentBox;

  /// Window for queue UI: [windowStart, dayEnd].
  List<Appointment> inScheduledRange(DateTime start, DateTime end) {
    final q = _box
        .query(
          Appointment_.scheduledAt.between(
            start.millisecondsSinceEpoch,
            end.millisecondsSinceEpoch,
          ),
        )
        .order(Appointment_.scheduledAt, flags: Order.descending)
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  List<Appointment> forPatient(int patientId, {int limit = 50}) {
    final q = _box
        .query(Appointment_.patientId.equals(patientId))
        .order(Appointment_.scheduledAt, flags: Order.descending)
        .build();
    try {
      q.limit = limit;
      return q.find();
    } finally {
      q.close();
    }
  }

  Appointment? byId(int id) => _box.get(id);

  int put(Appointment a) => _box.put(a);

  int count() => _box.count();
}
