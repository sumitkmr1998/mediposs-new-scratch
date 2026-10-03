import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A Hub-only key. It must not be copied to terminals or included in sync JSON.
class HubSigningKey {
  static Future<String> load({Directory? directory}) async {
    final root = directory ?? await getApplicationSupportDirectory();
    await root.create(recursive: true);
    final keyFile = File(p.join(root.path, 'mediposs_hub_signing.key'));
    if (await keyFile.exists()) {
      final saved = (await keyFile.readAsString()).trim();
      if (saved.length < 40) throw StateError('Invalid Hub signing key');
      return saved;
    }
    final random = Random.secure();
    final key = base64UrlEncode(List<int>.generate(48, (_) => random.nextInt(256)));
    await keyFile.writeAsString(key, flush: true);
    return key;
  }
}
