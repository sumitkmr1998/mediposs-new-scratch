import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:excel/excel.dart' as excel_pkg;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';
import '../models/medicine.dart';
import '../models/stock_transfer.dart';
import '../utils/analytics_helper.dart';
import '../../objectbox.g.dart';
import 'audit_service.dart';
import 'objectbox_service.dart';

class ClinicReconciliationBaseline {
  final int id;
  final DateTime timestamp;
  final String performedBy;
  final Map<int, int> clinicStocks;
  final Map<int, int> storeStocks;
  final Map<int, int> totalStocks;
  final int medicineCount;

  ClinicReconciliationBaseline({
    this.id = 0,
    required this.timestamp,
    required this.performedBy,
    required this.clinicStocks,
    Map<int, int>? storeStocks,
    Map<int, int>? totalStocks,
    int? medicineCount,
  })  : storeStocks = storeStocks ?? {},
        totalStocks = totalStocks ?? clinicStocks,
        medicineCount = medicineCount ?? clinicStocks.length;

  Map<int, int> get stocks => clinicStocks;
}

class ClinicReconciliationService extends ChangeNotifier {
  static final ClinicReconciliationService instance = ClinicReconciliationService._();
  ClinicReconciliationService._();

  static const _prefBaselineTimeKey = 'clinic_reconcile_baseline_time';
  static const _prefBaselineUserKey = 'clinic_reconcile_baseline_user';
  static const _prefBaselineClinicKey = 'clinic_reconcile_baseline_clinic';
  static const _prefBaselineStoreKey = 'clinic_reconcile_baseline_store';
  static const _prefBaselineTotalKey = 'clinic_reconcile_baseline_total';
  static const _prefBaselineStocksKey = 'clinic_reconcile_baseline_stocks';

  ClinicReconciliationBaseline? _activeBaseline;
  List<ClinicReconciliationBaseline> _baselineHistory = [];
  bool _initialized = false;

  bool get isInitialized => _initialized;
  bool get hasActiveBaseline => _activeBaseline != null;
  ClinicReconciliationBaseline? get activeBaseline => _activeBaseline;
  List<ClinicReconciliationBaseline> get baselineHistory => _baselineHistory;
  DateTime? get baselineDate => _activeBaseline?.timestamp;
  String? get performedBy => _activeBaseline?.performedBy;

  /// Next baseline in timeline (if reviewing past historical snapshot)
  ClinicReconciliationBaseline? get nextBaseline {
    if (_activeBaseline == null || _baselineHistory.isEmpty) return null;
    final idx = _baselineHistory.indexWhere((b) => b.id == _activeBaseline!.id || b.timestamp == _activeBaseline!.timestamp);
    if (idx > 0) {
      // History is sorted newest first, so idx - 1 is the next newer baseline
      return _baselineHistory[idx - 1];
    }
    return null;
  }

  /// Ending timestamp of the active cycle (null if it's the latest active cycle)
  DateTime? get currentBaselineEndDate => nextBaseline?.timestamp;

  /// Whether currently viewing the latest (active) baseline
  bool get isLatestBaseline {
    if (_activeBaseline == null || _baselineHistory.isEmpty) return true;
    return _activeBaseline!.id == _baselineHistory.first.id;
  }

  void selectLatestBaseline() {
    if (_baselineHistory.isNotEmpty) {
      _activeBaseline = _baselineHistory.first;
      notifyListeners();
    }
  }

  void selectBaseline(ClinicReconciliationBaseline baseline) {
    _activeBaseline = baseline;
    notifyListeners();
  }

  int getBaselineClinicStock(int medicineId) {
    if (_activeBaseline == null) return 0;
    return _activeBaseline!.clinicStocks[medicineId] ?? 0;
  }

  int getBaselineStoreStock(int medicineId) {
    if (_activeBaseline == null) return 0;
    return _activeBaseline!.storeStocks[medicineId] ?? 0;
  }

  int getBaselineTotalStock(int medicineId) {
    if (_activeBaseline == null) return 0;
    return _activeBaseline!.totalStocks[medicineId] ?? 
           ((_activeBaseline!.clinicStocks[medicineId] ?? 0) + (_activeBaseline!.storeStocks[medicineId] ?? 0));
  }

  int getBaselineStock(int medicineId) => getBaselineClinicStock(medicineId);

  Future<void> init() async {
    if (_initialized) return;
    await reloadBaseline();
    _initialized = true;
  }

  Future<void> reloadBaseline() async {
    try {
      _baselineHistory = [];

      // 1. Try to read from AuditLogs in ObjectBox
      if (ObjectBoxService.isInitialized) {
        final box = ObjectBoxService.instance.auditLogBox;
        final query = box
            .query(AuditLog_.entityType.equals('ClinicReconciliation'))
            .order(AuditLog_.timestamp, flags: Order.descending)
            .build();
        final logs = query.find();
        query.close();

        for (final log in logs) {
          if (log.action == 'RESET_BASELINE') {
            final clinic = <int, int>{};
            final store = <int, int>{};
            final total = <int, int>{};
            int medCount = 0;

            try {
              final json = jsonDecode(log.detailsJson);
              if (json is Map) {
                medCount = int.tryParse(json['medicineCount']?.toString() ?? '') ?? 0;
                void parseMap(dynamic source, Map<int, int> target) {
                  if (source is Map) {
                    source.forEach((k, v) {
                      final id = int.tryParse(k.toString());
                      final stock = int.tryParse(v.toString()) ?? 0;
                      if (id != null) target[id] = stock;
                    });
                  }
                }

                parseMap(json['clinicStocks'] ?? json['stocks'], clinic);
                parseMap(json['storeStocks'], store);
                parseMap(json['totalStocks'], total);

                if (total.isEmpty) {
                  for (final k in clinic.keys) {
                    total[k] = (clinic[k] ?? 0) + (store[k] ?? 0);
                  }
                }
              }
            } catch (e) {
              debugPrint('Error parsing baseline stocks from AuditLog: $e');
            }

            _baselineHistory.add(ClinicReconciliationBaseline(
              id: log.id,
              timestamp: log.timestamp,
              performedBy: log.performedBy,
              clinicStocks: clinic,
              storeStocks: store,
              totalStocks: total,
              medicineCount: medCount > 0 ? medCount : (total.isNotEmpty ? total.length : clinic.length),
            ));
          }
        }

        final latest = logs.firstOrNull;
        if (latest != null && latest.action == 'CLEAR_BASELINE') {
          // If the most recent user action was explicitly CLEAR_BASELINE, active baseline is cleared
          _activeBaseline = null;
          notifyListeners();
          return;
        }

        if (_baselineHistory.isNotEmpty) {
          // If activeBaseline was pointing to a specific baseline in history, preserve or point to latest
          final prevActiveId = _activeBaseline?.id;
          final match = _baselineHistory.where((b) => b.id == prevActiveId).firstOrNull;
          _activeBaseline = match ?? _baselineHistory.first;
          notifyListeners();
          return;
        }
      }

      // 2. Fallback to SharedPreferences if AuditLog not found
      final prefs = await SharedPreferences.getInstance();
      final timeStr = prefs.getString(_prefBaselineTimeKey);
      if (timeStr != null) {
        final time = DateTime.tryParse(timeStr);
        final user = prefs.getString(_prefBaselineUserKey) ?? 'Staff';

        final clinic = <int, int>{};
        final store = <int, int>{};
        final total = <int, int>{};

        void parseJsonMap(String? raw, Map<int, int> target) {
          if (raw == null) return;
          try {
            final json = jsonDecode(raw);
            if (json is Map) {
              json.forEach((k, v) {
                final id = int.tryParse(k.toString());
                final stock = int.tryParse(v.toString()) ?? 0;
                if (id != null) target[id] = stock;
              });
            }
          } catch (_) {}
        }

        parseJsonMap(prefs.getString(_prefBaselineClinicKey) ?? prefs.getString(_prefBaselineStocksKey), clinic);
        parseJsonMap(prefs.getString(_prefBaselineStoreKey), store);
        parseJsonMap(prefs.getString(_prefBaselineTotalKey), total);

        if (total.isEmpty) {
          for (final k in clinic.keys) {
            total[k] = (clinic[k] ?? 0) + (store[k] ?? 0);
          }
        }

        if (time != null) {
          final fallbackBaseline = ClinicReconciliationBaseline(
            id: 0,
            timestamp: time,
            performedBy: user,
            clinicStocks: clinic,
            storeStocks: store,
            totalStocks: total,
            medicineCount: total.isNotEmpty ? total.length : clinic.length,
          );
          _activeBaseline = fallbackBaseline;
          _baselineHistory = [fallbackBaseline];
          notifyListeners();
          return;
        }
      }

      _activeBaseline = null;
      notifyListeners();
    } catch (e) {
      debugPrint('ClinicReconciliationService.reloadBaseline error: $e');
    }
  }

  Future<void> setBaseline({
    required List<Medicine> medicines,
    AppUser? actor,
  }) async {
    final now = DateTime.now();
    final actorName = actor != null ? '${actor.name} (${actor.role})' : 'Staff';

    final clinicStocks = <int, int>{};
    final storeStocks = <int, int>{};
    final totalStocks = <int, int>{};

    final clinicJson = <String, int>{};
    final storeJson = <String, int>{};
    final totalJson = <String, int>{};

    for (final m in medicines) {
      clinicStocks[m.id] = m.mainStock;
      storeStocks[m.id] = m.storeStock;
      final total = m.mainStock + m.storeStock;
      totalStocks[m.id] = total;

      clinicJson[m.id.toString()] = m.mainStock;
      storeJson[m.id.toString()] = m.storeStock;
      totalJson[m.id.toString()] = total;
    }

    _activeBaseline = ClinicReconciliationBaseline(
      timestamp: now,
      performedBy: actorName,
      clinicStocks: clinicStocks,
      storeStocks: storeStocks,
      totalStocks: totalStocks,
    );

    // Save to SharedPreferences for quick local fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefBaselineTimeKey, now.toIso8601String());
      await prefs.setString(_prefBaselineUserKey, actorName);
      await prefs.setString(_prefBaselineClinicKey, jsonEncode(clinicJson));
      await prefs.setString(_prefBaselineStoreKey, jsonEncode(storeJson));
      await prefs.setString(_prefBaselineTotalKey, jsonEncode(totalJson));
      await prefs.setString(_prefBaselineStocksKey, jsonEncode(clinicJson)); // backward compat
    } catch (e) {
      debugPrint('Error saving baseline to SharedPreferences: $e');
    }

    // Save to AuditLog (synced across devices)
    try {
      await AuditService.instance.log(
        action: 'RESET_BASELINE',
        entityType: 'ClinicReconciliation',
        entityId: 'clinic_stock',
        description: 'Reset clinic stock reconciliation audit baseline ($actorName snapshotted ${medicines.length} medicines across clinic & store)',
        details: {
          'clinicStocks': clinicJson,
          'storeStocks': storeJson,
          'totalStocks': totalJson,
          'stocks': clinicJson, // backward compat
          'medicineCount': medicines.length,
          'timestamp': now.toIso8601String(),
        },
        actor: actor,
      );
      await reloadBaseline();
    } catch (e) {
      debugPrint('Error creating AuditLog for baseline: $e');
      notifyListeners();
    }
  }

  Future<void> clearBaseline({AppUser? actor}) async {
    final actorName = actor != null ? '${actor.name} (${actor.role})' : 'Staff';
    _activeBaseline = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefBaselineTimeKey);
      await prefs.remove(_prefBaselineUserKey);
      await prefs.remove(_prefBaselineClinicKey);
      await prefs.remove(_prefBaselineStoreKey);
      await prefs.remove(_prefBaselineTotalKey);
      await prefs.remove(_prefBaselineStocksKey);
    } catch (e) {
      debugPrint('Error clearing baseline in SharedPreferences: $e');
    }

    try {
      await AuditService.instance.log(
        action: 'CLEAR_BASELINE',
        entityType: 'ClinicReconciliation',
        entityId: 'clinic_stock',
        description: 'Reverted clinic stock reconciliation to all-time cumulative history ($actorName)',
        details: {
          'clearedAt': DateTime.now().toIso8601String(),
        },
        actor: actor,
      );
    } catch (e) {
      debugPrint('Error creating AuditLog for clear baseline: $e');
    }

    notifyListeners();
  }

  /// Exports a comparative audit Excel workbook spanning all audit snapshots.
  /// Sheet 1: Timeline summary of all audits.
  /// Sheet 2: Side-by-side comparison of ending physical stock across cycles.
  /// Sheet 3: Side-by-side comparison of discrepancies (surplus/shortage) across cycles to detect recurring irregularities.
  Future<File?> exportAuditHistoryComparisonToExcel({
    required List<Medicine> medicines,
    required List<StockTransfer> allTransfers,
    required List<dynamic> allSales,
  }) async {
    if (_baselineHistory.isEmpty) return null;

    final excel = excel_pkg.Excel.createExcel();
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    final shortDateFormat = DateFormat('dd/MM/yy');

    // -------------------------------------------------------------
    // SHEET 1: AUDIT SNAPSHOTS TIMELINE
    // -------------------------------------------------------------
    const sheet1Name = 'Audit Timeline';
    final sheet1 = excel[sheet1Name];
    excel.delete('Sheet1');

    sheet1.appendRow([excel_pkg.TextCellValue('MEDIPOSS AUDIT SNAPSHOTS TIMELINE & OVERVIEW')]);
    sheet1.appendRow([excel_pkg.TextCellValue('Exported At: ${dateFormat.format(DateTime.now())}')]);
    sheet1.appendRow([excel_pkg.TextCellValue('Total Snapshots Recorded: ${_baselineHistory.length}')]);
    sheet1.appendRow([]);

    sheet1.appendRow([
      excel_pkg.TextCellValue('Snapshot #'),
      excel_pkg.TextCellValue('Date & Time'),
      excel_pkg.TextCellValue('Audited By'),
      excel_pkg.TextCellValue('Medicines Counted'),
      excel_pkg.TextCellValue('Total Physical Units (Clinic + Store)'),
      excel_pkg.TextCellValue('Clinic Shelf Units'),
      excel_pkg.TextCellValue('Store Shelf Units'),
    ]);

    // Reverse so chronologically earliest is first
    final chronologicalHistory = _baselineHistory.reversed.toList();
    for (int i = 0; i < chronologicalHistory.length; i++) {
      final b = chronologicalHistory[i];
      int totalClinic = 0;
      int totalStore = 0;
      b.clinicStocks.forEach((_, v) => totalClinic += v);
      b.storeStocks.forEach((_, v) => totalStore += v);
      int totalCombined = totalClinic + totalStore;

      sheet1.appendRow([
        excel_pkg.TextCellValue('Audit ${i + 1}'),
        excel_pkg.TextCellValue(dateFormat.format(b.timestamp)),
        excel_pkg.TextCellValue(b.performedBy),
        excel_pkg.IntCellValue(b.medicineCount),
        excel_pkg.IntCellValue(totalCombined),
        excel_pkg.IntCellValue(totalClinic),
        excel_pkg.IntCellValue(totalStore),
      ]);
    }

    // -------------------------------------------------------------
    // SHEET 2: SIDE-BY-SIDE STOCK HISTORY ACROSS AUDITS
    // -------------------------------------------------------------
    const sheet2Name = 'Stock History Comparison';
    final sheet2 = excel[sheet2Name];

    sheet2.appendRow([excel_pkg.TextCellValue('PHYSICAL INVENTORY COUNTS ACROSS AUDIT CYCLES')]);
    sheet2.appendRow([excel_pkg.TextCellValue('Values show total on-hand quantity (Clinic + Store) verified at each audit date.')]);
    sheet2.appendRow([]);

    final sheet2Headers = <excel_pkg.CellValue>[
      excel_pkg.TextCellValue('Medicine Name'),
    ];
    for (int i = 0; i < chronologicalHistory.length; i++) {
      final b = chronologicalHistory[i];
      sheet2Headers.add(excel_pkg.TextCellValue('${shortDateFormat.format(b.timestamp)} (Audit ${i + 1})'));
    }
    sheet2Headers.add(excel_pkg.TextCellValue('Net Stock Change'));
    sheet2.appendRow(sheet2Headers);

    final sortedMedicines = List<Medicine>.from(medicines)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    for (final med in sortedMedicines) {
      final row = <excel_pkg.CellValue>[
        excel_pkg.TextCellValue(med.name),
      ];

      int? firstCount;
      int? lastCount;

      for (int i = 0; i < chronologicalHistory.length; i++) {
        final b = chronologicalHistory[i];
        final stock = b.totalStocks[med.id] ?? ((b.clinicStocks[med.id] ?? 0) + (b.storeStocks[med.id] ?? 0));
        row.add(excel_pkg.IntCellValue(stock));

        firstCount ??= stock;
        lastCount = stock;
      }

      final netChange = (lastCount ?? 0) - (firstCount ?? 0);
      row.add(excel_pkg.IntCellValue(netChange));
      sheet2.appendRow(row);
    }

    // -------------------------------------------------------------
    // SHEET 3: CYCLE DISCREPANCIES & IRREGULARITIES (RECURRING AUDIT VARIANCES)
    // -------------------------------------------------------------
    if (chronologicalHistory.length >= 2) {
      const sheet3Name = 'Cycle Irregularities';
      final sheet3 = excel[sheet3Name];

      sheet3.appendRow([excel_pkg.TextCellValue('AUDIT CYCLE DISCREPANCY & IRREGULARITY TRACKER')]);
      sheet3.appendRow([excel_pkg.TextCellValue('Variance = Ending Snapshot Count - Expected Count (Baseline + Transfers - Sales).')]);
      sheet3.appendRow([excel_pkg.TextCellValue('Negative numbers (-) indicate missing stock / shrinkage during that specific audit period.')]);
      sheet3.appendRow([]);

      final medMap = {for (var m in medicines) m.name.toLowerCase().trim(): m.id};

      // Define cycles: between consecutive baselines [B_{i} -> B_{i+1}]
      final numCycles = chronologicalHistory.length - 1;
      final sheet3Headers = <excel_pkg.CellValue>[
        excel_pkg.TextCellValue('Medicine Name'),
      ];

      for (int c = 0; c < numCycles; c++) {
        final startB = chronologicalHistory[c];
        final endB = chronologicalHistory[c + 1];
        sheet3Headers.add(excel_pkg.TextCellValue(
            'Cycle ${c + 1} (${shortDateFormat.format(startB.timestamp)} ➔ ${shortDateFormat.format(endB.timestamp)})'));
      }
      sheet3Headers.add(excel_pkg.TextCellValue('Shortage Frequency'));
      sheet3Headers.add(excel_pkg.TextCellValue('Irregularity Flag'));
      sheet3.appendRow(sheet3Headers);

      // Pre-aggregate sales and transfers per cycle
      // cycleData: cycleIndex -> { medicineId -> { 'transferred': X, 'consumed': Y } }
      final cycleData = List.generate(numCycles, (_) => <int, int>{});

      for (int c = 0; c < numCycles; c++) {
        final startT = chronologicalHistory[c].timestamp;
        final endT = chronologicalHistory[c + 1].timestamp;

        // Sales consumption in this cycle
        final cycleConsumed = <int, int>{};
        for (final sale in allSales) {
          final dt = sale.createdAt is DateTime ? sale.createdAt as DateTime : null;
          if (dt == null) continue;
          if (dt.isBefore(startT) || dt.isAfter(endT)) continue;

          for (final item in AnalyticsHelper.getItems(sale)) {
            if (!item.isProcedure) {
              final localId = medMap[item.medicineName.toLowerCase().trim()];
              if (localId != null) {
                cycleConsumed[localId] = (cycleConsumed[localId] ?? 0) + item.qty;
              }
            }
          }
        }
        cycleData[c] = cycleConsumed;
      }

      for (final med in sortedMedicines) {
        final row = <excel_pkg.CellValue>[
          excel_pkg.TextCellValue(med.name),
        ];

        int shortageCyclesCount = 0;
        int totalCycleVariance = 0;

        for (int c = 0; c < numCycles; c++) {
          final startB = chronologicalHistory[c];
          final endB = chronologicalHistory[c + 1];

          final startStock = startB.totalStocks[med.id] ?? ((startB.clinicStocks[med.id] ?? 0) + (startB.storeStocks[med.id] ?? 0));
          final endStock = endB.totalStocks[med.id] ?? ((endB.clinicStocks[med.id] ?? 0) + (endB.storeStocks[med.id] ?? 0));
          final consumed = cycleData[c][med.id] ?? 0;

          // Expected at end of cycle = starting stock - consumed (at total level transfers within clinic/store cancel out)
          final expected = startStock - consumed;
          final cycleVariance = endStock - expected;

          row.add(excel_pkg.IntCellValue(cycleVariance));
          totalCycleVariance += cycleVariance;

          if (cycleVariance < 0) {
            shortageCyclesCount++;
          }
        }

        row.add(excel_pkg.TextCellValue('$shortageCyclesCount of $numCycles cycles'));

        String flag = 'Normal';
        if (shortageCyclesCount == numCycles && numCycles >= 2) {
          flag = 'RECURRING SHORTAGE (Attention)';
        } else if (shortageCyclesCount > 0) {
          flag = 'Intermittent Shortage';
        } else if (totalCycleVariance > 0) {
          flag = 'Surplus Count';
        }
        row.add(excel_pkg.TextCellValue(flag));

        sheet3.appendRow(row);
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    final dateStr = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
    final file = File(p.join(dir.path, 'Audit_History_Comparison_$dateStr.xlsx'));
    final bytes = excel.encode();

    if (bytes != null) {
      await file.writeAsBytes(bytes);
      return file;
    }
    return null;
  }
}

