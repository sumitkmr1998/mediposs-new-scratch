import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'firebase_sync_service.dart';
import 'local_server_service.dart';
import 'objectbox_service.dart';
import 'sync_queue_service.dart';

/// Single path for "local write already done → notify hub or queue for client".
///
/// Replaces repeated isHub/isClient if-ladders across providers.
class MutationService {
  static final MutationService instance = MutationService._();
  MutationService._();

  bool get isWindowsClient =>
      Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient;

  bool get isClientDevice =>
      Platform.isAndroid ||
      Platform.isIOS ||
      isWindowsClient;

  bool get isHubDevice =>
      Platform.isWindows && !ObjectBoxService.instance.settings.isWindowsClient;

  /// After a successful local mutation:
  /// - Hub: broadcast WS events so clients refresh & mirror to Firebase in real time
  /// - Client: enqueue for later push to hub
  void publish({
    required String entity,
    required String action,
    Map<String, dynamic>? data,
    List<String> hubEvents = const [],
    Map<String, dynamic>? hubPayload,
  }) {
    if (isHubDevice) {
      if (LocalServerService.instance.isRunning) {
        if (hubEvents.isEmpty) {
          LocalServerService.instance.broadcast({
            'event': 'sync_received',
            if (hubPayload != null) ...hubPayload,
          });
        } else {
          for (final event in hubEvents) {
            LocalServerService.instance.broadcast({
              'event': event,
              if (hubPayload != null) ...hubPayload,
            });
          }
        }
      }

      // Real-time Cloud Mirroring on Hub
      _mirrorToCloud(entity: entity, action: action, data: data);
      return;
    }

    if (isClientDevice) {
      if (data == null) {
        debugPrint(
            'MutationService: client publish for $entity/$action missing data — skipped queue');
        return;
      }
      SyncQueueService.instance.addToQueue(
        entity: entity,
        action: action,
        data: data,
      );
    }
  }

  void _mirrorToCloud({
    required String entity,
    required String action,
    Map<String, dynamic>? data,
  }) {
    final settings = ObjectBoxService.instance.settings;
    if (!settings.firebaseEnabled) return;
    if (settings.connectionMode == 'summary') return;

    if (action == 'create' || action == 'update') {
      if (data != null) {
        unawaited(FirebaseSyncService.instance
            .broadcastUpdate(entity, data)
            .catchError((e) {
          debugPrint(
              'MutationService: real-time cloud broadcast failed for $entity: $e');
        }));
      }
    } else if (action == 'delete') {
      final docId = _resolveDocId(entity, data);
      if (docId != null && docId.isNotEmpty) {
        unawaited(FirebaseSyncService.instance
            .deleteDocument(entity, docId)
            .catchError((e) {
          debugPrint(
              'MutationService: real-time cloud delete failed for $entity/$docId: $e');
        }));
      }
    }
  }

  String? _resolveDocId(String entity, Map<String, dynamic>? data) {
    if (data == null) return null;
    if (entity.contains('medicine')) {
      final b = data['barcode']?.toString();
      if (b != null && b.isNotEmpty) return b;
      return data['id']?.toString();
    }
    if (entity.contains('sale')) {
      final inv = data['invoiceNo']?.toString();
      if (inv != null && inv.isNotEmpty) return inv;
      return data['id']?.toString();
    }
    if (entity.contains('patient')) {
      final uhid = data['uhid']?.toString();
      if (uhid != null && uhid.isNotEmpty) return uhid;
      return data['id']?.toString();
    }
    if (entity.contains('user') ||
        entity.contains('doctor') ||
        entity.contains('procedure') ||
        entity.contains('template')) {
      return data['name']?.toString() ?? data['id']?.toString();
    }
    return data['id']?.toString();
  }

  /// Convenience for entity create/update that clients push as full JSON.
  void publishEntity({
    required String entity,
    required String action,
    required Map<String, dynamic> data,
    List<String>? hubEvents,
  }) {
    publish(
      entity: entity,
      action: action,
      data: data,
      hubEvents: hubEvents ?? _defaultEvents(entity, action),
    );
  }

  @visibleForTesting
  List<String> defaultEventsFor(String entity, String action) =>
      _defaultEvents(entity, action);

  List<String> _defaultEvents(String entity, String action) {
    switch (entity) {
      case 'medicine':
        return ['medicines_updated'];
      case 'sale':
        return action == 'delete'
            ? ['sale_deleted', 'sales_updated']
            : ['sales_updated'];
      case 'patient':
        return action == 'delete'
            ? ['patient_deleted']
            : ['patients_updated', 'new_patient'];
      case 'appointment':
        return ['appointments_updated'];
      case 'prescription':
        return ['prescriptions_updated'];
      case 'settings':
        return ['settings_updated'];
      case 'user':
        return ['users_updated'];
      default:
        return ['sync_received'];
    }
  }
}
