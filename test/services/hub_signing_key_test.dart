import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/services/hub_signing_key.dart';

void main() {
  test('Hub signing key is random and stable per installation', () async {
    final first = await Directory.systemTemp.createTemp('hub-key-first-');
    final second = await Directory.systemTemp.createTemp('hub-key-second-');
    try {
      final key = await HubSigningKey.load(directory: first);
      expect(key.length, greaterThanOrEqualTo(40));
      expect(await HubSigningKey.load(directory: first), key);
      expect(await HubSigningKey.load(directory: second), isNot(key));
    } finally {
      await first.delete(recursive: true);
      await second.delete(recursive: true);
    }
  });
}
