import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medipos/shared/services/device_identity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('DeviceIdentityService generates and persists a 2-character device code', () async {
    final code1 = await DeviceIdentityService.getDeviceCode();
    expect(code1, isNotEmpty);
    expect(code1.length, equals(2));

    // Calling it again must return the exact same persisted code
    final code2 = await DeviceIdentityService.getDeviceCode();
    expect(code2, equals(code1));

    // Must match alphanumeric format (e.g. H0, A1, W1, etc.)
    expect(RegExp(r'^[A-Z][0-9A-Z]$').hasMatch(code1), isTrue);
  });
}

