import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/audit_log.dart';
import '../models/app_user.dart';
import 'objectbox_service.dart';
import 'sync_queue_service.dart';
import '../../objectbox.g.dart';

class AuditService {
  static final AuditService instance = AuditService._();
  AuditService._();

  Future<void> pruneOldLogs(int retentionDays) async {
    if (retentionDays <= 0) return;
    try {
      final db = ObjectBoxService.instance;
      final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
      final query = db.store.box<AuditLog>().query(
        AuditLog_.timestamp.lessThan(cutoff.millisecondsSinceEpoch)
      ).build();
      final count = query.remove();
      query.close();
      if (count > 0) {
        debugPrint('Pruned $count old audit logs (older than $retentionDays days).');
      }
    } catch (e) {
      debugPrint('Error pruning audit logs: $e');
    }
  }

  Future<void> log({
    required String action,
    required String entityType,
    required String entityId,
    required String description,
    Map<String, dynamic>? details,
    required AppUser? actor,
  }) async {
    try {
      if (!ObjectBoxService.isInitialized) {
        debugPrint('AuditService: ObjectBoxService not initialized yet. Skipping log.');
        return;
      }
      final db = ObjectBoxService.instance;
      final settings = db.settings;
      
      // Auto-prune old logs based on retention policy
      if (settings.auditRetentionDays > 0) {
        await pruneOldLogs(settings.auditRetentionDays);
      }

      final logEntry = AuditLog(
        action: action,
        entityType: entityType,
        entityId: entityId,
        description: description,
        detailsJson: jsonEncode(details ?? {}),
        performedBy: actor != null ? '${actor.name} (${actor.role})' : 'System',
        timestamp: DateTime.now(),
        deviceId: settings.deviceId ?? 'Unknown-Device',
      );
      
      db.store.box<AuditLog>().put(logEntry);
      debugPrint('AuditLog saved: $description by ${logEntry.performedBy}');

      final isClient = Platform.isAndroid || (Platform.isWindows && settings.isWindowsClient);
      if (isClient) {
        SyncQueueService.instance.addToQueue(
          entity: 'audit_log',
          action: 'create',
          data: logEntry.toJson(),
        );
      }
    } catch (e) {
      debugPrint('Error writing audit log: $e');
    }
  }
}
