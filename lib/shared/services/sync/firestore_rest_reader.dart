import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Reads every ListDocuments page or fails; errors are never empty snapshots.
class FirestoreRestReader {
  static Future<List<Map<String, dynamic>>> read(Uri collection,
      {Map<String, String>? headers, http.Client? client}) async {
    final documents = <Map<String, dynamic>>[];
    final seenTokens = <String>{};
    String? pageToken;
    do {
      final uri = collection.replace(queryParameters: {
        ...collection.queryParameters,
        'pageSize': '500',
        if (pageToken != null) 'pageToken': pageToken,
      });
      final response = await (client == null
              ? http.get(uri, headers: headers)
              : client.get(uri, headers: headers))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('Cloud read failed: ${response.statusCode}',
            uri: uri);
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final page = payload['documents'] as List? ?? [];
      documents
          .addAll(page.map((doc) => Map<String, dynamic>.from(doc as Map)));
      pageToken = payload['nextPageToken'] as String?;
      if (pageToken != null &&
          pageToken.isNotEmpty &&
          !seenTokens.add(pageToken)) {
        throw const FormatException('Cloud pagination repeated a token');
      }
    } while (pageToken != null && pageToken.isNotEmpty);
    return documents;
  }
}
