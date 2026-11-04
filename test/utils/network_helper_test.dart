import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/utils/network_helper.dart';

void main() {
  test('NetworkHelper.getLocalIp returns a valid non-virtual IP', () async {
    final ip = await NetworkHelper.getLocalIp();
    print('Detected local IP: $ip');
    expect(ip, isNotEmpty);
    expect(ip, isNot(equals('127.0.0.1')));
    // Should NOT be the virtual vgate0 IP
    expect(ip.startsWith('172.30.'), isFalse);
    expect(RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(ip), isTrue);
  });
}

