import '../models/patient.dart';
import '../services/objectbox_service.dart';
import '../../objectbox.g.dart';

class PatientRepository {
  Box<Patient> get _box => ObjectBoxService.instance.patientBox;

  List<Patient> recent({int limit = 100}) {
    final q = _box
        .query()
        .order(Patient_.createdAt, flags: Order.descending)
        .build();
    try {
      q.limit = limit;
      return q.find();
    } finally {
      q.close();
    }
  }

  /// Name / phone / UHID contains search, newest first.
  List<Patient> search(String term, {int limit = 50}) {
    final t = term.trim();
    if (t.isEmpty) return recent(limit: limit);

    final q = _box
        .query(
          Patient_.name
              .contains(t, caseSensitive: false)
              .or(Patient_.phone.contains(t, caseSensitive: false))
              .or(Patient_.uhid.contains(t, caseSensitive: false)),
        )
        .order(Patient_.createdAt, flags: Order.descending)
        .build();
    try {
      q.limit = limit;
      return q.find();
    } finally {
      q.close();
    }
  }

  Patient? byId(int id) => _box.get(id);

  int count() => _box.count();
}
