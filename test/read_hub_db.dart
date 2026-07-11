import 'package:medipos/objectbox.g.dart';
import 'package:medipos/shared/models/sale.dart';

void main() async {
  const dbDir = 'C:\\Users\\sumit\\AppData\\Roaming\\com.medipos\\medipos\\mediposs_db';
  print('Opening Hub database at $dbDir...');

  try {
    final store = Store(getObjectBoxModel(), directory: dbDir);
    final box = store.box<Sale>();

    final allSales = box.getAll();
    print('Found ${allSales.length} total sales in Hub database.');

    final dateCounts = <String, int>{};
    final details = [];

    for (final s in allSales) {
      final dateStr = s.createdAt.toIso8601String().substring(0, 10);
      dateCounts[dateStr] = (dateCounts[dateStr] ?? 0) + 1;
      details.add('${s.invoiceNo}: total=${s.total}, isReturn=${s.isReturn}, createdAt=${s.createdAt.toIso8601String()}');
    }

    print('\nSales Count by Date in Hub DB:');
    dateCounts.forEach((date, count) {
      print('$date: $count');
    });

    print('\nLatest 20 Sales in Hub DB:');
    details.sort();
    final latest = details.reversed.take(20);
    for (final det in latest) {
      print(det);
    }

    store.close();
  } catch (e) {
    print('Error: $e');
  }
}
