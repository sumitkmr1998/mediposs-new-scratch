import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/app_user.dart';
import '../objectbox_service.dart';
import '../../../objectbox.g.dart';
import 'sync_http.dart';

/// Extracted user pull used by SyncService.
Future<void> pullUsersWithHttp(SyncHttp httpClient) async {
  try {
    final res = await httpClient.get('/api/users');
    if (res.statusCode != 200) {
      debugPrint('pullUsers: status ${res.statusCode}');
      return;
    }
    final payload = jsonDecode(res.body);
    final data = payload is Map ? payload['data'] as List? : payload as List?;
    if (data == null) return;

    final box = ObjectBoxService.instance.userBox;
    final existing = {for (final u in box.getAll()) u.name.toLowerCase(): u};

    for (final item in data) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final name = (map['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      final local = existing[key];
      if (local != null) {
        // Keep local PIN if hub sends placeholder.
        final pin = map['pin'] as String? ?? local.pin;
        map['pin'] = (pin == 'xxxx' || pin.isEmpty) ? local.pin : pin;
        map['id'] = local.id;
      } else {
        map['id'] = 0;
      }
      final user = AppUser.fromJson(map);
      box.put(user);
      existing[key] = user;
    }
    debugPrint('pullUsers: synced ${data.length} users');
  } catch (e) {
    debugPrint('pullUsers err: $e');
  }
}
