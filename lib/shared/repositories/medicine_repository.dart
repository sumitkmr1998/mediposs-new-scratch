import '../models/medicine.dart';
import '../services/objectbox_service.dart';
import '../../objectbox.g.dart';

class MedicineRepository {
  Box<Medicine> get _box => ObjectBoxService.instance.medicineBox;

  List<Medicine> getAll() => _box.getAll();

  Medicine? byId(int id) => _box.get(id);

  Medicine? byBarcode(String barcode) {
    final b = barcode.trim();
    if (b.isEmpty) return null;
    final q = _box.query(Medicine_.barcode.equals(b)).build();
    try {
      return q.findFirst();
    } finally {
      q.close();
    }
  }

  List<Medicine> searchByName(String term, {int limit = 50}) {
    final t = term.trim();
    if (t.isEmpty) {
      final q = _box.query().order(Medicine_.name).build();
      try {
        q.limit = limit;
        return q.find();
      } finally {
        q.close();
      }
    }
    final q = _box
        .query(Medicine_.name.contains(t, caseSensitive: false))
        .order(Medicine_.name)
        .build();
    try {
      q.limit = limit;
      return q.find();
    } finally {
      q.close();
    }
  }

  int put(Medicine m) => _box.put(m);

  void putMany(List<Medicine> list) => _box.putMany(list);

  int count() => _box.count();
}
