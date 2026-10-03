import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medipos/shared/services/sync/firestore_rest_reader.dart';

void main() {
  final uri = Uri.parse('https://firestore.test/documents/shop/sales?key=test');
  test('follows every page with authentication and encoded cursor', () async {
    var pages = 0;
    final client = MockClient((request) async {
      pages++;
      expect(request.headers['Authorization'], 'Bearer test');
      expect(request.url.queryParameters['key'], 'test');
      if (pages == 1) {
        return http.Response(
            jsonEncode({
              'documents': [
                {'name': 'sale-1'}
              ],
              'nextPageToken': 'cursor/with+spaces',
            }),
            200);
      }
      expect(request.url.queryParameters['pageToken'], 'cursor/with+spaces');
      return http.Response('{"documents":[{"name":"sale-2"}]}', 200);
    });
    final docs = await FirestoreRestReader.read(uri,
        headers: {'Authorization': 'Bearer test'}, client: client);
    expect(docs.map((doc) => doc['name']), ['sale-1', 'sale-2']);
    expect(pages, 2);
  });
  test('second page failure cannot be mistaken for complete first page', () {
    var pages = 0;
    final client = MockClient((_) async => ++pages == 1
        ? http.Response(
            '{"documents":[{"name":"sale-1"}],"nextPageToken":"next"}', 200)
        : http.Response('{}', 503));
    expect(FirestoreRestReader.read(uri, client: client),
        throwsA(isA<HttpException>()));
  });
  test('repeating pagination token terminates instead of looping', () {
    final client = MockClient(
        (_) async => http.Response('{"nextPageToken":"repeat"}', 200));
    expect(
        FirestoreRestReader.read(uri, client: client), throwsFormatException);
  });
  test('successful empty collection is distinguishable from a failed request',
      () async {
    final client = MockClient((_) async => http.Response('{}', 200));
    expect(await FirestoreRestReader.read(uri, client: client), isEmpty);
  });
}
