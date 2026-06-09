import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../lib/objectbox.g.dart';
import '../lib/shared/models/sale.dart';
import '../lib/shared/models/app_user.dart';

void main() async {
  final srcDir = 'C:\\Users\\sumit\\AppData\\Roaming\\com.medipos\\medipos\\mediposs_terminal_db';
  final tempDir = Directory(p.join(Directory.current.path, 'scratch', 'temp_db'));
  
  if (tempDir.existsSync()) {
    tempDir.deleteSync(recursive: true);
  }
  tempDir.createSync(recursive: true);

  print('Copying active database from $srcDir to ${tempDir.path}...');
  try {
    final dataFile = File(p.join(srcDir, 'data.mdb'));
    final lockFile = File(p.join(srcDir, 'lock.mdb'));
    if (dataFile.existsSync()) {
      dataFile.copySync(p.join(tempDir.path, 'data.mdb'));
    }
    if (lockFile.existsSync()) {
      lockFile.copySync(p.join(tempDir.path, 'lock.mdb'));
    }

    print('Opening temporary copy of the database...');
    final store = Store(getObjectBoxModel(), directory: tempDir.path);
    
    // 1. Read Users
    final userBox = store.box<AppUser>();
    final users = userBox.getAll();
    print('\nSynced Users in Client DB:');
    for (final u in users) {
      print('Name: ${u.name}, Role: ${u.role}, PIN: ${u.pin}');
    }

    // 2. Read today's sales
    final saleBox = store.box<Sale>();
    final allSales = saleBox.getAll();
    print('\nTotal sales in Client DB: ${allSales.length}');

    final targetDate = DateTime(2026, 6, 9);
    final todaySales = [];

    for (final s in allSales) {
      final localTime = s.createdAt.toLocal();
      if (localTime.year == targetDate.year &&
          localTime.month == targetDate.month &&
          localTime.day == targetDate.day) {
        todaySales.add(s);
      }
    }

    print('Today\'s Sales in Client DB: ${todaySales.length}');
    todaySales.sort((a, b) => b.invoiceNo.compareTo(a.invoiceNo));
    for (final s in todaySales) {
      print('${s.invoiceNo}: total=${s.total}, isReturn=${s.isReturn}, createdAt=${s.createdAt.toIso8601String()}');
    }

    store.close();
  } catch (e) {
    print('Error: $e');
  } finally {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}
