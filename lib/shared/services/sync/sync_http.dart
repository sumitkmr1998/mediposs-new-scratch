import 'package:http/http.dart' as http;
import 'dart:io';

/// Thin HTTP helper shared by extracted sync pull modules.
class SyncHttp {
  SyncHttp({
    required this.baseUrl,
    required this.headers,
  });

  final String baseUrl;
  final Map<String, String> headers;

  Uri uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p').replace(queryParameters: query);
  }

  Future<http.Response> get(String path, [Map<String, String>? query]) {
    return checkedGet(uri(path, query), headers: headers);
  }

  static Future<http.Response> checkedGet(Uri uri,
      {Map<String, String>? headers,
      http.Client? client,
      Duration timeout = const Duration(seconds: 30)}) async {
    final res = await (client == null
            ? http.get(uri, headers: headers)
            : client.get(uri, headers: headers))
        .timeout(timeout);
    if (res.statusCode != 200) {
      throw HttpException('Hub pull failed: ${res.statusCode}', uri: uri);
    }
    return res;
  }

  Future<http.Response> post(String path, {Object? body}) {
    return http.post(
      uri(path),
      headers: {
        ...headers,
        'Content-Type': 'application/json',
      },
      body: body is String ? body : null,
    );
  }
}
