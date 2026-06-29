import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_user.dart';
import '../models/patient.dart';
import '../models/appointment.dart';
import '../models/prescription.dart';
import '../models/sale.dart';
import '../../objectbox.g.dart';
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

  bool get _isEnabled {
    try {
      return ObjectBoxService.instance.settings.firebaseEnabled;
    } catch (_) {
      return true;
    }
  }

  String? _idToken;
  DateTime? _tokenExpiry;

  String get _shopId {
    try {
      final settings = ObjectBoxService.instance.settings;
      if (settings.shopId.isNotEmpty) return settings.shopId;
      final fallback = settings.storeName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase();
      return fallback.isNotEmpty ? fallback : 'default_shop';
    } catch (_) {
      return 'default_shop';
    }
  }

  FirebaseSyncService._();

  static Future<void> init() async {
    if (_instance != null) return;
    _instance = FirebaseSyncService._();
    try {
      Firebase.app();
      _instance!._isInitialized = true;

      if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
        debugPrint('FirebaseSyncService: Triggering anonymous sign-in on mobile...');
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          await FirebaseAuth.instance.signInAnonymously();
          debugPrint('FirebaseSyncService: Anonymous sign-in successful.');
        } else {
          debugPrint('FirebaseSyncService: Already authenticated anonymously: ${user.uid}');
        }
      }
    } catch (e) {
      debugPrint('FirebaseSyncService: Firebase initialization or authentication failed: $e');
    }
  }

  // --- Hub Methods ---

  /// Updates the Hub's public Cloudflare URL and online status in Firebase.
  Future<void> updateHubStatus({
    required bool isOnline,
    String? cloudflareUrl,
    int? port,
  }) async {
    if (!_isEnabled) return;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _updateHubStatusREST(isOnline: isOnline, cloudflareUrl: cloudflareUrl, port: port);
      return;
    }

    if (!_isInitialized) return;
    try {
      await _db.collection('shops').doc(_shopId).collection('settings').doc('hub_status').set({
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
    if (!_isEnabled) return;
    try {
      final token = await _getIdToken();
      final projectId = DefaultFirebaseOptions.windows.projectId;
      final apiKey = DefaultFirebaseOptions.windows.apiKey;
      final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/shops/$_shopId/settings/hub_status?key=$apiKey');
      
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
    if (!_isEnabled) return false;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return await _pushDeltaREST(entity: entity, action: action, data: data);
    }

    if (!_isInitialized) return false;
    try {
      final settings = ObjectBoxService.instance.settings;
      await _db.collection('shops').doc(_shopId).collection('sync_queue').add({
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
    if (!_isEnabled) return false;
    try {
      final projectId = DefaultFirebaseOptions.windows.projectId;
      final apiKey = DefaultFirebaseOptions.windows.apiKey;
      final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/shops/$_shopId/sync_queue?key=$apiKey');
      
      final settings = ObjectBoxService.instance.settings;
      final body = jsonEncode({
        'fields': {
          'deviceId': {'stringValue': settings.deviceId ?? 'unknown'},
          'entity': {'stringValue': entity},
          'action': {'stringValue': action},
          'data': {'mapValue': {'fields': _convertToFirestoreMap(data)}},
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
    if (!_isEnabled) return;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _startQueueListenerREST(onNewItem);
      return;
    }

    if (!_isInitialized) return;
    _db.collection('shops').doc(_shopId).collection('sync_queue')
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
    if (!_isEnabled) return;
    Future<void> poll() async {
      try {
        final projectId = DefaultFirebaseOptions.windows.projectId;
        final apiKey = DefaultFirebaseOptions.windows.apiKey;
        final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/shops/$_shopId/sync_queue?key=$apiKey');
        
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
    }

    // Run poll immediately on startup
    poll();

    // Polling every 15 seconds for new deltas
    Timer.periodic(const Duration(seconds: 15), (timer) async {
      await poll();
    });
  }

  /// Hub-side: Marks a queue item as processed and deletes it from Firebase.
  Future<void> markAsProcessed(String docId) async {
    if (!_isEnabled) return;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        final projectId = DefaultFirebaseOptions.windows.projectId;
        final apiKey = DefaultFirebaseOptions.windows.apiKey;
        final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/shops/$_shopId/sync_queue/$docId?key=$apiKey');
        await http.delete(url);
      } catch (e) {
        debugPrint('Firebase [REST] MarkAsProcessed Error: $e');
      }
      return;
    }

    if (!_isInitialized) return;
    // We delete to keep Firebase costs low as per plan
    await _db.collection('shops').doc(_shopId).collection('sync_queue').doc(docId).delete();
  }

  /// Hub-side: Broadcasts an update to all devices via Firestore.
  /// Used for "after sync, hub should also post updated data to all other devices"
  Future<void> broadcastUpdate(String entity, Map<String, dynamic> data, {bool force = false}) async {
    if (!_isEnabled) return;
    
    // Check connection mode: Only sync/mirror database to Firebase if connectionMode is explicitly 'firebase' or if force=true
    final connectionMode = ObjectBoxService.instance.settings.connectionMode;
    if (connectionMode != 'firebase' && !force) {
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _broadcastUpdateREST(entity, data, force: force);
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

    await _db.collection('shops').doc(_shopId).collection(entity).doc(docId).set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
      'syncedFrom': 'hub',
    });
  }

  Future<void> _broadcastUpdateREST(String entity, Map<String, dynamic> data, {bool force = false}) async {
    if (!_isEnabled) return;
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

      final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/shops/$_shopId/$entity/$docId?key=$apiKey');
      
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
  Future<void> deleteDocument(String entity, String docId, {bool force = false}) async {
    if (!_isEnabled) return;
    
    // Only perform deletes if mirroring is enabled via connectionMode == 'firebase' or if force=true
    final connectionMode = ObjectBoxService.instance.settings.connectionMode;
    if (connectionMode != 'firebase' && !force) {
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        final projectId = DefaultFirebaseOptions.windows.projectId;
        final apiKey = DefaultFirebaseOptions.windows.apiKey;
        // Sanitize docId
        final sanitizedId = docId.replaceAll('/', '_').replaceAll('\\', '_').replaceAll(' ', '_');
        final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/shops/$_shopId/$entity/$sanitizedId?key=$apiKey');
        
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
      await _db.collection('shops').doc(_shopId).collection(entity).doc(docId).delete();
    } catch (e) {
      debugPrint('Firebase deleteDocument error: $e');
    }
  }

  /// Pulls an entire collection from Firebase.
  /// Hub-side: Uses REST to see what needs to be pruned.
  /// Companion-side: Uses Native SDK.
  Future<List<Map<String, dynamic>>> fetchCollection(String entity) async {
    if (!_isEnabled) return [];
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
      var snapshot = await _db.collection('shops').doc(_shopId).collection(entity).where('syncedFrom', isEqualTo: 'hub').get();
      
      // Fallback: If no hub-synced items found, try fetching entire collection
      if (snapshot.docs.isEmpty) {
        debugPrint('Firebase: No "hub-synced" items found in "$entity", trying full fetch...');
        snapshot = await _db.collection('shops').doc(_shopId).collection(entity).get();
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
    if (!_isEnabled) return [];
    try {
      final projectId = DefaultFirebaseOptions.windows.projectId;
      final apiKey = DefaultFirebaseOptions.windows.apiKey;
      final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/shops/$_shopId/$entity?key=$apiKey');
      
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
    if (!_isEnabled) return;
    if (!_isInitialized) return;
    _db.collection('shops').doc(_shopId).collection(entity)
        .where('syncedFrom', isEqualTo: 'hub')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        onUpdate({...doc.data(), 'id': doc.id});
      }
    });
  }

  Future<Map<String, dynamic>?> _getHubStatusREST() async {
    try {
      final projectId = DefaultFirebaseOptions.windows.projectId;
      final apiKey = DefaultFirebaseOptions.windows.apiKey;
      final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/shops/$_shopId/settings/hub_status?key=$apiKey');
      
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final fields = data['fields'] as Map<String, dynamic>? ?? {};
        return _convertFromFirestoreMap(fields);
      }
    } catch (e) {
      debugPrint('Firebase [_getHubStatusREST] Error: $e');
    }
    return null;
  }

  Future<List<String>> _fetchShopIdsREST() async {
    try {
      final projectId = DefaultFirebaseOptions.windows.projectId;
      final apiKey = DefaultFirebaseOptions.windows.apiKey;
      final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/shops?key=$apiKey');
      
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List docs = data['documents'] ?? [];
        return docs.map((doc) {
          final name = doc['name'] as String;
          return name.split('/').last;
        }).toList();
      }
    } catch (e) {
      debugPrint('Firebase [_fetchShopIdsREST] Error: $e');
    }
    return [];
  }

  /// Fetches the Hub status (online/offline, cloudflare URL) from Firestore.
  Future<Map<String, dynamic>?> getHubStatus() async {
    if (!_isEnabled) return null;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return await _getHubStatusREST();
    }
    if (!_isInitialized) return null;
    try {
      final targetShopId = _shopId;
      if (targetShopId != 'default_shop') {
        final doc = await _db.collection('shops').doc(targetShopId).collection('settings').doc('hub_status').get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 5));
        return doc.data();
      }

      // Auto-detect active shop partition if currently default_shop (unpaired client)
      final shopIds = await fetchShopIds();
      for (final id in shopIds) {
        try {
          final doc = await _db.collection('shops').doc(id).collection('settings').doc('hub_status').get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 2));
          if (doc.exists) {
            final data = doc.data();
            if (data != null && data['cloudflareUrl'] != null && data['cloudflareUrl'].toString().isNotEmpty) {
              // Found a shop with an active tunnel URL! Save it in settings so subsequent calls use it
              final settings = ObjectBoxService.instance.settings;
              settings.shopId = id;
              ObjectBoxService.instance.settingsBox.put(settings);
              debugPrint('Firebase getHubStatus: Auto-detected active shop partition: $id');
              return data;
            }
          }
        } catch (_) {}
      }

      // Fallback to default
      final doc = await _db.collection('shops').doc('default_shop').collection('settings').doc('hub_status').get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 3));
      return doc.data();
    } catch (e) {
      debugPrint('Firebase getHubStatus failed: $e');
      return null;
    }
  }

  /// Fetches the list of all available shop IDs in Firestore.
  Future<List<String>> fetchShopIds() async {
    if (!_isEnabled) return [];
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return await _fetchShopIdsREST();
    }
    if (!_isInitialized) return [];
    try {
      final snapshot = await _db.collection('shops').get();
      return snapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      debugPrint('Firebase fetchShopIds failed: $e');
      return [];
    }
  }

  /// Uploads only today's records (sales, appointments, prescriptions, patients) to Firestore.
  /// Used for daily summary cloud uploads.
  Future<void> uploadTodaysDataToCloud() async {
    if (!_isEnabled) return;
    debugPrint('FirebaseSyncService: Starting daily summary cloud upload...');
    
    try {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final startMs = startOfToday.millisecondsSinceEpoch;
      
      final db = ObjectBoxService.instance;
      
      // 1. Fetch today's patients
      final patients = db.patientBox
          .query(Patient_.createdAt.greaterThan(startMs - 1)
              .or(Patient_.updatedAt.greaterThan(startMs - 1)))
          .build()
          .find();
          
      // 2. Fetch today's appointments
      final appointments = db.appointmentBox
          .query(Appointment_.scheduledAt.greaterThan(startMs - 1))
          .build()
          .find();
          
      // 3. Fetch today's prescriptions
      final prescriptions = db.prescriptionBox
          .query(Prescription_.createdAt.greaterThan(startMs - 1))
          .build()
          .find();
          
      // 4. Fetch today's sales
      final sales = db.saleBox
          .query(Sale_.createdAt.greaterThan(startMs - 1))
          .build()
          .find();

      debugPrint('FirebaseSyncService: Found ${patients.length} patients, ${appointments.length} appointments, ${prescriptions.length} prescriptions, ${sales.length} sales created/updated today.');

      // Upload patients
      for (final p in patients) {
        await broadcastUpdate('patients', p.toJson(), force: true);
      }
      // Upload appointments
      for (final a in appointments) {
        await broadcastUpdate('appointments', a.toJson(), force: true);
      }
      // Upload prescriptions
      for (final pr in prescriptions) {
        await broadcastUpdate('prescriptions', pr.toJson(), force: true);
      }
      // Upload sales
      for (final s in sales) {
        await broadcastUpdate('sales', s.toJson(), force: true);
      }

      debugPrint('FirebaseSyncService: Daily summary cloud upload completed successfully.');
    } catch (e) {
      debugPrint('FirebaseSyncService: Daily summary cloud upload failed: $e');
    }
  }

  /// Push a real-time notification document to Firestore.
  Future<bool> pushNotification({
    required String event,
    required Map<String, dynamic> data,
  }) async {
    if (!_isEnabled) return false;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return await _pushNotificationREST(event: event, data: data);
    }

    if (!_isInitialized) return false;
    try {
      final settings = ObjectBoxService.instance.settings;
      await _db.collection('shops').doc(_shopId).collection('notifications').add({
        'deviceId': settings.deviceId ?? 'unknown',
        'event': event,
        'data': data,
        'timestamp': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('Firebase pushNotification error: $e');
      return false;
    }
  }

  Future<bool> _pushNotificationREST({
    required String event,
    required Map<String, dynamic> data,
  }) async {
    if (!_isEnabled) return false;
    try {
      final projectId = DefaultFirebaseOptions.windows.projectId;
      final apiKey = DefaultFirebaseOptions.windows.apiKey;
      final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/shops/$_shopId/notifications?key=$apiKey');
      
      final settings = ObjectBoxService.instance.settings;
      final body = jsonEncode({
        'fields': {
          'deviceId': {'stringValue': settings.deviceId ?? 'unknown'},
          'event': {'stringValue': event},
          'data': {'mapValue': {'fields': _convertToFirestoreMap(data)}},
          'timestamp': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        }
      });

      final token = await _getIdToken();
      final res = await http.post(
        url, 
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
        body: body
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        debugPrint('Firebase [REST]: Notification pushed successfully.');
        return true;
      } else {
        debugPrint('Firebase [REST]: Notification push failed with ${res.statusCode}: ${res.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Firebase [REST]: Error pushing notification: $e');
      return false;
    }
  }
}
