import '../models/patient.dart';
import '../services/objectbox_service.dart';
import '../../objectbox.g.dart';

class PatientRepository {
  Box<Patient> get _box => ObjectBoxService.instance.patientBox;

  List<Patient> recent({int limit = 50, int offset = 0}) {
    final q = _box
        .query()
        .order(Patient_.createdAt, flags: Order.descending)
        .build();
    try {
      q.limit = limit;
      q.offset = offset;
      return q.find();
    } finally {
      q.close();
    }
  }

  /// Name / phone / UHID contains search, newest first.
  List<Patient> search(String term, {int limit = 50, int offset = 0}) {
    final t = term.trim();
    if (t.isEmpty) return recent(limit: limit, offset: offset);

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
      q.offset = offset;
      return q.find();
    } finally {
      q.close();
    }
  }

  Patient? byId(int id) => _box.get(id);

  int count() => _box.count();
}
