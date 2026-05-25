import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_user.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../firebase_options.dart';
import 'objectbox_service.dart';
import 'dart:convert';

class FirebaseSyncService {
  static FirebaseSyncService? _instance;
  static FirebaseSyncService get instance {
    if (_instance == null) {
      debugPrint('Warning: FirebaseSyncService.instance accessed before init(). Initializing dummy.');
      _instance = FirebaseSyncService._();
    }
    return _instance!;
  }

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  bool _isInitialized = false;

  String? _idToken;
  DateTime? _tokenExpiry;

  FirebaseSyncService._();

  static Future<void> init() async {
    if (_instance != null) return;
    _instance = FirebaseSyncService._();
    try {
      // Check if Firebase is initialized by accessing the app name
      Firebase.app();
      _instance!._isInitialized = true;

      if (defaultTargetPlatform != TargetPlatform.windows) {
        debugPrint('FirebaseSyncService: Triggering anonymous sign-in on mobile...');
        FirebaseAuth.instance.signInAnonymously().then((credential) {
          debugPrint('FirebaseSyncService: Anonymous sign-in successful: ${credential.user?.uid}');
        }).catchError((error) {
          debugPrint('FirebaseSyncService: Anonymous sign-in failed: $error');
        });
      }
    } catch (_) {
      debugPrint('FirebaseSyncService: Firebase core not initialized. Some features will be disabled.');
    }
  }

  // --- Hub Methods ---

  /// Updates the Hub's public Cloudflare URL and online status in Firebase.
  Future<void> updateHubStatus({
    required bool isOnline,
    String? cloudflareUrl,
    int? port,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _updateHubStatusREST(isOnline: isOnline, cloudflareUrl: cloudflareUrl, port: port);
      return;
    }

    if (!_isInitialized) return;
    try {
      await _db.collection('settings').doc('hub_status').set({
        'hubOnline': isOnline,
        'cloudflareUrl': cloudflareUrl,
        'serverPort': port ?? 8080,
        'lastGlobalSync': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firebase updateHubStatus failed: $e');
    }
  }

  DateTime? _lastAuthAttempt;
  bool _authDisabled = false;

  Future<String?> _getIdToken() async {
    if (_idToken != null && _tokenExpiry != null && _tokenExpiry!.isAfter(DateTime.now())) {
      return _idToken;
    }
    
    // Fallback if auth is disabled in console to avoid spamming 400 errors
    if (_authDisabled && _lastAuthAttempt != null && DateTime.now().difference(_lastAuthAttempt!).inMinutes < 10) {
      return null;
    }

    _lastAuthAttempt = DateTime.now();
    try {
      final apiKey = DefaultFirebaseOptions.windows.apiKey;
      final url = Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey');
      
      final res = await http.post(url, body: jsonEncode({'returnSecureToken': true}));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _idToken = data['idToken'];
        final expiresIn = int.tryParse(data['expiresIn'] ?? '3600') ?? 3600;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
        _authDisabled = false;
        debugPrint('Firebase [Auth]: Anonymous login successful.');
        return _idToken;
      } else {
        final err = res.body;
        if (err.contains('CONFIGURATION_NOT_FOUND')) {
          _authDisabled = true;
          debugPrint('Firebase [Auth]: Anonymous login is NOT enabled in your Firebase Console. Please enable it under Authentication -> Sign-in method.');
        } else {
          debugPrint('Firebase [Auth]: Login failed (${res.statusCode}): $err');
        }
      }
    } catch (e) {
      debugPrint('Firebase [Auth]: Error: $e');
    }
    return null;
  }

  /// Lightweight REST fallback for Windows to avoid crashing the Hub with native SDK
  Future<void> _updateHubStatusREST({
    required bool isOnline,
    String? cloudflareUrl,
    int? port,
  }) async {
    try {
      final token = await _getIdToken();
      final projectId = DefaultFirebaseOptions.windows.projectId;
      final apiKey = DefaultFirebaseOptions.windows.apiKey;
      final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/settings/hub_status?key=$apiKey');
      
      final body = jsonEncode({
        'fields': {
          'hubOnline': {'booleanValue': isOnline},
          'cloudflareUrl': {'stringValue': cloudflareUrl ?? ''},
          'serverPort': {'integerValue': port ?? 8080},
          'lastGlobalSync': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        }
      });

      final res = await http.patch(
        url, 
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
        body: body
      );
      if (res.statusCode == 200) {
        debugPrint('Firebase [REST]: Hub status updated successfully.');
      } else {
        debugPrint('Firebase [REST]: Update failed with ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('Firebase [REST]: Error: $e');
    }
  }

  // --- Sync Queue Logic ---

  /// Pushes a delta change to the Firestore sync queue.
  Future<bool> pushDelta({
    required String entity,
    required String action,
    required Map<String, dynamic> data,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return await _pushDeltaREST(entity: entity, action: action, data: data);
    }

    if (!_isInitialized) return false;
    try {
      final settings = ObjectBoxService.instance.settings;
      await _db.collection('sync_queue').add({
        'deviceId': settings.deviceId ?? 'unknown',
        'entity': entity,
        'action': action,
        'data': data,
        'timestamp': FieldValue.serverTimestamp(),
        'processed': false,
      });
      return true;
    } catch (e) {
      debugPrint('Firebase pushDelta error: $e');
      return false;
    }
  }

  Future<bool> _pushDeltaREST({
    required String entity,
    required String action,
    required Map<String, dynamic> data,
  }) async {
    try {
      final projectId = DefaultFirebaseOptions.windows.projectId;
      final apiKey = DefaultFirebaseOptions.windows.apiKey;
      final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/sync_queue?key=$apiKey');
      
      final settings = ObjectBoxService.instance.settings;
      final body = jsonEncode({
        'fields': {
          'deviceId': {'stringValue': settings.deviceId ?? 'unknown'},
          'entity': {'stringValue': entity},
          'action': {'stringValue': action},
          'data': {'mapValue': _convertToFirestoreMap(data)},
          'timestamp': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
          'processed': {'booleanValue': false},
        }
      });

      final token = await _getIdToken();
      final res = await http.post(
        url, 
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
        body: body
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        debugPrint('Firebase [REST]: Delta pushed successfully.');
        return true;
      } else {
        debugPrint('Firebase [REST]: Push failed with ${res.statusCode}: ${res.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Firebase [REST]: Error pushing delta: $e');
      return false;
    }
  }

  Map<String, dynamic> _convertToFirestoreValue(dynamic value) {
    if (value == null) return {'nullValue': null};
    if (value is String) return {'stringValue': value};
    if (value is int) return {'integerValue': value.toString()};
    if (value is double) return {'doubleValue': value};
    if (value is bool) return {'booleanValue': value};
    if (value is Map<String, dynamic>) {
      return {'mapValue': {'fields': _convertToFirestoreMap(value)}};
    }
    if (value is List) {
      return {
        'arrayValue': {
          'values': value.map((e) => _convertToFirestoreValue(e)).toList()
        }
      };
    }
    // Fallback for DateTime or other types
    return {'stringValue': value.toString()};
  }

  Map<String, dynamic> _convertToFirestoreMap(Map<String, dynamic> data) {
    final Map<String, dynamic> firestoreMap = {};
    data.forEach((key, value) {
      firestoreMap[key] = _convertToFirestoreValue(value);
    });
    return firestoreMap;
  }

  dynamic _convertFromFirestoreValue(Map<String, dynamic> value) {
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('integerValue')) return int.tryParse(value['integerValue'].toString()) ?? 0;
    if (value.containsKey('doubleValue')) return (value['doubleValue'] as num).toDouble();
    if (value.containsKey('booleanValue')) return value['booleanValue'];
    if (value.containsKey('nullValue')) return null;
    if (value.containsKey('mapValue')) return _convertFromFirestoreMap(value['mapValue']['fields'] ?? {});
    if (value.containsKey('arrayValue')) {
      final list = value['arrayValue']['values'] as List? ?? [];
      return list.map((e) => _convertFromFirestoreValue(e as Map<String, dynamic>)).toList();
    }
    return null;
  }

  Map<String, dynamic> _convertFromFirestoreMap(Map<String, dynamic> fields) {
    final Map<String, dynamic> data = {};
    fields.forEach((key, value) {
      data[key] = _convertFromFirestoreValue(value as Map<String, dynamic>);
    });
    return data;
  }

  /// Hub-side: Listens for incoming queue items and processes them.
  void startQueueListener(Function(Map<String, dynamic>) onNewItem) {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _startQueueListenerREST(onNewItem);
      return;
    }

    if (!_isInitialized) return;
    _db.collection('sync_queue')
        .where('processed', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        // Simple "lease" mechanism to prevent multiple Hubs (if any) from processing
        if (doc.data()['processingBy'] == null) {
          onNewItem({...doc.data(), 'id': doc.id});
        }
      }
    });
  }

  void _startQueueListenerREST(Function(Map<String, dynamic>) onNewItem) {
    // Polling every 15 seconds for new deltas
    Timer.periodic(const Duration(seconds: 15), (timer) async {
      try {
        final projectId = DefaultFirebaseOptions.windows.projectId;
        final apiKey = DefaultFirebaseOptions.windows.apiKey;
        final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/sync_queue?key=$apiKey');
        
        final res = await http.get(url);
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final docs = data['documents'] as List?;
          if (docs != null) {
            for (final doc in docs) {
              final fields = doc['fields'] as Map<String, dynamic>?;
              if (fields == null) continue;

              final isProcessed = fields['processed']?['booleanValue'] ?? true;
              if (!isProcessed) {
                final name = doc['name'] as String;
                final id = name.split('/').last;
                final item = {
                  'id': id,
                  'entity': fields['entity']?['stringValue'],
                  'action': fields['action']?['stringValue'],
                  'data': _convertFromFirestoreMap(fields['data']?['mapValue']?['fields'] ?? {}),
                };
                onNewItem(item);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Firebase [REST] Poll Error: $e');
      }
    });
  }

  /// Hub-side: Marks a queue item as processed and deletes it from Firebase.
  Future<void> markAsProcessed(String docId) async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        final projectId = DefaultFirebaseOptions.windows.projectId;
        final apiKey = DefaultFirebaseOptions.windows.apiKey;
        final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/sync_queue/$docId?key=$apiKey');
        await http.delete(url);
      } catch (e) {
        debugPrint('Firebase [REST] MarkAsProcessed Error: $e');
      }
      return;
    }

    if (!_isInitialized) return;
    // We delete to keep Firebase costs low as per plan
    await _db.collection('sync_queue').doc(docId).delete();
  }

  /// Hub-side: Broadcasts an update to all devices via Firestore.
  /// Used for "after sync, hub should also post updated data to all other devices"
  Future<void> broadcastUpdate(String entity, Map<String, dynamic> data) async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _broadcastUpdateREST(entity, data);
      return;
    }

    if (!_isInitialized) return;
    String docId = data['id']?.toString() ?? data['barcode']?.toString() ?? 'unknown';
    
    // Use natural keys for better cloud visibility and deduplication
    if (entity == 'sales' || entity == 'sale') {
      docId = data['invoiceNo']?.toString() ?? docId;
    } else if (entity == 'patients' || entity == 'patient') {
      docId = data['uhid']?.toString() ?? docId;
    } else if (entity == 'users' || entity == 'user') {
      docId = data['name']?.toString() ?? docId;
    }

    await _db.collection(entity).doc(docId).set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
      'syncedFrom': 'hub',
    });
  }

  Future<void> _broadcastUpdateREST(String entity, Map<String, dynamic> data) async {
    try {
      final projectId = DefaultFirebaseOptions.windows.projectId;
      final apiKey = DefaultFirebaseOptions.windows.apiKey;

      // Prioritize global unique keys over local ObjectBox IDs to prevent collisions between hubs
      String? rawId;
      if (entity.contains('medicine')) {
        rawId = data['barcode']?.toString();
        if (rawId == null || rawId.isEmpty) rawId = data['id']?.toString();
      } else if (entity.contains('sale')) {
        rawId = data['invoiceNo']?.toString();
        if (rawId == null || rawId.isEmpty) rawId = data['id']?.toString();
      } else if (entity.contains('patient')) {
        rawId = data['uhid']?.toString();
        if (rawId == null || rawId.isEmpty) rawId = data['id']?.toString();
      } else if (entity.contains('user') || entity.contains('doctor')) {
        rawId = data['name']?.toString();
      } else {
        rawId = data['id']?.toString();
      }

      String docId = rawId?.trim() ?? 'unknown';
      if (docId.isEmpty) docId = 'unknown_${DateTime.now().millisecondsSinceEpoch}';

      // Sanitize docId for REST (replace characters that break URLs)
      docId = docId.replaceAll('/', '_').replaceAll('\\', '_').replaceAll(' ', '_');

      final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$entity/$docId?key=$apiKey');
      
      final body = jsonEncode({
        'fields': {
          ..._convertToFirestoreMap(data),
          'updatedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
          'syncedFrom': {'stringValue': 'hub'},
        }
      });

      final token = await _getIdToken();
      final res = await http.patch(
        url, 
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
        body: body
      );
      if (res.statusCode != 200) {
        debugPrint('Firebase [REST] Broadcast FAIL ($entity): ${res.statusCode} - ${res.body}');
      }
    } catch (e) {
      debugPrint('Firebase [REST] Broadcast Error ($entity): $e');
    }
  }

  /// Hub-side: Deletes a document from Firebase REST.
  Future<void> deleteDocument(String entity, String docId) async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        final projectId = DefaultFirebaseOptions.windows.projectId;
        final apiKey = DefaultFirebaseOptions.windows.apiKey;
        // Sanitize docId
        final sanitizedId = docId.replaceAll('/', '_').replaceAll('\\', '_').replaceAll(' ', '_');
        final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$entity/$sanitizedId?key=$apiKey');
        
        final token = await _getIdToken();
        final res = await http.delete(
          url,
          headers: token != null ? {'Authorization': 'Bearer $token'} : {},
        );
        if (res.statusCode == 200 || res.statusCode == 204) {
          debugPrint('Firebase [REST]: Document $entity/$sanitizedId deleted successfully.');
        }
      } catch (e) {
        debugPrint('Firebase [REST]: Error deleting document: $e');
      }
      return;
    }

    if (!_isInitialized) return;
    try {
      await _db.collection(entity).doc(docId).delete();
    } catch (e) {
      debugPrint('Firebase deleteDocument error: $e');
    }
  }

  /// Pulls an entire collection from Firebase.
  /// Hub-side: Uses REST to see what needs to be pruned.
  /// Companion-side: Uses Native SDK.
  Future<List<Map<String, dynamic>>> fetchCollection(String entity) async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return await _fetchCollectionREST(entity);
    }

    if (!_isInitialized) {
      debugPrint('Firebase: fetchCollection aborted (not initialized)');
      return [];
    }
    try {
      debugPrint('Firebase: Fetching collection "$entity" (Cloud Mode)...');
      // Primary: Only items synced from Hub
      var snapshot = await _db.collection(entity).where('syncedFrom', isEqualTo: 'hub').get();
      
      // Fallback: If no hub-synced items found, try fetching entire collection
      if (snapshot.docs.isEmpty) {
        debugPrint('Firebase: No "hub-synced" items found in "$entity", trying full fetch...');
        snapshot = await _db.collection(entity).get();
      }

      debugPrint('Firebase: Found ${snapshot.docs.length} documents in "$entity".');
      return snapshot.docs.map((doc) => {
        ...doc.data(),
        'cloudId': doc.id, // Store doc.id separately to avoid overwriting Hub's local id
      }).toList();
    } catch (e) {
      debugPrint('Firebase fetchCollection failed for "$entity": $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCollectionREST(String entity) async {
    try {
      final projectId = DefaultFirebaseOptions.windows.projectId;
      final apiKey = DefaultFirebaseOptions.windows.apiKey;
      final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$entity?key=$apiKey');
      
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List docs = data['documents'] ?? [];
        return docs.map((doc) {
          final fields = doc['fields'] as Map<String, dynamic>? ?? {};
          final name = doc['name'] as String;
          final docId = name.split('/').last;
          return {
            ..._convertFromFirestoreMap(fields),
            'cloudId': docId,
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('Firebase [_fetchCollectionREST] Error: $e');
    }
    return [];
  }

  /// Companion-side: Listens for global updates from the Hub.
  void startGlobalUpdateListener(String entity, Function(Map<String, dynamic>) onUpdate) {
    if (!_isInitialized) return;
    _db.collection(entity)
        .where('syncedFrom', isEqualTo: 'hub')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        onUpdate({...doc.data(), 'id': doc.id});
      }
    });
  }

  /// Fetches the Hub status (online/offline, cloudflare URL) from Firestore.
  Future<Map<String, dynamic>?> getHubStatus() async {
    if (!_isInitialized) return null;
    try {
      final doc = await _db.collection('settings').doc('hub_status').get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 5));
      return doc.data();
    } catch (e) {
      debugPrint('Firebase getHubStatus failed: $e');
      return null;
    }
  }
}
