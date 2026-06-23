import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/prescription_template.dart';
import '../models/prescription.dart';
import '../services/objectbox_service.dart';
import '../services/local_server_service.dart';
import '../services/sync_service.dart';
import '../services/sync_queue_service.dart';

class TemplateProvider extends ChangeNotifier {
  List<PrescriptionTemplate> _templates = [];

  List<PrescriptionTemplate> get templates => _templates;

  void load() {
    _templates = ObjectBoxService.instance.templateBox.getAll()
      ..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  PrescriptionTemplate save({
    int id = 0,
    required String name,
    String diagnosis = '',
    String complaints = '',
    String notes = '',
    required List<PrescriptionItem> items,
    List<String> labTests = const [],
    int doctorId = 0,
    SyncService? syncService,
  }) {
    final t = id == 0
        ? PrescriptionTemplate(name: name)
        : (ObjectBoxService.instance.templateBox.get(id) ??
            PrescriptionTemplate(name: name));

    t.name = name;
    t.diagnosis = diagnosis;
    t.complaints = complaints;
    t.notes = notes;
    t.itemsJson = jsonEncode(items.map((i) => i.toJson()).toList());
    t.labTestsJson = jsonEncode(labTests);
    t.doctorId = doctorId;

    ObjectBoxService.instance.templateBox.put(t);
    load();

    final isClient = ObjectBoxService.instance.settings.isWindowsClient;
    final isHub = !ObjectBoxService.instance.settings.isWindowsClient;
    if (isHub) {
      if (LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      }
    } else if (isClient) {
      SyncQueueService.instance.addToQueue(
        entity: 'template',
        action: 'create',
        data: t.toJson(),
      );
    }

    return t;
  }

  void delete(int id, {SyncService? syncService}) {
    final t = ObjectBoxService.instance.templateBox.get(id);
    if (t != null) {
      final name = t.name;
      ObjectBoxService.instance.templateBox.remove(id);
      load();

      final isClient = ObjectBoxService.instance.settings.isWindowsClient;
      final isHub = !ObjectBoxService.instance.settings.isWindowsClient;
      if (isHub && LocalServerService.instance.isRunning) {
        LocalServerService.instance.broadcast({'event': 'sync_received'});
      } else if (isClient) {
        SyncQueueService.instance.addToQueue(
          entity: 'template',
          action: 'delete',
          data: {'name': name},
        );
      }
    }
  }

  List<PrescriptionItem> getItems(PrescriptionTemplate t) {
    try {
      final List<dynamic> decoded = jsonDecode(t.itemsJson);
      return decoded.map((j) => PrescriptionItem.fromJson(j)).toList();
    } catch (_) {
      return [];
    }
  }

  List<String> getLabTests(PrescriptionTemplate t) {
    try {
      final List<dynamic> decoded = jsonDecode(t.labTestsJson);
      return decoded.cast<String>();
    } catch (_) {
      return [];
    }
  }
}
