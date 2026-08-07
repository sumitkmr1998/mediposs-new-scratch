import 'package:http/http.dart' as http;

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
    return http.get(uri(path, query), headers: headers);
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
