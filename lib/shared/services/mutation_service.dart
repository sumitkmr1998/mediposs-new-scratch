import 'dart:io';

import 'package:flutter/foundation.dart';

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
  /// - Hub: broadcast WS events so clients refresh
  /// - Client: enqueue for later push to hub
  void publish({
    required String entity,
    required String action,
    Map<String, dynamic>? data,
    List<String> hubEvents = const [],
    Map<String, dynamic>? hubPayload,
  }) {
    if (isHubDevice) {
      if (!LocalServerService.instance.isRunning) return;
      if (hubEvents.isEmpty) {
        LocalServerService.instance.broadcast({
          'event': 'sync_received',
          if (hubPayload != null) ...hubPayload,
        });
        return;
      }
      for (final event in hubEvents) {
        LocalServerService.instance.broadcast({
          'event': event,
          if (hubPayload != null) ...hubPayload,
        });
      }
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
