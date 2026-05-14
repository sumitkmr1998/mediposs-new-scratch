import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/procedure.dart';
import '../services/objectbox_service.dart';
import '../services/sync_service.dart';
import '../../objectbox.g.dart';

class ProcedureProvider with ChangeNotifier {
  List<Procedure> _procedures = [];
  List<ProcedureRecord> _records = [];

  List<Procedure> get procedures => _procedures;
  List<ProcedureRecord> get records => _records;

  ProcedureProvider() {
    loadProcedures();
    loadRecords();
    _seedDefaults();
  }

  void loadProcedures() {
    final box = ObjectBoxService.instance.procedureBox;
    _procedures = box.getAll();
    notifyListeners();
  }

  void loadRecords() {
    final box = ObjectBoxService.instance.procedureRecordBox;
    final query = box.query().order(ProcedureRecord_.date, flags: Order.descending).build();
    _records = query.find();
    query.close();
    notifyListeners();
  }

  void _seedDefaults() {
    final box = ObjectBoxService.instance.procedureBox;
    if (box.isEmpty()) {
      final defaults = [
        Procedure(name: 'Pico Laser', category: 'Laser', basePrice: 5000, description: 'Advanced laser for pigmentation and tattoo removal'),
        Procedure(name: 'LHR (Laser Hair Removal)', category: 'Laser', basePrice: 3000, description: 'Permanent hair reduction'),
        Procedure(name: 'Mole Removal', category: 'Surgical', basePrice: 1500, description: 'Radiofrequency or surgical excision of moles'),
        Procedure(name: 'Carbon Toning', category: 'Laser', basePrice: 4000, description: 'Hollywood Peel for skin rejuvenation'),
        Procedure(name: 'Chemical Peel', category: 'Skin Care', basePrice: 2000, description: 'Exfoliation for acne and glow'),
        Procedure(name: 'Tattoo Removal', category: 'Laser', basePrice: 3500, description: 'Multi-session laser tattoo clearance'),
        Procedure(name: 'Microneedling', category: 'Skin Care', basePrice: 4500, description: 'Collagen Induction Therapy for scars'),
      ];
      box.putMany(defaults);
      loadProcedures();
    }
  }

  Future<void> saveProcedure(Procedure p, {SyncService? syncService}) async {
    ObjectBoxService.instance.procedureBox.put(p);
    loadProcedures();
    if (syncService != null) {
      await syncService.syncEntity('Procedure', p.toJson());
    }
  }

  Future<void> deleteProcedure(int id, {SyncService? syncService}) async {
    ObjectBoxService.instance.procedureBox.remove(id);
    loadProcedures();
    // Logic for sync delete could be added here
  }

  Future<void> saveRecord(ProcedureRecord record, {SyncService? syncService}) async {
    ObjectBoxService.instance.procedureRecordBox.put(record);
    loadRecords();
    if (syncService != null) {
      await syncService.syncEntity('ProcedureRecord', record.toJson());
    }
  }

  List<ProcedureRecord> getRecordsForPatient(int patientId) {
    return _records.where((r) => r.patientId == patientId).toList();
  }
}
