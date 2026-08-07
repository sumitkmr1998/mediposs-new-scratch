import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/services/mutation_service.dart';

void main() {
  group('MutationService defaults', () {
    test('default hub events for known entities', () {
      final m = MutationService.instance;
      expect(m.defaultEventsFor('medicine', 'create'), ['medicines_updated']);
      expect(m.defaultEventsFor('sale', 'delete'),
          ['sale_deleted', 'sales_updated']);
      expect(m.defaultEventsFor('patient', 'create'),
          ['patients_updated', 'new_patient']);
      expect(m.defaultEventsFor('unknown', 'x'), ['sync_received']);
    });
  });
}
