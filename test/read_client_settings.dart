import 'dart:io';
import 'package:path/path.dart' as p;
import '../lib/objectbox.g.dart';
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

    final store = Store(getObjectBoxModel(), directory: tempDir.path);
    final box = store.box<AppSettings>();
    final settings = box.getAll().firstOrNull;

    if (settings != null) {
      print('\nAppSettings:');
      print('AutoLoginName: ${settings.autoLoginName}');
      print('AutoLoginPin: ${settings.autoLoginPin}');
      print('ConnectionMode: ${settings.connectionMode}');
      print('IsWindowsClient: ${settings.isWindowsClient}');
      print('JWT Secret: ${settings.jwtSecret}');
    } else {
      print('No AppSettings found.');
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
