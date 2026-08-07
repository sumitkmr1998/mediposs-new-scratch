import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Shared JSON response helpers for the local hub server routes.
Response jsonOk(Object? data, {int? serverTime}) {
  return Response.ok(
    jsonEncode({
      'data': data,
      if (serverTime != null) 'serverTime': serverTime,
    }),
    headers: {'Content-Type': 'application/json'},
  );
}

Response jsonError(String message, {int status = 400}) {
  return Response(
    status,
    body: jsonEncode({'error': message}),
    headers: {'Content-Type': 'application/json'},
  );
}

Response jsonMessage(String message, {int status = 200}) {
  return Response(
    status,
    body: jsonEncode({'message': message}),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Parse JSON body map; returns null if invalid.
Future<Map<String, dynamic>?> readJsonMap(Request request) async {
  try {
    final body = await request.readAsString();
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  } catch (_) {
    return null;
  }
}
