import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:medipos/objectbox.g.dart';
import 'package:medipos/shared/models/sync_queue_item.dart';

void main() async {
  const srcDir = 'C:\\Users\\sumit\\AppData\\Roaming\\com.medipos\\medipos\\mediposs_terminal_db';
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

    final store = Store(getObjectBoxModel(), directory: tempDir.path);
    final box = store.box<SyncQueueItem>();
    final items = box.getAll();

    print('\nLocal Sync Queue Count: ${items.length}');
    for (final item in items) {
      print('ID: ${item.id}, Entity: ${item.entity}, Action: ${item.action}, Timestamp: ${item.timestamp.toIso8601String()}');
      try {
        final data = jsonDecode(item.dataJson);
        print('  Data: $data');
      } catch (_) {}
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
