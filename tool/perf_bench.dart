// ignore_for_file: avoid_print
/// Quick query budgets against the local ObjectBox DB (after seed_scale_data).
///
///   dart run tool/perf_bench.dart

import 'package:flutter/widgets.dart';
import 'package:medipos/shared/providers/opd_provider.dart';
import 'package:medipos/shared/repositories/patient_repository.dart';
import 'package:medipos/shared/repositories/sale_repository.dart';
import 'package:medipos/shared/services/objectbox_service.dart';
import 'package:medipos/shared/services/sales_fact_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await ObjectBoxService.init(forceTerminal: true);

  final sales = SaleRepository();
  final patients = PatientRepository();
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

  Future<int> timeMs(String label, void Function() fn) async {
    final sw = Stopwatch()..start();
    fn();
    sw.stop();
    print('$label: ${sw.elapsedMilliseconds}ms');
    return sw.elapsedMilliseconds;
  }

  print('=== MediPoss perf bench ===');
  print('sales=${ObjectBoxService.instance.saleBox.count()} '
      'patients=${ObjectBoxService.instance.patientBox.count()} '
      'meds=${ObjectBoxService.instance.medicineBox.count()} '
      'facts=${ObjectBoxService.instance.salesFactBox.count()}');

  await timeMs('salesInRange(today) limit 30', () {
    sales.salesInRange(todayStart, todayEnd, limit: 30);
  });

  await timeMs('salesLastDays(30)', () {
    sales.salesLastDays(30);
  });

  await timeMs('patient search "a" limit 50', () {
    patients.search('a', limit: 50);
  });

  await timeMs('consumptionLastDays(30) facts', () {
    SalesFactService.instance.consumptionLastDays(30);
  });

  await timeMs('OpdProvider.loadQueue', () {
    OpdProvider().loadQueue();
  });

  print('Targets: sales today <50ms, patient search <50ms, facts <100ms, OPD queue <100ms');
  print('(Soft budgets — wall clock varies by machine.)');
}
