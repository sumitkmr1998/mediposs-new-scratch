import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medipos/shared/services/sync/sync_http.dart';

void main() {
  final uri = Uri.parse('http://hub/api/sales');
  for (final status in [401, 403, 500, 503]) {
    test('HTTP $status is failure rather than empty successful snapshot', () {
      final client = MockClient((_) async => http.Response('{}', status));
      expect(SyncHttp.checkedGet(uri, client: client),
          throwsA(isA<HttpException>()));
    });
  }
  test('hung pull has a bounded deadline', () {
    final client = MockClient((_) => Completer<http.Response>().future);
    expect(
        SyncHttp.checkedGet(uri,
            client: client, timeout: const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()));
  });
  test('successful pull retains payload', () async {
    final client = MockClient((_) async => http.Response('{"data":[]}', 200));
    expect(
        (await SyncHttp.checkedGet(uri, client: client)).body, '{"data":[]}');
  });
}
