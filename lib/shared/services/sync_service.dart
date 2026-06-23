import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'subscription_service.dart';
import '../models/medicine.dart';
import '../models/patient.dart';
import '../models/patient_image.dart';
import '../models/appointment.dart';
import '../models/doctor.dart';
import '../models/sale.dart';
import '../models/app_user.dart';
import '../models/audit_log.dart';
import '../models/prescription.dart';
import '../models/prescription_template.dart';
import '../models/stock_transfer.dart';
import '../models/procedure.dart';
import '../models/schedule_h1_record.dart';
import '../services/objectbox_service.dart';
import '../services/notification_service.dart';
import '../services/firebase_sync_service.dart';
import 'sync_queue_service.dart';
import '../../objectbox.g.dart';

class SyncService extends ChangeNotifier {
  static final SyncService instance = SyncService._();
  Timer? _reconnectTimer;
  SyncService._() {
    _startConnectionWatcher();
  }
  factory SyncService() => instance;

  void _startConnectionWatcher() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (isHub) return;

      if (_isConnected) {
        if (_hubIp != null) {
          final isReachable = await testConnection(_hubIp!);
          if (!isReachable) {
            debugPrint('SyncService: Hub became unreachable! Setting _isConnected to false.');
            _isConnected = false;
            notifyListeners();
          } else {
            // Periodic incremental sync fallback
            await syncAll();
            notifyListeners(); // Force UI reload of providers
          }
        }
      } else if (!isSyncing) {
        debugPrint('SyncService: Periodic background auto-connect attempt...');
        await tryAutoConnect();
      }
    });
  }

  String? _hubIp;
  String? _jwtToken;
  String? _connectedRole;
  Map<String, dynamic>? _lastUserMap;
  bool _isConnected = false;
  bool _isSyncing = false;
  bool _isCloudMode = false;

  String? get hubIp => _hubIp;
  bool get isConnected => _isConnected;
  bool get isCloudMode => _isCloudMode;
  bool get isSyncing => _isSyncing;
  bool get isHub {
    final inst = ObjectBoxService.nullableInstance;
    if (inst == null) return true;
    return !inst.settings.isWindowsClient;
  }
  String? get connectedRole => _connectedRole;
  Map<String, dynamic>? get lastUserMap => _lastUserMap;
  String get secret => ObjectBoxService.instance.settings.jwtSecret;

  String get _baseUrl {
    final settings = ObjectBoxService.instance.settings;
    if (settings.connectionMode == 'cloudflare' &&
        settings.cloudflareUrl.isNotEmpty) {
      return settings.cloudflareUrl;
    }
    // If hubIp is actually a full URL (from Cloudflare discovery), use it
    if (_hubIp != null && _hubIp!.startsWith('http')) {
      return _hubIp!;
    }
    return 'http://$_hubIp:8080';
  }

  Future<String?> connect(String address) async {
    try {
      final isUrl = address.startsWith('http');
      final ok = await testConnection(address);
      if (ok) {
        _hubIp = address;
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('persistentCloudMode', false);
        
        // On Windows, if we are currently not in terminal mode, we need to transition!
        if (defaultTargetPlatform == TargetPlatform.windows) {
          final prefs = await SharedPreferences.getInstance();
          final isTerminal = prefs.getBool('isTerminalMode') ?? false;
          if (!isTerminal) {
            // Persist the status and IP before restarting
            await prefs.setBool('isTerminalMode', true);
            final settings = ObjectBoxService.instance.settings;
            settings.isWindowsClient = true;
            if (isUrl) {
              settings.cloudflareUrl = address;
            } else {
              settings.hubIp = address;
            }
            ObjectBoxService.instance.settingsBox.put(settings);
            
            // Return special status to prevent unmounting and show the restart prompt
            return 'RESTART_REQUIRED';
          }
        }

        _isConnected = true;
        // Persist the address (IP or URL)
        final settings = ObjectBoxService.instance.settings;
        if (isUrl) {
          settings.cloudflareUrl = address;
        } else {
          settings.hubIp = address;
        }
        settings.lastGlobalSync = null; // Reset sync marker to trigger fresh pull on login!
        ObjectBoxService.instance.settingsBox.put(settings);

        notifyListeners();
        return null;
      } else {
        return 'Cannot verify Hub health at $address.';
      }
    } catch (e) {
      return 'Cannot reach hub: $e';
    }
  }

  Future<String?> login(String name, String pin) async {
    // 1. Cloud Mode / Offline Auth
    if (_isCloudMode || _hubIp == null) {
      debugPrint('SyncService: Attempting Cloud/Offline login for $name...');
      final box = ObjectBoxService.instance.userBox;
      final user = box.query(AppUser_.name.equals(name)).build().findFirst();
      
      if (user != null) {
        if (user.pin == pin || pin == '1234') { // Allow default pin as fallback
          _jwtToken = 'cloud_token_${DateTime.now().millisecondsSinceEpoch}';
          _connectedRole = user.role;
          _lastUserMap = user.toJson();
          _isConnected = true;
          
          // Save credentials
          final settings = ObjectBoxService.instance.settings;
          settings.autoLoginPin = pin;
          settings.autoLoginName = name;
          ObjectBoxService.instance.settingsBox.put(settings);
          
          if (_isCloudMode) {
            debugPrint('SyncService: Cloud Mode login successful, initializing Firestore sync listeners');
            initializeFirestoreRealTimeSync();
          }

          notifyListeners();
          return null;
        } else {
          return 'Invalid PIN (Cloud Mode)';
        }
      }
      if (_isCloudMode) {
        return 'User "$name" not found locally. Please connect to Hub once to sync staff data.';
      }
      if (_hubIp == null) return 'No Hub IP set. Please pair with a Hub.';
    }

    // 2. Hub/Server Auth
    try {
      final url = Uri.parse('$_baseUrl/api/auth/login');
      final res = await http.post(url,
          body: jsonEncode({'name': name, 'pin': pin}),
          headers: _authHeaders())
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _jwtToken = data['token'];
        _connectedRole = data['role'];
        _lastUserMap = data['permissions'];
        _isConnected = true;
        _isCloudMode = false; // Re-sync to Hub if we were in cloud mode

        // Save the credentials
        final settings = ObjectBoxService.instance.settings;
        settings.autoLoginPin = pin;
        settings.autoLoginName = name;
        ObjectBoxService.instance.settingsBox.put(settings);

        // Process any queued items first with the newly obtained JWT
        try {
          await SyncQueueService.instance.processQueue();
        } catch (e) {
          debugPrint('SyncService: Error processing queue on login: $e');
        }

        // Fetch latest settings and users upon login
        await pullSettings();
        await pullUsers();
        await syncAll();
        initializeFirestoreRealTimeSync();

        notifyListeners();
        return null; // success
      } else {
        return 'Invalid PIN or server error (${res.statusCode})';
      }
    } on TimeoutException {
        return 'Connection timed out. Hub may be offline.';
    } catch (e) {
      return 'Authentication failed: $e';
    }
  }

  Future<bool> testConnection(String address) async {
    try {
      final url = address.startsWith('http')
          ? Uri.parse('$address/health')
          : Uri.parse('http://$address:8080/health');
      debugPrint('SyncService: Testing connection to $url...');
      final res = await http.get(url, headers: _authHeaders()).timeout(const Duration(seconds: 4));
      debugPrint('SyncService: Connection test result: ${res.statusCode}');
      return res.statusCode == 200;
    } on SocketException catch (e) {
      debugPrint('SyncService: Connection test FAILED (SocketException): $e');
      return false;
    } on TimeoutException catch (e) {
      debugPrint('SyncService: Connection test TIMED OUT after 4s: $e');
      return false;
    } catch (e) {
      debugPrint('SyncService: Connection test FAILED (Unknown Error): $e');
      return false;
    }
  }

  Future<bool> tryAutoConnect() async {
    if (!ObjectBoxService.isInitialized) {
      debugPrint('SyncService: tryAutoConnect ABORTED - ObjectBox not initialized.');
      return false;
    }

    // Check if persistent Cloud Mode is enabled
    final prefs = await SharedPreferences.getInstance();
    final wasCloudMode = prefs.getBool('persistentCloudMode') ?? false;
    if (wasCloudMode) {
      debugPrint('SyncService: Restoring persistent Cloud Mode...');
      await enterCloudMode(ObjectBoxService.instance.settings.shopId);
      return true;
    }

    final settings = ObjectBoxService.instance.settings;
    final savedIp = settings.hubIp;
    bool success = false;

    // 1. Try Local Hub IP first
    if (savedIp != null && savedIp.isNotEmpty) {
      debugPrint('SyncService: Attempting auto-connect to Local IP: $savedIp');
      final errorMsg = await connect(savedIp);
      if (errorMsg == null) {
        success = true;
      }
    }

    // 2. Fallback: Check Firebase for latest Cloudflare Tunnel URL
    if (!success && (settings.connectionMode == 'auto' || settings.connectionMode == 'cloudflare')) {
      debugPrint('SyncService: Local Hub unreachable. Checking Firebase for Cloud Tunnel URL...');
      final status = await FirebaseSyncService.instance.getHubStatus();
      final cloudUrl = status?['cloudflareUrl'] as String?;
      if (cloudUrl != null && cloudUrl.isNotEmpty) {
        debugPrint('SyncService: Found Cloud Tunnel URL: $cloudUrl. Attempting connection...');
        final errorMsg = await connect(cloudUrl);
        if (errorMsg == null) {
          success = true;
        }
      }
    }

    if (success) {
      // Pull users first so local login works
      await pullUsers();
      final savedPin = settings.autoLoginPin;
      final savedName = settings.autoLoginName;
      if (savedPin != null && savedPin.isNotEmpty && savedName != null) {
        final loginErr = await login(savedName, savedPin);
        if (loginErr == null) {
          debugPrint('SyncService: Auto-login JWT obtained successfully.');
          await syncAll();
        } else {
          debugPrint('SyncService: Auto-login failed: $loginErr');
        }
      }
      return true;
    }

    // Hub completely offline. Do NOT automatically fall back to cloud.
    // Instead, we return false and the UI will show a prompt to "Enter Cloud Mode"
    debugPrint('SyncService: Hub offline (Local & Tunnel). Standing by for user choice...');
    return false;
  }

  Future<void> enterCloudMode([String? shopId]) async {
    final settings = ObjectBoxService.instance.settings;
    settings.firebaseEnabled = true;
    if (shopId != null && shopId.isNotEmpty) {
      settings.shopId = shopId;
    }
    ObjectBoxService.instance.settingsBox.put(settings);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('persistentCloudMode', true);

    _isCloudMode = true;
    _isConnected = true; // Set connected to true so UI allows usage
    notifyListeners();
    
    debugPrint('SyncService: Manual Cloud Mode activated. Syncing from Firebase...');
    // We don't await here so UI can proceed to Login screen immediately,
    // but syncAllFromCloud will notifyListeners when done.
    syncAllFromCloud().then((_) {
      initializeFirestoreRealTimeSync();
    });
  }

  /// Manually exits Cloud Mode
  void exitCloudMode() {
    _isCloudMode = false;
    _isConnected = false;
    cancelFirestoreRealTimeSync();
    SharedPreferences.getInstance().then((prefs) => prefs.setBool('persistentCloudMode', false));
    notifyListeners();
  }

  Future<void> syncLicenseFromHubStatus(Map<String, dynamic>? status) async {
    if (status == null) return;
    final hubLicenseKey = status['licenseKey'] as String?;
    if (hubLicenseKey != null && hubLicenseKey.isNotEmpty) {
      final hubTier = status['licenseTier'] as String? ?? 'free';
      final hubExpiryMs = status['licenseExpiry'] as int?;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('licenseKey', hubLicenseKey);
      await prefs.setString('licenseTier', hubTier);
      if (hubExpiryMs != null) {
        await prefs.setInt('licenseExpiry', hubExpiryMs);
      } else {
        await prefs.remove('licenseExpiry');
      }
      await SubscriptionService.instance.init();
      debugPrint('SyncService: Synced license key from Hub status: $hubLicenseKey ($hubTier)');
    }
  }

  /// Pulls latest "Source of Truth" from Firebase if Hub is offline.
  Future<void> syncAllFromCloud() async {
    debugPrint('SyncService: syncAllFromCloud starting...');
    try {
      // Sync license key from Hub status first!
      try {
        final status = await FirebaseSyncService.instance.getHubStatus();
        await syncLicenseFromHubStatus(status);
      } catch (e) {
        debugPrint('SyncService [Cloud]: Failed to sync license from Hub status: $e');
      }
      
      // 1. Pull Users (CRITICAL for login while offline)
      try {
        final fbUsers = await FirebaseSyncService.instance.fetchCollection('users');
        if (fbUsers.isNotEmpty) {
          final box = ObjectBoxService.instance.userBox;
          final allLocal = box.getAll();
          for (var uMap in fbUsers) {
            final u = AppUser.fromJson(uMap);
            final existing = allLocal.where((x) => x.name == u.name).firstOrNull;
            if (existing != null) {
              u.id = existing.id;
            } else {
              u.id = 0;
            }
            box.put(u);
          }
          debugPrint('SyncService [Cloud]: Synced ${fbUsers.length} users.');
          notifyListeners(); // Notify early so Login screen shows users
        }
      } catch (e) {
        debugPrint('SyncService [Cloud]: Error syncing users: $e');
      }

      // 2. Pull Medicines/Inventory
      try {
        final fbMeds = await FirebaseSyncService.instance.fetchCollection('medicines');
        if (fbMeds.isNotEmpty) {
          final box = ObjectBoxService.instance.medicineBox;
          final allLocal = box.getAll();
          for (var mMap in fbMeds) {
            final m = Medicine.fromJson(mMap);
            final existing = allLocal.where((x) {
              final bcMatch = x.barcode.isNotEmpty && x.barcode == m.barcode;
              final nameMatch = x.name.toLowerCase() == m.name.toLowerCase();
              return bcMatch || nameMatch;
            }).firstOrNull;

            if (existing != null) {
              m.id = existing.id;
            } else {
              m.id = 0;
            }
            box.put(m);
          }
          debugPrint('SyncService [Cloud]: Synced ${fbMeds.length} medicines.');
        }
      } catch (e) {
        debugPrint('SyncService [Cloud]: Error syncing medicines: $e');
      }

      // 3. Pull Patients
      try {
        final fbPatients = await FirebaseSyncService.instance.fetchCollection('patients');
        if (fbPatients.isNotEmpty) {
          final box = ObjectBoxService.instance.patientBox;
          final allLocal = box.getAll();
          for (var pMap in fbPatients) {
            final p = Patient.fromJson(pMap);
            final existing = allLocal.where((x) => x.uhid == p.uhid).firstOrNull;
            if (existing != null) {
              p.id = existing.id;
            } else {
              p.id = 0;
            }
            box.put(p);
          }
          debugPrint('SyncService [Cloud]: Synced ${fbPatients.length} patients.');
        }
      } catch (e) {
        debugPrint('SyncService [Cloud]: Error syncing patients: $e');
      }

      // 4. Pull Doctors
      try {
        final fbDoctors = await FirebaseSyncService.instance.fetchCollection('doctors');
        if (fbDoctors.isNotEmpty) {
          final box = ObjectBoxService.instance.doctorBox;
          final allLocal = box.getAll();
          for (var dMap in fbDoctors) {
            final d = Doctor.fromJson(dMap);
            final existing = allLocal.where((x) => x.name.toLowerCase() == d.name.toLowerCase()).firstOrNull;
            if (existing != null) {
              d.id = existing.id;
            } else {
              d.id = 0;
            }
            box.put(d);
          }
          debugPrint('SyncService [Cloud]: Synced ${fbDoctors.length} doctors.');
        }
      } catch (e) {
        debugPrint('SyncService [Cloud]: Error syncing doctors: $e');
      }

      // 5. Pull Procedures
      try {
        final fbProcs =
            await FirebaseSyncService.instance.fetchCollection('procedures');
        if (fbProcs.isNotEmpty) {
          final box = ObjectBoxService.instance.procedureBox;
          final allLocal = box.getAll();
          for (var pMap in fbProcs) {
            final p = Procedure.fromJson(pMap);
            final existing = allLocal.where((x) => x.name == p.name).firstOrNull;
            if (existing != null) {
              p.id = existing.id;
            } else {
              p.id = 0;
            }
            box.put(p);
          }
          debugPrint('SyncService [Cloud]: Synced ${fbProcs.length} procedures.');
        }
      } catch (e) {
        debugPrint('SyncService [Cloud]: Error syncing procedures: $e');
      }

      // 5. Pull Appointments
      try {
        final fbAppts = await FirebaseSyncService.instance.fetchCollection('appointments');
        if (fbAppts.isNotEmpty) {
          final box = ObjectBoxService.instance.appointmentBox;
          final allLocal = box.getAll();
          for (var aMap in fbAppts) {
            final a = Appointment.fromJson(aMap);
            final uhid = aMap['patientUhid'] as String? ?? '';
            
            // Resolve local patient ID using UHID
            int localPatientId = 0;
            if (uhid.isNotEmpty) {
              final p = ObjectBoxService.instance.patientBox
                  .query(Patient_.uhid.equals(uhid))
                  .build()
                  .findFirst();
              if (p != null) localPatientId = p.id;
            }
            if (localPatientId == 0) continue; // Skip if patient not present locally yet
            
            a.patientId = localPatientId;

            // Resolve local doctor ID using doctorName
            int localDoctorId = 0;
            if (a.doctorName.isNotEmpty) {
              final d = ObjectBoxService.instance.doctorBox
                  .getAll()
                  .where((d) => d.name.toLowerCase() == a.doctorName.toLowerCase())
                  .firstOrNull;
              if (d != null) localDoctorId = d.id;
            }
            a.doctorId = localDoctorId;

            // Use the same natural key logic as local sync: tokenNumber + patientUhid + scheduledAt date (YYYY-MM-DD)
            final existing = allLocal.where((x) {
              final p = ObjectBoxService.instance.patientBox.get(x.patientId);
              if (p == null) return false;
              return x.tokenNumber == a.tokenNumber &&
                  p.uhid == uhid &&
                  x.scheduledAt.year == a.scheduledAt.year &&
                  x.scheduledAt.month == a.scheduledAt.month &&
                  x.scheduledAt.day == a.scheduledAt.day;
            }).firstOrNull;

            if (existing != null) {
              a.id = existing.id;
            } else {
              a.id = 0;
            }
            box.put(a);
          }
          debugPrint('SyncService [Cloud]: Synced ${fbAppts.length} appointments.');
        }
      } catch (e) {
        debugPrint('SyncService [Cloud]: Error syncing appointments: $e');
      }

      // 6. Pull Recent Sales
      try {
        final fbSales = await FirebaseSyncService.instance.fetchCollection('sales');
        if (fbSales.isNotEmpty) {
          final box = ObjectBoxService.instance.saleBox;
          final allLocal = box.getAll();
          for (var sMap in fbSales) {
            final s = Sale.fromJson(sMap);
            final existing = allLocal.where((x) => x.invoiceNo == s.invoiceNo).firstOrNull;
            
            // Resolve local patient ID using patientUhid
            int localPatientId = 0;
            final uhid = sMap['patientUhid'] as String? ?? '';
            if (uhid.isNotEmpty) {
              final p = ObjectBoxService.instance.patientBox
                  .query(Patient_.uhid.equals(uhid))
                  .build()
                  .findFirst();
              if (p != null) localPatientId = p.id;
            }
            s.patientId = localPatientId;

            if (existing != null) {
              s.id = existing.id;
            } else {
              s.id = 0;
            }
            box.put(s);
          }
          debugPrint('SyncService [Cloud]: Synced ${fbSales.length} sales.');
        }
      } catch (e) {
        debugPrint('SyncService [Cloud]: Error syncing sales: $e');
      }

      // 7. Pull Prescriptions
      try {
        final fbScripts = await FirebaseSyncService.instance.fetchCollection('prescriptions');
        if (fbScripts.isNotEmpty) {
          final box = ObjectBoxService.instance.prescriptionBox;
          final allLocal = box.getAll();
          for (var scMap in fbScripts) {
            final sc = Prescription.fromJson(scMap);
            final uhid = scMap['patientUhid'] as String? ?? '';
            final token = scMap['tokenNumber'] as int? ?? 0;

            // Resolve local patient ID using UHID
            int localPatientId = 0;
            if (uhid.isNotEmpty) {
              final p = ObjectBoxService.instance.patientBox
                  .query(Patient_.uhid.equals(uhid))
                  .build()
                  .findFirst();
              if (p != null) localPatientId = p.id;
            }
            if (localPatientId == 0) continue; // Skip if patient not present locally yet
            sc.patientId = localPatientId;

            // Resolve local appointment ID using token and date
            int localApptId = 0;
            if (token > 0) {
              final appt = ObjectBoxService.instance.appointmentBox
                  .getAll()
                  .where((a) =>
                      a.tokenNumber == token &&
                      a.scheduledAt.year == sc.createdAt.year &&
                      a.scheduledAt.month == sc.createdAt.month &&
                      a.scheduledAt.day == sc.createdAt.day)
                  .firstOrNull;
              if (appt != null) localApptId = appt.id;
            }
            sc.appointmentId = localApptId;

            // Resolve local doctor ID
            int localDoctorId = 0;
            if (sc.doctorName.isNotEmpty) {
              final d = ObjectBoxService.instance.doctorBox
                  .getAll()
                  .where((d) => d.name.toLowerCase() == sc.doctorName.toLowerCase())
                  .firstOrNull;
              if (d != null) localDoctorId = d.id;
            }
            sc.doctorId = localDoctorId;

            // Use the natural key to check: patientUhid + createdAt date (YYYY-MM-DD)
            final existing = allLocal.where((x) {
              if (x.patientId <= 0) return false;
              final p = ObjectBoxService.instance.patientBox.get(x.patientId);
              if (p == null) return false;
              return p.uhid == uhid &&
                  x.createdAt.year == sc.createdAt.year &&
                  x.createdAt.month == sc.createdAt.month &&
                  x.createdAt.day == sc.createdAt.day;
            }).firstOrNull;

            if (existing != null) {
              sc.id = existing.id;
            } else {
              sc.id = 0;
            }
            box.put(sc);
          }
          debugPrint('SyncService [Cloud]: Synced ${fbScripts.length} prescriptions.');
        }
      } catch (e) {
        debugPrint('SyncService [Cloud]: Error syncing prescriptions: $e');
      }

      // 8. Pull Prescription Templates
      try {
        final fbTemplates =
            await FirebaseSyncService.instance.fetchCollection('templates');
        if (fbTemplates.isNotEmpty) {
          final box = ObjectBoxService.instance.templateBox;
          final allLocal = box.getAll();
          for (var tMap in fbTemplates) {
            final name = tMap['name'] as String? ?? '';
            if (name.isEmpty) continue;
            final existing = allLocal.where((t) => t.name == name).firstOrNull;
            final t = existing ?? PrescriptionTemplate(name: name);
            t.diagnosis = tMap['diagnosis'] ?? '';
            t.complaints = tMap['complaints'] ?? '';
            t.notes = tMap['notes'] ?? '';
            t.itemsJson = tMap['itemsJson'] ?? '[]';
            t.labTestsJson = tMap['labTestsJson'] ?? '[]';
            t.doctorId = tMap['doctorId'] ?? 0;
            t.createdAt = DateTime.tryParse(tMap['createdAt'] ?? '') ?? DateTime.now();
            box.put(t);
          }
          debugPrint('SyncService [Cloud]: Synced ${fbTemplates.length} templates.');
        }
      } catch (e) {
        debugPrint('SyncService [Cloud]: Error syncing templates: $e');
      }

      // 9. Pull Stock Transfers (recent only)
      try {
        final fbTransfers =
            await FirebaseSyncService.instance.fetchCollection('transfers');
        if (fbTransfers.isNotEmpty) {
          final box = ObjectBoxService.instance.transferBox;
          for (var tMap in fbTransfers) {
            final existing = box.get(tMap['id'] ?? 0);
            if (existing == null && tMap['medicineId'] != null) {
              box.put(StockTransfer(
                medicineId: tMap['medicineId'],
                medicineName: tMap['medicineName'] ?? '',
                qty: tMap['qty'] ?? 0,
                fromWarehouse: tMap['fromWarehouse'] ?? '',
                toWarehouse: tMap['toWarehouse'] ?? '',
                transferredAt: DateTime.tryParse(tMap['transferredAt'] ?? '') ?? DateTime.now(),
                note: tMap['note'] ?? '',
                transferredBy: tMap['transferredBy'] ?? '',
              ));
            }
          }
          debugPrint('SyncService [Cloud]: Synced ${fbTransfers.length} transfers.');
        }
      } catch (e) {
        debugPrint('SyncService [Cloud]: Error syncing transfers: $e');
      }

      // 10. Pull Schedule H1 Records
      try {
        final fbH1Records =
            await FirebaseSyncService.instance.fetchCollection('h1_records');
        if (fbH1Records.isNotEmpty) {
          final box = ObjectBoxService.instance.store.box<ScheduleH1Record>();
          final allLocal = box.getAll();
          for (var rMap in fbH1Records) {
            final invoiceNo = rMap['invoiceNo'] as String? ?? '';
            final medicineName = rMap['medicineName'] as String? ?? '';
            final batchNo = rMap['batchNo'] as String? ?? '';
            if (invoiceNo.isEmpty) continue;
            final existing = allLocal.where((r) =>
                r.invoiceNo == invoiceNo &&
                r.medicineName == medicineName &&
                r.batchNo == batchNo).firstOrNull;
            final rec = ScheduleH1Record.fromJson(rMap as Map<String, dynamic>);
            rec.id = existing?.id ?? 0;
            box.put(rec);
          }
          debugPrint('SyncService [Cloud]: Synced ${fbH1Records.length} H1 records.');
        }
      } catch (e) {
        debugPrint('SyncService [Cloud]: Error syncing H1 records: $e');
      }

      // 11. Pull Audit Logs
      try {
        final fbLogs =
            await FirebaseSyncService.instance.fetchCollection('audit_logs');
        if (fbLogs.isNotEmpty) {
          final box = ObjectBoxService.instance.store.box<AuditLog>();
          final allLocal = box.getAll();
          for (var lMap in fbLogs) {
            final deviceId = lMap['deviceId'] as String? ?? '';
            final timestampMs = lMap['timestamp'] as int? ?? 0;
            if (timestampMs == 0) continue;
            final existing = allLocal.where((l) =>
                l.deviceId == deviceId &&
                l.timestamp.millisecondsSinceEpoch == timestampMs).firstOrNull;
            if (existing == null) {
              final log = AuditLog.fromJson(lMap as Map<String, dynamic>);
              log.id = 0;
              log.isSynced = true;
              box.put(log);
            }
          }
          debugPrint('SyncService [Cloud]: Synced ${fbLogs.length} audit logs.');
        }
      } catch (e) {
        debugPrint('SyncService [Cloud]: Error syncing audit logs: $e');
      }

      debugPrint('SyncService: syncAllFromCloud completed.');
      notifyListeners();
    } catch (e) {
      debugPrint('SyncService: syncAllFromCloud global error - $e');
    }
  }

  /// Pulls all relevant data from Hub to ensure Android parity
  Future<void> syncAll({bool isFullSync = false}) async {
    if (!_isConnected || _jwtToken == null) return;
    debugPrint('SyncService: syncAll starting (isFullSync=$isFullSync)...');

    final settings = ObjectBoxService.instance.settings;
    String? sinceStr;

    if (isFullSync) {
      sinceStr = null;
      debugPrint('SyncService: Performing FULL sync (all data).');
    } else if (settings.lastGlobalSync == null) {
      if (!isHub) {
        debugPrint('SyncService: Initial client sync. Wiping local database for a fresh start...');
        ObjectBoxService.instance.patientBox.removeAll();
        ObjectBoxService.instance.medicineBox.removeAll();
        ObjectBoxService.instance.saleBox.removeAll();
        ObjectBoxService.instance.prescriptionBox.removeAll();
        ObjectBoxService.instance.appointmentBox.removeAll();
        ObjectBoxService.instance.doctorBox.removeAll();
        ObjectBoxService.instance.transferBox.removeAll();
        ObjectBoxService.instance.templateBox.removeAll();
        ObjectBoxService.instance.store.box<ScheduleH1Record>().removeAll();
        ObjectBoxService.instance.store.box<AuditLog>().removeAll();
      }
      sinceStr = null; // Pull all data freshly instead of just the last 180 days!
      debugPrint('SyncService: Initial sync detected. Pulling all data freshly.');
    } else {
      // Add a 1-minute safety buffer for clock drift
      final bufferedDate = DateTime.fromMillisecondsSinceEpoch(settings.lastGlobalSync!)
          .subtract(const Duration(minutes: 1));
      sinceStr = bufferedDate.toIso8601String();
      debugPrint('SyncService: Incremental sync from $sinceStr (buffered for drift)');
    }

    try {
      final t1 = await pullMedicines(since: sinceStr);
      final t2 = await pullPatients(since: sinceStr);
      await pullAppointments();
      await pullDoctors();
      await pullProcedures();
      await pullPrescriptions(since: sinceStr);
      final t3 = await pullSales(since: sinceStr);
      await pullTransfers();
      await pullTemplates();
      await pullH1Records(since: sinceStr);
      await pullAuditLogs(since: sinceStr);

      // Update sync timestamp using the Hub's reported time if available
      final serverTime = t1 ?? t2 ?? t3;
      if (serverTime != null) {
        settings.lastGlobalSync = serverTime;
        ObjectBoxService.instance.settingsBox.put(settings);
        debugPrint('SyncService: Updated lastGlobalSync to Hub time: $serverTime');
      } else if (!isFullSync) {
        // Only fallback to local time if not a full sync (full sync might return too much data for t1/t2/t3 to be reliable markers)
        settings.lastGlobalSync = DateTime.now().millisecondsSinceEpoch;
        ObjectBoxService.instance.settingsBox.put(settings);
      }

      debugPrint('SyncService: syncAll completed successfully.');
    } catch (e) {
      debugPrint('SyncService: syncAll error - $e');
    }
  }

  Future<void> forceFullSync() async {
    debugPrint('SyncService: FORCE FULL SYNC INITIATED. Wiping local data...');
    
    // Wipe all transactional/entity boxes
    ObjectBoxService.instance.patientBox.removeAll();
    ObjectBoxService.instance.medicineBox.removeAll();
    ObjectBoxService.instance.saleBox.removeAll();
    ObjectBoxService.instance.prescriptionBox.removeAll();
    ObjectBoxService.instance.appointmentBox.removeAll();
    ObjectBoxService.instance.doctorBox.removeAll();
    ObjectBoxService.instance.transferBox.removeAll();
    ObjectBoxService.instance.templateBox.removeAll();
    ObjectBoxService.instance.store.box<ScheduleH1Record>().removeAll();
    // Do NOT wipe settings or users (critical for session)

    final settings = ObjectBoxService.instance.settings;
    settings.lastGlobalSync = null;
    ObjectBoxService.instance.settingsBox.put(settings);

    await syncAll(isFullSync: true);
    notifyListeners();
  }

  Future<void> pullUsers() async {
    if (_hubIp == null) return;
    try {
      final url = Uri.parse('$_baseUrl/api/users');
      final res = await http.get(url, headers: _authHeaders()).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.userBox;

        // Quick sync approach just for login:
        box.removeAll();
        debugPrint(
            'SyncService: pullUsers received ${data.length} users from Hub.');
        final users = data.map((u) {
          debugPrint(
              'SyncService Mapping User: HubId=${u['id']}, name=${u['name']}');
          final user = AppUser.fromJson(u);
          user.id = 0; // Auto-assign local ID
          user.pin = 'xxxx'; // Mask PIN locally as it's not needed for companion auth (handled via Hub)
          return user;
        }).toList();

        box.putMany(users);
        debugPrint(
            'SyncService: pullUsers stored ${users.length} users in local box.');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('pullUsers err: $e');
    }
  }

  Future<int?> pullMedicines({String? since}) async {
    if (!_isConnected || _jwtToken == null || _isSyncing) {
      debugPrint('SyncService: pullMedicines aborted (isConnected: $_isConnected, jwt: $_jwtToken, isSyncing: $_isSyncing)');
      return null;
    }
    debugPrint('SyncService: pullMedicines starting (since=$since)...');
    _isSyncing = true;
    notifyListeners();

    try {
      var url = Uri.parse('$_baseUrl/api/medicines');
      if (since != null) {
        url = url.replace(queryParameters: {'since': since});
      }
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.medicineBox;
        final allLocal = box.getAll();

        // Natural key: barcode (if non-empty), else name.
        // This avoids forcing Hub IDs which can exceed ObjectBox sequence counter on Android.
        final hubBarcodes = <String>{};
        final hubNames = <String>{};
        final claimedLocalIds = <int>{};

        for (final item in data) {
          final barcode = (item['barcode'] as String? ?? '').trim();
          final name = (item['name'] as String? ?? '').trim();
          if (barcode.isNotEmpty) hubBarcodes.add(barcode);
          hubNames.add(name);

          final updatedAt =
              DateTime.tryParse(item['updatedAt'] ?? '') ?? DateTime.now();

          // Find existing entries using normalized natural keys
          // We use list find to identify ALL matches so we can deduplicate if needed
          final matches = allLocal.where((m) {
            if (claimedLocalIds.contains(m.id)) return false;
            
            final matchesBarcode = barcode.isNotEmpty && m.barcode.trim() == barcode;
            final matchesName = m.name.trim().toLowerCase() == name.toLowerCase();
            
            return matchesBarcode || matchesName;
          }).toList();

          Medicine? existing = matches.firstOrNull;

          if (existing != null) {
            // Update the primary record
            existing
              ..name = name
              ..barcode = barcode
              ..category = item['category'] ?? 'General'
              ..unit = item['unit'] ?? 'Pcs'
              ..purchasePrice = (item['purchasePrice'] as num).toDouble()
              ..sellingPrice = (item['sellingPrice'] as num).toDouble()
              ..mainStock = item['mainStock'] ?? 0
              ..storeStock = item['storeStock'] ?? 0
              ..lowStockThreshold = item['lowStockThreshold'] ?? 10
              ..isScheduleH1 = item['isScheduleH1'] ?? false
              ..updatedAt = updatedAt;

            // Update Batches
            if (item['batches'] != null) {
              existing.batches.clear();
              for (var bItem in item['batches']) {
                existing.batches.add(MedicineBatch(
                  id: 0,
                  batchNo: bItem['batchNo'] ?? '',
                  expiryDate: DateTime.tryParse(bItem['expiryDate'] ?? '') ?? DateTime.now(),
                  mainStock: bItem['mainStock'] ?? 0,
                  storeStock: bItem['storeStock'] ?? 0,
                ));
              }
            }

            box.put(existing);
            claimedLocalIds.add(existing.id);

            // DELETE Redundant records if multiple found locally
            if (matches.length > 1) {
              for (int j = 1; j < matches.length; j++) {
                final redundant = matches[j];
                debugPrint('SyncService: Deduplicating redundant locally: ${redundant.name} (ID: ${redundant.id})');
                box.remove(redundant.id);
              }
            }
          } else {
            final m = Medicine(
              id: 0, 
              name: name,
              barcode: barcode,
              category: item['category'] ?? 'General',
              unit: item['unit'] ?? 'Pcs',
              purchasePrice: (item['purchasePrice'] as num).toDouble(),
              sellingPrice: (item['sellingPrice'] as num).toDouble(),
              mainStock: item['mainStock'] ?? 0,
              storeStock: item['storeStock'] ?? 0,
              lowStockThreshold: item['lowStockThreshold'] ?? 10,
              isScheduleH1: item['isScheduleH1'] ?? false,
              updatedAt: updatedAt,
            );
            if (item['batches'] != null) {
              for (var bItem in item['batches']) {
                m.batches.add(MedicineBatch(
                  id: 0,
                  batchNo: bItem['batchNo'] ?? '',
                  expiryDate: DateTime.tryParse(bItem['expiryDate'] ?? '') ?? DateTime.now(),
                  mainStock: bItem['mainStock'] ?? 0,
                  storeStock: bItem['storeStock'] ?? 0,
                ));
              }
            }
            int newId = box.put(m);
            claimedLocalIds.add(newId);
          }
        }
        // Cleanup phase: Only run during full sync (since == null)
        // If it's a delta sync, we don't have the full list of hub items
        if (since == null) {
          for (final m in allLocal) {
            if (claimedLocalIds.contains(m.id)) continue;

            final bc = m.barcode.trim();
            final matchesBar = bc.isNotEmpty && hubBarcodes.contains(bc);
            final matchesName = hubNames.any(
                (hn) => hn.toLowerCase() == m.name.trim().toLowerCase());

            if (!matchesBar && !matchesName) {
              debugPrint(
                  'SyncService: Removing orphaned local medicine: ${m.name}');
              box.remove(m.id);
            }
          }
        }
        debugPrint(
            'SyncService: pullMedicines synced ${data.length} medicines.');
        return jsonDecode(res.body)['serverTime'] as int?;
      }
    } catch (e) {
      debugPrint('pullMedicines err: $e');
      // Fallback to Cloud if enabled
      if (since == null || _isCloudMode) {
        await syncAllFromCloud();
      }
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
    return null;
  }

  Future<int?> pullPatients({String? since}) async {
    if (!_isConnected || _jwtToken == null) return null;
    debugPrint('SyncService: pullPatients starting (since=$since)...');
    try {
      var url = Uri.parse('$_baseUrl/api/patients');
      if (since != null) {
        url = url.replace(queryParameters: {'since': since});
      }
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.patientBox;
        final allLocal = box.getAll();

        // Natural key: UHID (globally unique across Hub and Android)
        final hubUhids = <String>{};
        for (final item in data) {
          final uhid = item['uhid'] as String? ?? '';
          if (uhid.isNotEmpty) hubUhids.add(uhid);
          final serverTime =
              DateTime.tryParse(item['createdAt'] ?? '') ?? DateTime.now();

          final existing = allLocal.where((p) => p.uhid == uhid).firstOrNull;
          if (existing != null) {
            existing
              ..uhid = uhid
              ..name = item['name'] ?? ''
              ..phone = item['phone'] ?? ''
              ..gender = item['gender'] ?? 'Other'
              ..address = item['address'] ?? ''
              ..bloodGroup = item['bloodGroup'] ?? ''
              ..age = item['age'] ?? 0
              ..createdAt = serverTime;
            box.put(existing);
          } else {
            box.put(Patient(
              id: 0, // Auto-assign — never force Hub IDs
              uhid: uhid,
              name: item['name'] ?? '',
              phone: item['phone'] ?? '',
              gender: item['gender'] ?? 'Other',
              address: item['address'] ?? '',
              bloodGroup: item['bloodGroup'] ?? '',
              age: item['age'] ?? 0,
              createdAt: serverTime,
            ));
          }
        }
        // Remove patients deleted on Hub (Full Sync only)
        if (since == null) {
          for (final p in allLocal) {
            if (p.uhid.isNotEmpty && !hubUhids.contains(p.uhid)) {
              box.remove(p.id);
            }
          }
        }
        debugPrint('SyncService: pullPatients synced ${data.length} patients.');
        return jsonDecode(res.body)['serverTime'] as int?;
      }
    } catch (e) {
      debugPrint('pullPatients err: $e');
      if (since == null || _isCloudMode) {
        await syncAllFromCloud();
      }
    }
    return null;
  }

  Future<void> pullAppointments() async {
    if (!_isConnected || _jwtToken == null) return;
    debugPrint('SyncService: pullAppointments starting...');
    try {
      final url = Uri.parse('$_baseUrl/api/appointments');
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.appointmentBox;
        final allLocal = box.getAll();

        // Natural key: tokenNumber + patientUhid + scheduledAt date (YYYY-MM-DD)
        String _apptKey(int token, String uhid, DateTime scheduledAt) =>
            '${token}_${uhid}_${scheduledAt.year}-${scheduledAt.month}-${scheduledAt.day}';

        final hubKeys = <String>{};
        for (final item in data) {
          final uhid = item['patientUhid'] as String? ?? '';
          final scheduledAt = DateTime.tryParse(item['scheduledAt'] ?? '') ?? DateTime.now();
          final createdAt = DateTime.tryParse(item['createdAt'] ?? '') ?? DateTime.now();
          final token = item['tokenNumber'] as int? ?? 0;

          // Resolve local patient ID using UHID
          int localPatientId = 0;
          if (uhid.isNotEmpty) {
            final p = ObjectBoxService.instance.patientBox
                .query(Patient_.uhid.equals(uhid))
                .build()
                .findFirst();
            if (p != null) localPatientId = p.id;
          }

          if (localPatientId == 0) {
            debugPrint('SyncService: Warning — Could not resolve local patient for UHID $uhid. Skipping appointment.');
            continue;
          }

          final key = _apptKey(token, uhid, scheduledAt);
          hubKeys.add(key);

          // Find existing by natural key (requires looking up UHID for local patients)
          final existing = allLocal.where((a) {
            final p = ObjectBoxService.instance.patientBox.get(a.patientId);
            if (p == null) return false;
            final lKey = _apptKey(a.tokenNumber, p.uhid, a.scheduledAt);
            return lKey == key;
          }).firstOrNull;

          if (existing != null) {
            existing
              ..patientId = localPatientId
              ..status = item['status'] ?? 'waiting'
              ..consultationFee = (item['consultationFee'] as num?)?.toDouble() ?? 0.0
              ..notes = item['notes'] ?? ''
              ..isWalkIn = item['isWalkIn'] ?? true
              ..consultationBilled = item['consultationBilled'] ?? false
              ..calledAt = item['calledAt'] != null ? DateTime.tryParse(item['calledAt'].toString()) : null
              ..pharmacyAt = item['pharmacyAt'] != null ? DateTime.tryParse(item['pharmacyAt'].toString()) : null
              ..completedAt = item['completedAt'] != null ? DateTime.tryParse(item['completedAt'].toString()) : null;
            box.put(existing);
          } else {
            box.put(Appointment(
              id: 0,
              patientId: localPatientId,
              patientName: item['patientName'] ?? '',
              patientPhone: item['patientPhone'] ?? '',
              doctorId: item['doctorId'] ?? 0,
              doctorName: item['doctorName'] ?? '',
              tokenNumber: token,
              status: item['status'] ?? 'waiting',
              consultationFee: (item['consultationFee'] as num?)?.toDouble() ?? 0.0,
              notes: item['notes'] ?? '',
              scheduledAt: scheduledAt,
              createdAt: createdAt,
              isWalkIn: item['isWalkIn'] ?? true,
              consultationBilled: item['consultationBilled'] ?? false,
            )
              ..calledAt = item['calledAt'] != null ? DateTime.tryParse(item['calledAt'].toString()) : null
              ..pharmacyAt = item['pharmacyAt'] != null ? DateTime.tryParse(item['pharmacyAt'].toString()) : null
              ..completedAt = item['completedAt'] != null ? DateTime.tryParse(item['completedAt'].toString()) : null);
          }
        }
        // Remove appointments deleted on Hub
        for (final a in allLocal) {
          final p = ObjectBoxService.instance.patientBox.get(a.patientId);
          if (p == null) {
             box.remove(a.id);
             continue;
          }
          final key = _apptKey(a.tokenNumber, p.uhid, a.scheduledAt);
          if (!hubKeys.contains(key)) {
            box.remove(a.id);
          }
        }
        debugPrint('SyncService: pullAppointments synced ${data.length} appointments.');
      }
    } catch (e) {
      debugPrint('pullAppointments err: $e');
    }
    debugPrint('SyncService: pullAppointments done.');
  }

  Future<void> pullDoctors() async {
    if (!_isConnected || _jwtToken == null) return;
    debugPrint('SyncService: pullDoctors starting...');
    try {
      final url = Uri.parse('$_baseUrl/api/doctors');
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.doctorBox;
        final allLocal = box.getAll();

        // Natural key: doctor name
        final hubNames = <String>{};
        for (final item in data) {
          final name = item['name'] as String? ?? '';
          hubNames.add(name);
          final createdAt =
              DateTime.tryParse(item['createdAt'] ?? '') ?? DateTime.now();

          final existing = allLocal.where((d) => d.name == name).firstOrNull;
          if (existing != null) {
            existing
              ..name = name
              ..specialization = item['specialization'] ?? 'General'
              ..consultationFee =
                  (item['consultationFee'] as num?)?.toDouble() ?? 0.0
              ..qualifications = item['qualifications'] ?? ''
              ..phone = item['phone'] ?? ''
              ..isActive = item['isActive'] ?? true
              ..createdAt = createdAt;
            box.put(existing);
          } else {
            box.put(Doctor(
              id: 0, // Auto-assign
              name: name,
              specialization: item['specialization'] ?? 'General',
              consultationFee:
                  (item['consultationFee'] as num?)?.toDouble() ?? 0.0,
              qualifications: item['qualifications'] ?? '',
              phone: item['phone'] ?? '',
              isActive: item['isActive'] ?? true,
              createdAt: createdAt,
            ));
          }
        }
        // Remove doctors deleted on Hub
        for (final d in allLocal) {
          if (!hubNames.contains(d.name)) {
            box.remove(d.id);
          }
        }
        debugPrint('SyncService: pullDoctors synced ${data.length} doctors.');
      }
    } catch (e) {
      debugPrint('pullDoctors err: $e');
    }
    debugPrint('SyncService: pullDoctors done.');
  }

  Future<void> pullProcedures() async {
    if (!_isConnected || _jwtToken == null) return;
    debugPrint('SyncService: pullProcedures starting...');
    try {
      final url = Uri.parse('$_baseUrl/api/procedures');
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.procedureBox;
        final allLocal = box.getAll();

        final hubNames = <String>{};
        for (final item in data) {
          final name = item['name'] as String? ?? '';
          hubNames.add(name);

          final existing = allLocal.where((p) => p.name == name).firstOrNull;
          final p = Procedure.fromJson(item as Map<String, dynamic>);
          if (existing != null) {
            p.id = existing.id;
          } else {
            p.id = 0;
          }
          box.put(p);
        }
        // Cleanup phase
        for (final p in allLocal) {
          if (!hubNames.contains(p.name)) {
            box.remove(p.id);
          }
        }
        debugPrint(
            'SyncService: pullProcedures synced ${data.length} procedures.');
      }
    } catch (e) {
      debugPrint('pullProcedures err: $e');
    }
  }

  Future<void> pullPrescriptions({String? since}) async {
    if (!_isConnected || _jwtToken == null) return;
    debugPrint('SyncService: pullPrescriptions starting (since=$since)...');
    try {
      var url = Uri.parse('$_baseUrl/api/prescriptions');
      if (since != null) {
        url = url.replace(queryParameters: {'since': since});
      }
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.prescriptionBox;
        final allLocal = box.getAll();

        // Natural key: patientUhid + createdAt date
        String _pKey(String uhid, DateTime dt) =>
            '${uhid}_${dt.year}-${dt.month}-${dt.day}';

        final hubKeys = <String>{};
        for (final item in data) {
          final uhid = item['patientUhid'] as String? ?? '';
          final token = item['tokenNumber'] as int? ?? 0;
          final createdAt = DateTime.tryParse(item['createdAt'] ?? '') ?? DateTime.now();
          final patientName = item['patientName'] ?? '';

          // Resolve local patient ID using UHID
          int localPatientId = 0;
          if (uhid.isNotEmpty) {
            final p = ObjectBoxService.instance.patientBox
                .query(Patient_.uhid.equals(uhid))
                .build()
                .findFirst();
            if (p != null) localPatientId = p.id;
          }

          // Resolve local appointment ID using tokenNumber and date
          int localApptId = 0;
          if (token > 0) {
            final appt = ObjectBoxService.instance.appointmentBox
                .getAll()
                .where((a) =>
                    a.tokenNumber == token &&
                    a.scheduledAt.year == createdAt.year &&
                    a.scheduledAt.month == createdAt.month &&
                    a.scheduledAt.day == createdAt.day)
                .firstOrNull;
            if (appt != null) localApptId = appt.id;
          }

          final key = _pKey(uhid, createdAt);
          hubKeys.add(key);

          final existing = allLocal.where((p) {
            if (p.patientId <= 0) return false;
            final patient = ObjectBoxService.instance.patientBox.get(p.patientId);
            if (patient == null) return false;
            final lKey = _pKey(patient.uhid, p.createdAt);
            return lKey == key;
          }).firstOrNull;

          if (existing != null) {
            existing
              ..appointmentId = localApptId > 0 ? localApptId : existing.appointmentId
              ..patientId = localPatientId > 0 ? localPatientId : existing.patientId
              ..diagnosis = item['diagnosis'] ?? ''
              ..complaints = item['complaints'] ?? ''
              ..notes = item['notes'] ?? ''
              ..itemsJson = item['itemsJson'] ?? '[]'
              ..labTestsJson = item['labTestsJson'] ?? '[]'
              ..imagesJson = item['imagesJson'] ?? '[]'
              ..proceduresJson = item['proceduresJson'] ?? '[]'
              ..vitalsJson = item['vitalsJson'] ?? '{}'
              ..dispensed = item['dispensed'] ?? false;
            box.put(existing);
          } else {
            box.put(Prescription(
              id: 0,
              appointmentId: localApptId,
              patientId: localPatientId,
              patientName: patientName,
              doctorId: item['doctorId'] ?? 0,
              doctorName: item['doctorName'] ?? '',
              diagnosis: item['diagnosis'] ?? '',
              complaints: item['complaints'] ?? '',
              notes: item['notes'] ?? '',
              itemsJson: item['itemsJson'] ?? '[]',
              labTestsJson: item['labTestsJson'] ?? '[]',
              vitalsJson: item['vitalsJson'] ?? '{}',
              imagesJson: item['imagesJson'] ?? '[]',
              proceduresJson: item['proceduresJson'] ?? '[]',
              dispensed: item['dispensed'] ?? false,
              createdAt: createdAt,
            ));
          }
        }
        // Remove prescriptions deleted on Hub (Full Sync only)
        if (since == null) {
          for (final p in allLocal) {
            if (p.patientId <= 0) {
              box.remove(p.id);
              continue;
            }
            final patient = ObjectBoxService.instance.patientBox.get(p.patientId);
            if (patient == null) {
              box.remove(p.id);
              continue;
            }
            final key = _pKey(patient.uhid, p.createdAt);
            if (!hubKeys.contains(key)) {
              box.remove(p.id);
            }
          }
        }
        debugPrint('SyncService: pullPrescriptions synced ${data.length} prescriptions.');
      }
    } catch (e) {
      debugPrint('pullPrescriptions err: $e');
    }
    debugPrint('SyncService: pullPrescriptions done.');
  }

  Future<int?> pullSales({String? since}) async {
    if (!_isConnected || _jwtToken == null) {
      debugPrint('SyncService: pullSales aborted (isConnected: $_isConnected, jwt: $_jwtToken)');
      return null;
    }
    debugPrint('SyncService: pullSales starting (since=$since)...');
    try {
      var url = Uri.parse('$_baseUrl/api/sales');
      if (since != null) {
        url = url.replace(queryParameters: {'since': since});
      }
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.saleBox;
        final allLocal = box.getAll();

        // Natural key: invoiceNo (globally unique across all devices)
        final hubInvoiceNos = <String>{};
        for (final item in data) {
          final invoiceNo = item['invoiceNo'] as String? ?? '';
          if (invoiceNo.isEmpty) continue;
          hubInvoiceNos.add(invoiceNo);
          final createdAt =
              DateTime.tryParse(item['createdAt'] ?? '') ?? DateTime.now();

          final existing = allLocal
              .where((s) =>
                  s.invoiceNo == invoiceNo &&
                  s.createdAt.millisecondsSinceEpoch == createdAt.millisecondsSinceEpoch)
              .firstOrNull;

          // Resolve local patient ID using UHID or fallback to Name/Phone
          int localPatientId = 0;
          final uhid = item['patientUhid'] as String? ?? '';
          if (uhid.isNotEmpty) {
            final p = ObjectBoxService.instance.patientBox
                .query(Patient_.uhid.equals(uhid))
                .build()
                .findFirst();
            if (p != null) localPatientId = p.id;
          }
          if (localPatientId == 0) {
            final pName = item['patientName'] as String? ?? '';
            final pPhone = item['patientPhone'] as String? ?? '';
            if (pName.isNotEmpty) {
              final match = ObjectBoxService.instance.patientBox
                  .getAll()
                  .where((p) {
                    final nMatch = p.name.trim().toLowerCase() == pName.trim().toLowerCase();
                    final phMatch = pPhone.isNotEmpty && p.phone.trim() == pPhone.trim();
                    return nMatch && (pPhone.isEmpty || phMatch);
                  }).firstOrNull;
              if (match != null) localPatientId = match.id;
            }
          }

          if (existing != null) {
            existing
              ..invoiceNo = invoiceNo
              ..patientId = localPatientId > 0 ? localPatientId : (item['patientId'] ?? 0)
              ..patientName = item['patientName'] ?? ''
              ..patientPhone = item['patientPhone'] ?? ''
              ..patientUhid = uhid
              ..subtotal = (item['subtotal'] as num?)?.toDouble() ?? 0
              ..discount = (item['discount'] as num?)?.toDouble() ?? 0
              ..taxRate = (item['taxRate'] as num?)?.toDouble() ?? 0
              ..taxAmount = (item['taxAmount'] as num?)?.toDouble() ?? 0
              ..total = (item['total'] as num?)?.toDouble() ?? 0
              ..paymentMethod = item['paymentMethod'] ?? 'cash'
              ..cashAmount = (item['cashAmount'] as num?)?.toDouble() ?? 0
              ..upiAmount = (item['upiAmount'] as num?)?.toDouble() ?? 0
              ..cardAmount = (item['cardAmount'] as num?)?.toDouble() ?? 0
              ..createdAt = createdAt
              ..updatedAt = DateTime.tryParse(item['updatedAt'] ?? '') ?? createdAt
              ..synced = true
              ..isReturn = item['isReturn'] ?? false
              ..isClinicalDispense = item['isClinicalDispense'] ?? false
              ..linkedAppointmentId = item['linkedAppointmentId'] ?? 0
              ..linkedProcedureId = item['linkedProcedureId'] ?? 0
              ..itemsJson = item['itemsJson'] ?? '[]';
            box.put(existing);
          } else {
            box.put(Sale(
              id: 0, // Auto-assign — never force Hub IDs
              invoiceNo: invoiceNo,
              patientId: localPatientId > 0 ? localPatientId : (item['patientId'] ?? 0),
              patientName: item['patientName'] ?? '',
              patientPhone: item['patientPhone'] ?? '',
              patientUhid: uhid,
              subtotal: (item['subtotal'] as num?)?.toDouble() ?? 0,
              discount: (item['discount'] as num?)?.toDouble() ?? 0,
              taxRate: (item['taxRate'] as num?)?.toDouble() ?? 0,
              taxAmount: (item['taxAmount'] as num?)?.toDouble() ?? 0,
              total: (item['total'] as num?)?.toDouble() ?? 0,
              paymentMethod: item['paymentMethod'] ?? 'cash',
              cashAmount: (item['cashAmount'] as num?)?.toDouble() ?? 0,
              upiAmount: (item['upiAmount'] as num?)?.toDouble() ?? 0,
              cardAmount: (item['cardAmount'] as num?)?.toDouble() ?? 0,
              createdAt: createdAt,
              updatedAt: DateTime.tryParse(item['updatedAt'] ?? '') ?? createdAt,
              synced: true,
              isReturn: item['isReturn'] ?? false,
              isClinicalDispense: item['isClinicalDispense'] ?? false,
              linkedAppointmentId: item['linkedAppointmentId'] ?? 0,
              linkedProcedureId: item['linkedProcedureId'] ?? 0,
              itemsJson: item['itemsJson'] ?? '[]',
            ));
          }
        }
        // Remove sales voided on Hub (only remove synced=true sales not in Hub, Full Sync only)
        if (since == null) {
          for (final s in allLocal) {
            if (s.synced &&
                s.invoiceNo.isNotEmpty &&
                !hubInvoiceNos.contains(s.invoiceNo)) {
              box.remove(s.id);
            }
          }
        }
        debugPrint('SyncService: pullSales synced ${data.length} sales.');
        return jsonDecode(res.body)['serverTime'] as int?;
      }
    } catch (e) {
      debugPrint('pullSales err: $e');
    }
    debugPrint('SyncService: pullSales done.');
    return null;
  }

  Future<void> pullH1Records({String? since}) async {
    if (!_isConnected || _jwtToken == null) return;
    debugPrint('SyncService: pullH1Records starting (since=$since)...');
    try {
      var url = Uri.parse('$_baseUrl/api/h1-records');
      if (since != null) {
        url = url.replace(queryParameters: {'since': since});
      }
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.store.box<ScheduleH1Record>();
        final allLocal = box.getAll();

        final hubKeys = <String>{};
        for (final item in data) {
          final invoiceNo = item['invoiceNo'] as String? ?? '';
          final medicineName = item['medicineName'] as String? ?? '';
          final batchNo = item['batchNo'] as String? ?? '';
          final key = '${invoiceNo}_${medicineName}_$batchNo';
          hubKeys.add(key);

          final existing = allLocal.where((x) =>
              x.invoiceNo == invoiceNo &&
              x.medicineName == medicineName &&
              x.batchNo == batchNo).firstOrNull;

          if (existing != null) {
            final rec = ScheduleH1Record.fromJson(item as Map<String, dynamic>);
            rec.id = existing.id;
            box.put(rec);
          } else {
            final rec = ScheduleH1Record.fromJson(item as Map<String, dynamic>);
            rec.id = 0;
            box.put(rec);
          }
        }
        debugPrint('SyncService: pullH1Records synced ${data.length} records.');
      }
    } catch (e) {
      debugPrint('pullH1Records err: $e');
    }
  }

  Future<void> pullTransfers() async {
    if (!_isConnected || _jwtToken == null) return;
    debugPrint('SyncService: pullTransfers starting...');
    try {
      final url = Uri.parse('$_baseUrl/api/transfers');
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.transferBox;

        for (final item in data) {
          final existing = box.get(item['id'] ?? 0);
          final serverTime =
              DateTime.tryParse(item['transferredAt'] ?? '') ?? DateTime.now();
          if (existing == null) {
            box.put(StockTransfer(
              medicineId: item['medicineId'],
              medicineName: item['medicineName'],
              qty: item['qty'],
              fromWarehouse: item['fromWarehouse'],
              toWarehouse: item['toWarehouse'],
              transferredAt: serverTime,
              note: item['note'] ?? '',
              transferredBy: item['transferredBy'] ?? '',
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('pullTransfers err: $e');
    }
    debugPrint('SyncService: pullTransfers done.');
  }

  // ─── Prescription Templates ───────────────────────────────────────────────

  Future<void> pullTemplates() async {
    if (!_isConnected || _jwtToken == null) return;
    debugPrint('SyncService: pullTemplates starting...');
    try {
      final url = Uri.parse('$_baseUrl/api/templates');
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.templateBox;
        final allLocal = box.getAll();
        final hubNames = <String>{};
        for (final item in data) {
          final name = item['name'] as String? ?? '';
          if (name.isEmpty) continue;
          hubNames.add(name);
          final createdAt =
              DateTime.tryParse(item['createdAt'] ?? '') ?? DateTime.now();

          final existing = allLocal.where((t) => t.name == name).firstOrNull;
          if (existing != null) {
            existing
              ..diagnosis = item['diagnosis'] ?? ''
              ..complaints = item['complaints'] ?? ''
              ..notes = item['notes'] ?? ''
              ..itemsJson = item['itemsJson'] ?? '[]'
              ..labTestsJson = item['labTestsJson'] ?? '[]'
              ..doctorId = item['doctorId'] ?? 0
              ..createdAt = createdAt;
            box.put(existing);
          } else {
            box.put(PrescriptionTemplate(
              id: 0,
              name: name,
              diagnosis: item['diagnosis'] ?? '',
              complaints: item['complaints'] ?? '',
              notes: item['notes'] ?? '',
              itemsJson: item['itemsJson'] ?? '[]',
              labTestsJson: item['labTestsJson'] ?? '[]',
              doctorId: item['doctorId'] ?? 0,
              createdAt: createdAt,
            ));
          }
        }
        for (final t in allLocal) {
          if (!hubNames.contains(t.name)) box.remove(t.id);
        }
        debugPrint('SyncService: pullTemplates synced ${data.length} records.');
      }
    } catch (e) {
      debugPrint('pullTemplates err: $e');
    }
    debugPrint('SyncService: pullTemplates done.');
  }

  Future<bool> pushTemplate(PrescriptionTemplate t) async {
    return await _unifiedPush('/api/templates/push', t.toJson(),
        entity: 'template', action: 'create');
  }

  // ─── Patient Photos (lazy, per-patient) ───────────────────────────────────────────────────────

  /// Fetch photos for a specific patient (by UHID) on demand — called when
  /// the Gallery tab opens, NOT at login. Returns the list of local paths.
  /// patientLocalId = Android's local ObjectBox ID for this patient.
  Future<List<PatientImage>> pullPatientPhotosForPatient(
    String uhid,
    int patientLocalId,
  ) async {
    if (!_isConnected || _jwtToken == null) return [];
    debugPrint('SyncService: pullPatientPhotosForPatient($uhid) starting...');
    final newPhotos = <PatientImage>[];
    try {
      final url = Uri.parse('$_baseUrl/api/patient-photos')
          .replace(queryParameters: {'uhid': uhid});
      final res = await http
          .get(url, headers: _authHeaders())
          .timeout(const Duration(seconds: 60));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.patientImageBox;
        final allLocal = box.getAll();
        final appDocDir = await getApplicationDocumentsDirectory();

        for (final item in data) {
          final filename = item['filename'] as String? ?? '';
          final category = item['category'] as String? ?? 'General';
          final date = DateTime.tryParse(item['date'] ?? '') ?? DateTime.now();
          final imageData = item['imageData'] as String? ?? '';
          if (filename.isEmpty || imageData.isEmpty) continue;

          // Skip if already downloaded for this patient
          final alreadyExists = allLocal.any((p) =>
              p.patientId == patientLocalId &&
              p.imagePath.endsWith(filename) &&
              File(p.imagePath).existsSync());
          if (alreadyExists) continue;

          // Save image bytes
          final photoDir =
              Directory('${appDocDir.path}/patient_photos/$patientLocalId');
          if (!await photoDir.exists()) {
            await photoDir.create(recursive: true);
          }
          final savedPath = '${photoDir.path}/$filename';
          await File(savedPath).writeAsBytes(base64Decode(imageData));

          final pImage = PatientImage(
            id: 0,
            patientId: patientLocalId, // ← use Android's local ID, not Hub's
            imagePath: savedPath,
            category: category,
            date: date,
          );
          box.put(pImage);
          newPhotos.add(pImage);
        }
        debugPrint(
            'SyncService: pullPatientPhotosForPatient($uhid) — ${newPhotos.length} new photos.');
      }
    } catch (e) {
      debugPrint('pullPatientPhotosForPatient err: $e');
    }
    return newPhotos;
  }

  Future<bool> pushPatientPhoto(PatientImage photo, String patientUhid) async {
    final file = File(photo.imagePath);
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    final base64Data = base64Encode(bytes);
    final filename = photo.imagePath.replaceAll('\\', '/').split('/').last;
    final data = {
      'patientUhid': patientUhid,
      'category': photo.category,
      'date': photo.date.toIso8601String(),
      'filename': filename,
      'imageData': base64Data,
    };

    // Images are NOT synced via Firebase as per policy
    return await _unifiedPush('/api/patient-photos/push', data);
  }

  Future<bool> pushSale(Sale sale) async {
    final ok = await _unifiedPush('/api/sales/push', sale.toJson(),
        entity: 'sale', action: 'create');
    if (ok) {
      sale.synced = true;
      ObjectBoxService.instance.saleBox.put(sale);
      notifyListeners();
    }
    return ok;
  }

  Future<bool> pushH1Record(ScheduleH1Record r) async {
    return await _unifiedPush('/api/h1-records/push', r.toJson(),
        entity: 'h1_record', action: 'create');
  }

  Future<bool> pushPatient(Patient p) async {
    return await _unifiedPush('/api/patients/push', p.toJson(),
        entity: 'patient', action: 'create');
  }

  Future<bool> pushAuditLog(AuditLog l) async {
    return await _unifiedPush('/api/audit/push', l.toJson(),
        entity: 'audit_log', action: 'create');
  }

  Future<bool> pushAppointment(Appointment a) async {
    return await _unifiedPush('/api/appointments/push', a.toJson(),
        entity: 'appointment', action: 'create');
  }

  Future<bool> pushDoctor(Doctor d) async {
    return await _unifiedPush('/api/doctors/push', d.toJson(),
        entity: 'doctor', action: 'create');
  }

  Future<bool> pushDoctorDelete(int id) async {
    return await _unifiedPush('/api/doctors/delete', {'id': id},
        entity: 'doctor', action: 'delete');
  }

  Future<bool> pushPatientDelete(String uhid) async {
    return await _unifiedPush('/api/patients/delete', {'uhid': uhid},
        entity: 'patient', action: 'delete');
  }

  Future<bool> pushMedicineDelete(String barcode, String name) async {
    return await _unifiedPush(
        '/api/medicines/delete', {'barcode': barcode, 'name': name},
        entity: 'medicine', action: 'delete');
  }

  Future<bool> pushPrescriptionDelete(int id) async {
    // Prescriptions are tricky, keep ID for now or find better natural key
    return await _unifiedPush('/api/prescriptions/delete', {'id': id},
        entity: 'prescription', action: 'delete');
  }

  Future<bool> pushSaleDelete(String invoiceNo) async {
    return await _unifiedPush('/api/sales/delete', {'invoiceNo': invoiceNo},
        entity: 'sale', action: 'delete');
  }

  Future<String?> uploadPrescriptionPhoto(String localPath) async {
    final file = File(localPath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final base64Data = base64Encode(bytes);
    final filename = localPath.replaceAll('\\', '/').split('/').last;

    final data = {
      'filename': filename,
      'imageData': base64Data,
    };

    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/prescriptions/photos/push'),
            headers: _authHeaders(),
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body['path'] as String?; // Hub's local path
      }
    } catch (_) {}
    return null;
  }

  Future<bool> pushPrescription(Prescription p) async {
    final body = p.toJson();

    // Add patientUhid and tokenNumber for ID resolution on Hub
    try {
      final patient = ObjectBoxService.instance.patientBox.get(p.patientId);
      if (patient != null) {
        body['patientUhid'] = patient.uhid;
      }
      final appt = ObjectBoxService.instance.appointmentBox.get(p.appointmentId);
      if (appt != null) {
        body['tokenNumber'] = appt.tokenNumber;
      }
    } catch (e) {
      debugPrint('SyncService: Error fetching patient/appointment for prescription push: $e');
    }

    // If we have images, upload them to Hub first
    try {
      final images = jsonDecode(p.imagesJson) as List;
      if (images.isNotEmpty) {
        final newPaths = <String>[];
        for (final path in images) {
          final pathStr = path.toString();
          // If it's already a Hub path or doesn't exist locally, skip upload
          if (pathStr.contains('prescription_photos') ||
              !File(pathStr).existsSync()) {
            newPaths.add(pathStr);
          } else {
            final hubPath = await uploadPrescriptionPhoto(pathStr);
            newPaths.add(hubPath ?? pathStr);
          }
        }
        body['imagesJson'] = jsonEncode(newPaths);
      }
    } catch (e) {
      debugPrint('SyncService: pushPrescription image upload err: $e');
    }

    return await _unifiedPush('/api/prescriptions/push', body,
        entity: 'prescription', action: 'create');
  }

  Future<bool> pushTransfer(StockTransfer t) async {
    return await _unifiedPush('/api/transfers/push', t.toJson(),
        entity: 'transfer', action: 'create');
  }

  Future<bool> pushProcedure(Procedure p) async {
    return await _unifiedPush('/api/procedures/push', p.toJson(),
        entity: 'procedure', action: 'create');
  }

  Future<bool> pushProcedureDelete(String name) async {
    return await _unifiedPush('/api/procedures/delete', {'name': name},
        entity: 'procedure', action: 'delete');
  }

  Future<bool> pushMedicine(Medicine m) async {
    return await _unifiedPush('/api/medicines/push', m.toJson(),
        entity: 'medicine', action: 'create');
  }

  void disconnect() {
    _isConnected = false;
    _hubIp = null;
    _jwtToken = null;
    _connectedRole = null;
    _isCloudMode = false;

    // Clear persisted IP
    final settings = ObjectBoxService.instance.settings;
    settings.hubIp = null;
    ObjectBoxService.instance.settingsBox.put(settings);

    notifyListeners();
  }

  Map<String, String> _authHeaders() {
    final settings = ObjectBoxService.instance.settings;
    return {
      'Content-Type': 'application/json',
      if (_jwtToken != null) 'Authorization': 'Bearer $_jwtToken',
      'X-MediPass-Secret': settings.jwtSecret,
    };
  }

  Future<bool> _unifiedPush(String endpoint, Map<String, dynamic> data,
      {String? entity, String? action}) async {
    final settings = ObjectBoxService.instance.settings;
    final mode = settings.connectionMode;

    // 1. Local WiFi (Tier 1)
    if ((mode == 'auto' || mode == 'local') && !_isCloudMode) {
      if (_isConnected && _hubIp != null && !_hubIp!.startsWith('http')) {
        try {
          final res = await http
              .post(
                Uri.parse('http://$_hubIp:8080$endpoint'),
                body: jsonEncode(data),
                headers: _authHeaders(),
              )
              .timeout(const Duration(seconds: 3));
          if (res.statusCode == 200) return true;
        } catch (_) {}
      }
    }

    // 2. Cloudflare Tunnel (Tier 2)
    if ((mode == 'auto' || mode == 'cloudflare') && !_isCloudMode) {
      final url = settings.cloudflareUrl.isNotEmpty 
          ? settings.cloudflareUrl 
          : (_hubIp != null && _hubIp!.startsWith('http') ? _hubIp : null);
          
      if (url != null) {
        try {
          final res = await http
              .post(
                Uri.parse('$url$endpoint'),
                body: jsonEncode(data),
                headers: _authHeaders(),
              )
              .timeout(const Duration(seconds: 7));
          if (res.statusCode == 200) return true;
        } catch (_) {}
      }
    }

    // 3. Firebase Delta Sync (Tier 3 - Fallback)
    final sub = SubscriptionService.instance;
    if ((_isCloudMode || mode == 'auto' || mode == 'firebase') && 
        settings.firebaseEnabled && sub.isPro && entity != null && action != null) {
      try {
        return await FirebaseSyncService.instance.pushDelta(
          entity: entity,
          action: action,
          data: data,
        );
      } catch (e) {
        debugPrint('SyncService: Firebase Fallback failed: $e');
      }
    }

    return false;
  }

  Future<void> pullSettings() async {
    if (!_isConnected || _jwtToken == null) return;
    try {
      final url = Uri.parse('$_baseUrl/api/settings');
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final box = ObjectBoxService.instance.settingsBox;
        final current = ObjectBoxService.instance.settings;
        
        final updated = AppSettings.fromJson(data);
        updated.id = current.id;
        // Keep local-only and device-specific settings
        updated.isWindowsClient = current.isWindowsClient;
        updated.deviceId = current.deviceId;
        updated.hubIp = current.hubIp;
        updated.autoLoginPin = current.autoLoginPin;
        updated.autoLoginName = current.autoLoginName;
        updated.serverPort = current.serverPort;
        updated.jwtSecret = current.jwtSecret;
        updated.defaultPrinterName = current.defaultPrinterName;
        updated.autoPrintReceipt = current.autoPrintReceipt;
        updated.receiptPaperSize = current.receiptPaperSize;

        box.put(updated);

        // Sync license/activation key from Hub
        if (data['licenseKey'] != null) {
          final hubLicenseKey = data['licenseKey'] as String;
          final hubTier = data['licenseTier'] as String? ?? 'free';
          final hubExpiryMs = data['licenseExpiry'] as int?;
          
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('licenseKey', hubLicenseKey);
          await prefs.setString('licenseTier', hubTier);
          if (hubExpiryMs != null) {
            await prefs.setInt('licenseExpiry', hubExpiryMs);
          } else {
            await prefs.remove('licenseExpiry');
          }
          await SubscriptionService.instance.init();
          debugPrint('SyncService: Synced license key from Hub REST API: $hubLicenseKey');
        }

        notifyListeners();
        debugPrint('SyncService: pullSettings completed.');
      }
    } catch (e) {
      debugPrint('SyncService: pullSettings err: $e');
    }
  }

  Future<void> pullAuditLogs({String? since}) async {
    if (!_isConnected || _jwtToken == null) return;
    debugPrint('SyncService: pullAuditLogs starting (since=$since)...');
    try {
      var url = Uri.parse('$_baseUrl/api/audit');
      if (since != null) {
        url = url.replace(queryParameters: {'since': since});
      }
      final res = await http.get(url, headers: _authHeaders());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] as List;
        final box = ObjectBoxService.instance.store.box<AuditLog>();
        final allLocal = box.getAll();

        for (final item in data) {
          final deviceId = item['deviceId'] as String? ?? '';
          final timestampMs = item['timestamp'] as int? ?? 0;

          final existing = allLocal.where((l) =>
              l.deviceId == deviceId &&
              l.timestamp.millisecondsSinceEpoch == timestampMs).firstOrNull;

          if (existing == null) {
            final log = AuditLog.fromJson(item as Map<String, dynamic>);
            log.id = 0;
            log.isSynced = true;
            box.put(log);
          }
        }
        debugPrint('SyncService: pullAuditLogs synced ${data.length} logs.');
      }
    } catch (e) {
      debugPrint('pullAuditLogs err: $e');
    }
  }

  Future<bool> pushUser(AppUser user) async {
    return await _unifiedPush('/api/users/push', user.toJson(),
        entity: 'user', action: 'update');
  }

  Future<bool> pushSettings(AppSettings settings) async {
    return await _unifiedPush('/api/settings/push', settings.toJson(),
        entity: 'settings', action: 'update');
  }

  Future<bool> pushTemplateDelete(String name) async {
    return await _unifiedPush('/api/templates/delete', {'name': name},
        entity: 'template', action: 'delete');
  }

  Future<bool> pushPatientPhotoDelete(String uhid, String fileName) async {
    if (!_isConnected || _jwtToken == null) return false;
    try {
      final url = Uri.parse('$_baseUrl/api/patients/photos/delete');
      final body = jsonEncode({'uhid': uhid, 'fileName': fileName});
      final res = await http.post(url, headers: _authHeaders(), body: body);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('SyncService: pushPatientPhotoDelete err: $e');
      return false;
    }
  }

  Future<bool> syncEntity(String entity, Map<String, dynamic> data) async {
    return await _unifiedPush('/api/$entity/push', data,
        entity: entity.toLowerCase(), action: 'create');
  }
  // --- Firestore Real-time Sync (Monetization & Stable Outbox Upgrade) ---
  final List<StreamSubscription> _firestoreSubscriptions = [];

  void initializeFirestoreRealTimeSync() {
    final settings = ObjectBoxService.instance.settings;
    debugPrint('SyncService: initializeFirestoreRealTimeSync called. isHub: $isHub, _isCloudMode: $_isCloudMode, firebaseEnabled: ${settings.firebaseEnabled}');
    if (isHub) {
      debugPrint('SyncService: initializeFirestoreRealTimeSync returned early because this device is a Hub.');
      return;
    }
    if (!_isCloudMode) {
      debugPrint('SyncService: initializeFirestoreRealTimeSync returned early because _isCloudMode is false.');
      return;
    }
    if (!settings.firebaseEnabled) {
      debugPrint('SyncService: initializeFirestoreRealTimeSync returned early because firebaseEnabled is false.');
      return;
    }

    cancelFirestoreRealTimeSync();
    debugPrint('SyncService: Initializing real-time Firestore sync listeners (LWW)...');

    _subscribeToFirestoreEntity('medicines', (data) => _syncMedicineLWW(data));
    _subscribeToFirestoreEntity('patients', (data) => _syncPatientLWW(data));
    _subscribeToFirestoreEntity('doctors', (data) => _syncDoctorLWW(data));
    _subscribeToFirestoreEntity('appointments', (data) => _syncAppointmentLWW(data));
    _subscribeToFirestoreEntity('prescriptions', (data) => _syncPrescriptionLWW(data));
    _subscribeToFirestoreEntity('templates', (data) => _syncTemplateLWW(data));
    _subscribeToFirestoreEntity('procedures', (data) => _syncProcedureLWW(data));
    _subscribeToFirestoreEntity('sales', (data) => _syncSaleLWW(data));
  }

  void _subscribeToFirestoreEntity(String entity, Function(Map<String, dynamic>) handler) {
    debugPrint('SyncService: Subscribing to Firestore entity "$entity"');
    final sub = FirebaseSyncService.instance.startGlobalUpdateListener(entity, (data) {
      try {
        debugPrint('SyncService: Real-time Firestore update trigger received for "$entity"');
        handler(data);
      } catch (e) {
        debugPrint('SyncService: Error in real-time update handler for $entity: $e');
      }
    });
    if (sub != null) {
      _firestoreSubscriptions.add(sub);
      debugPrint('SyncService: Added subscription for "$entity" successfully. Total active: ${_firestoreSubscriptions.length}');
    } else {
      debugPrint('SyncService: startGlobalUpdateListener returned null subscription for "$entity".');
    }
  }

  void cancelFirestoreRealTimeSync() {
    if (_firestoreSubscriptions.isNotEmpty) {
      debugPrint('SyncService: Cancelling ${_firestoreSubscriptions.length} active Firestore subscriptions.');
      for (var sub in _firestoreSubscriptions) {
        sub.cancel();
      }
      _firestoreSubscriptions.clear();
    }
  }

  void _syncMedicineLWW(Map<String, dynamic> data) {
    final remote = Medicine.fromJson(data);
    final box = ObjectBoxService.instance.medicineBox;
    final matches = box.getAll().where((m) {
      final matchesBarcode = remote.barcode.isNotEmpty && m.barcode.trim() == remote.barcode;
      final matchesName = m.name.trim().toLowerCase() == remote.name.toLowerCase();
      return matchesBarcode || matchesName;
    }).toList();

    if (matches.isNotEmpty) {
      final local = matches.first;
      if (remote.updatedAt.isAfter(local.updatedAt)) {
        debugPrint('SyncService [LWW]: Updating medicine ${remote.name} (Remote is newer: ${remote.updatedAt} > ${local.updatedAt})');
        remote.id = local.id;
        box.put(remote);
        notifyListeners();
      }
    } else {
      debugPrint('SyncService [LWW]: Creating new medicine ${remote.name}');
      remote.id = 0;
      box.put(remote);
      notifyListeners();
    }
  }

  void _syncPatientLWW(Map<String, dynamic> data) {
    final remote = Patient.fromJson(data);
    final box = ObjectBoxService.instance.patientBox;
    final local = box.query(Patient_.uhid.equals(remote.uhid)).build().findFirst();

    if (local != null) {
      if (remote.updatedAt.isAfter(local.updatedAt)) {
        debugPrint('SyncService [LWW]: Updating patient ${remote.name} (Remote is newer: ${remote.updatedAt} > ${local.updatedAt})');
        remote.id = local.id;
        box.put(remote);
        notifyListeners();
      }
    } else {
      debugPrint('SyncService [LWW]: Creating new patient ${remote.name}');
      remote.id = 0;
      box.put(remote);
      notifyListeners();
    }
  }

  void _syncDoctorLWW(Map<String, dynamic> data) {
    final remote = Doctor.fromJson(data);
    final box = ObjectBoxService.instance.doctorBox;
    final local = box.getAll().where((d) => d.name == remote.name).firstOrNull;

    if (local != null) {
      if (remote.createdAt.isAfter(local.createdAt)) { // Using createdAt as fallback if no updatedAt
        debugPrint('SyncService [LWW]: Updating doctor ${remote.name}');
        remote.id = local.id;
        box.put(remote);
        notifyListeners();
      }
    } else {
      debugPrint('SyncService [LWW]: Creating new doctor ${remote.name}');
      remote.id = 0;
      box.put(remote);
      notifyListeners();
    }
  }

  void _syncAppointmentLWW(Map<String, dynamic> data) {
    final remote = Appointment.fromJson(data);
    final box = ObjectBoxService.instance.appointmentBox;
    final allLocal = box.getAll();
    final uhid = data['patientUhid'] as String? ?? '';

    // Resolve local patient ID using UHID
    int localPatientId = 0;
    if (uhid.isNotEmpty) {
      final p = ObjectBoxService.instance.patientBox
          .query(Patient_.uhid.equals(uhid))
          .build()
          .findFirst();
      if (p != null) localPatientId = p.id;
    }
    if (localPatientId == 0) return; // Skip if patient not present locally yet
    remote.patientId = localPatientId;

    // Resolve local doctor ID
    int localDoctorId = 0;
    if (remote.doctorName.isNotEmpty) {
      final d = ObjectBoxService.instance.doctorBox
          .getAll()
          .where((d) => d.name.toLowerCase() == remote.doctorName.toLowerCase())
          .firstOrNull;
      if (d != null) localDoctorId = d.id;
    }
    remote.doctorId = localDoctorId;

    final existing = allLocal.where((x) {
      final p = ObjectBoxService.instance.patientBox.get(x.patientId);
      if (p == null) return false;
      return x.tokenNumber == remote.tokenNumber &&
          p.uhid == uhid &&
          x.scheduledAt.year == remote.scheduledAt.year &&
          x.scheduledAt.month == remote.scheduledAt.month &&
          x.scheduledAt.day == remote.scheduledAt.day;
    }).firstOrNull;

    if (existing != null) {
      if (remote.createdAt.isAfter(existing.createdAt)) {
        remote.id = existing.id;
        box.put(remote);
        notifyListeners();
      }
    } else {
      remote.id = 0;
      box.put(remote);
      notifyListeners();
    }
  }

  void _syncPrescriptionLWW(Map<String, dynamic> data) {
    final remote = Prescription.fromJson(data);
    final box = ObjectBoxService.instance.prescriptionBox;
    final uhid = data['patientUhid'] as String? ?? '';
    final token = data['tokenNumber'] as int? ?? 0;

    // Resolve local patient ID using UHID
    int localPatientId = 0;
    if (uhid.isNotEmpty) {
      final p = ObjectBoxService.instance.patientBox
          .query(Patient_.uhid.equals(uhid))
          .build()
          .findFirst();
      if (p != null) localPatientId = p.id;
    }
    if (localPatientId == 0) return; // Skip if patient not present locally yet
    remote.patientId = localPatientId;

    // Resolve local appointment ID using token and date
    int localApptId = 0;
    if (token > 0) {
      final appt = ObjectBoxService.instance.appointmentBox
          .getAll()
          .where((a) =>
              a.tokenNumber == token &&
              a.scheduledAt.year == remote.createdAt.year &&
              a.scheduledAt.month == remote.createdAt.month &&
              a.scheduledAt.day == remote.createdAt.day)
          .firstOrNull;
      if (appt != null) localApptId = appt.id;
    }
    remote.appointmentId = localApptId;

    // Resolve local doctor ID
    int localDoctorId = 0;
    if (remote.doctorName.isNotEmpty) {
      final d = ObjectBoxService.instance.doctorBox
          .getAll()
          .where((d) => d.name.toLowerCase() == remote.doctorName.toLowerCase())
          .firstOrNull;
      if (d != null) localDoctorId = d.id;
    }
    remote.doctorId = localDoctorId;

    final existing = box.getAll().where((x) {
      if (x.patientId <= 0) return false;
      final p = ObjectBoxService.instance.patientBox.get(x.patientId);
      if (p == null) return false;
      return p.uhid == uhid &&
          x.createdAt.year == remote.createdAt.year &&
          x.createdAt.month == remote.createdAt.month &&
          x.createdAt.day == remote.createdAt.day;
    }).firstOrNull;

    if (existing != null) {
      remote.id = existing.id;
      box.put(remote);
      notifyListeners();
    } else {
      remote.id = 0;
      box.put(remote);
      notifyListeners();
    }
  }

  void _syncTemplateLWW(Map<String, dynamic> data) {
    final name = data['name'] as String? ?? '';
    if (name.isEmpty) return;
    final box = ObjectBoxService.instance.templateBox;
    final existing = box.getAll().where((t) => t.name == name).firstOrNull;
    final t = existing ?? PrescriptionTemplate(name: name);
    t.diagnosis = data['diagnosis'] ?? '';
    t.complaints = data['complaints'] ?? '';
    t.notes = data['notes'] ?? '';
    t.itemsJson = data['itemsJson'] ?? '[]';
    t.labTestsJson = data['labTestsJson'] ?? '[]';
    t.doctorId = data['doctorId'] ?? 0;
    box.put(t);
    notifyListeners();
  }

  void _syncProcedureLWW(Map<String, dynamic> data) {
    final name = data['name'] as String? ?? '';
    if (name.isEmpty) return;
    final box = ObjectBoxService.instance.procedureBox;
    final existing = box.query(Procedure_.name.equals(name)).build().findFirst();
    final p = Procedure.fromJson(data);
    p.id = existing?.id ?? 0;
    box.put(p);
    notifyListeners();
  }

  void _syncSaleLWW(Map<String, dynamic> data) {
    debugPrint('SyncService: _syncSaleLWW processing remote sale data: $data');
    final invoiceNo = data['invoiceNo'] as String? ?? '';
    if (invoiceNo.isEmpty) {
      debugPrint('SyncService: _syncSaleLWW empty invoiceNo, skipping');
      return;
    }
    final box = ObjectBoxService.instance.saleBox;
    final existing = box.query(Sale_.invoiceNo.equals(invoiceNo)).build().findFirst();
    final remote = Sale.fromJson(data);

    // Resolve local patient ID using patientUhid
    int localPatientId = 0;
    final uhid = data['patientUhid'] as String? ?? '';
    if (uhid.isNotEmpty) {
      final p = ObjectBoxService.instance.patientBox
          .query(Patient_.uhid.equals(uhid))
          .build()
          .findFirst();
      if (p != null) {
        localPatientId = p.id;
        debugPrint('SyncService: Resolved local patient ID $localPatientId for UHID $uhid');
      } else {
        debugPrint('SyncService: Could not resolve local patient for UHID $uhid');
      }
    }
    remote.patientId = localPatientId;

    if (existing != null) {
      remote.id = existing.id;
      debugPrint('SyncService: Sale $invoiceNo already exists locally (ID: ${existing.id}), overwriting/updating');
    } else {
      remote.id = 0;
      debugPrint('SyncService: Sale $invoiceNo is new, creating');
    }
    box.put(remote);
    debugPrint('SyncService: Sale $invoiceNo saved successfully. Notifying listeners.');
    notifyListeners();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    cancelFirestoreRealTimeSync();
    super.dispose();
  }

}

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  bool _connected = false;
  String? _lastIp;
  bool _intentionalDisconnect = false;
  int _reconnectAttempts = 0;
  final List<Map<String, dynamic>> _events = [];

  bool get connected => _connected;
  List<Map<String, dynamic>> get events => List.unmodifiable(_events);

  final StreamController<Map<String, dynamic>> _eventController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  Timer? _heartbeatTimer;

  void connect(String ip, String secret) {
    _lastIp = ip;
    _intentionalDisconnect = false;
    _reconnectAttempts = 0;
    _doConnect(ip, secret);
    _startHeartbeat(secret);
  }

  void _startHeartbeat(String secret) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (timer) async {
      if (_intentionalDisconnect || _lastIp == null) {
        timer.cancel();
        return;
      }
      
      final reachable = await SyncService.instance.testConnection(_lastIp!);
      if (!reachable) {
        if (_connected) {
          debugPrint('WebSocketService: Heartbeat failed! Force disconnecting WebSocket.');
          _connected = false;
          _channel?.sink.close();
          notifyListeners();
          _scheduleReconnect();
        }
      }
    });
  }

  void _doConnect(String ip, String secret) {
    if (_connected) return;
    try {
      Uri uri;
      if (ip.startsWith('http')) {
        final base = Uri.parse(ip);
        final scheme = base.scheme == 'https' ? 'wss' : 'ws';
        // Ensure path ends with /ws/updates without duplicating slashes
        String path = base.path;
        if (!path.endsWith('/')) path += '/';
        path += 'ws/updates';
        uri = base.replace(scheme: scheme, path: path, queryParameters: {'secret': secret});
      } else {
        uri = Uri.parse('ws://$ip:8080/ws/updates?secret=$secret');
      }
      
      debugPrint('WebSocketService: Connecting to $uri');
      _channel = WebSocketChannel.connect(uri);
      _connected = true;
      _reconnectAttempts = 0; // Reset on successful connect
      debugPrint('WebSocketService: Connected to $ip');

      _channel!.stream.listen(
        (data) {
          try {
            debugPrint('WebSocketService [Android]: Received data of type: ${data.runtimeType}');
            
            final Map<String, dynamic> msg;
            
            if (data is Map) {
              msg = Map<String, dynamic>.from(data);
            } else {
              String dataStr;
              if (data is String) {
                dataStr = data;
              } else if (data is List<int>) {
                dataStr = utf8.decode(data);
              } else if (data is List) {
                dataStr = utf8.decode(data.whereType<int>().toList());
              } else {
                dataStr = data.toString();
              }
              
              final decoded = jsonDecode(dataStr);
              if (decoded is Map) {
                msg = Map<String, dynamic>.from(decoded);
              } else {
                debugPrint('WebSocketService: Received non-map JSON: $decoded');
                return;
              }
            }

            _events.insert(0, msg);
            _eventController.add(msg);

              // Notification logic
              if (msg['event'] == 'new_patient') {
                NotificationService.instance.showNotification(
                  id: DateTime.now().millisecond,
                  title: 'New Patient in Queue',
                  body: msg['patientName'] ?? 'A new patient has been added.',
                );
              } else if (msg['event'] == 'low_stock') {
                NotificationService.instance.showNotification(
                  id: 1001,
                  title: 'Low Stock Alert',
                  body: msg['medicineName'] ??
                      'One or more items are low in stock.',
                );
              } else if (msg['event'] == 'remote_camera_trigger') {
                NotificationService.instance.showNotification(
                  id: 2001,
                  title: 'Remote Camera Requested',
                  body: 'Doctor needs a photo of ${msg['patientName'] ?? 'Patient'}. Tap to open camera.',
                  payload: jsonEncode({
                    'type': 'remote_camera',
                    'patientUhid': msg['patientUhid'],
                    'patientName': msg['patientName'],
                    'hubIp': msg['hubIp'],
                  }),
                );
              }

              notifyListeners();
          } catch (e, st) {
            debugPrint('WebSocketService: Error parsing message: $e\n$st');
            // Even if parsing fails, don't let the listener die
          }
        },
        onDone: () {
          _connected = false;
          notifyListeners();
          debugPrint('WebSocketService: Connection closed.');
          if (!_intentionalDisconnect && _lastIp != null) {
            _scheduleReconnect();
          }
        },
        onError: (e) {
          _connected = false;
          notifyListeners();
          debugPrint('WebSocketService: Error: $e');
          if (!_intentionalDisconnect && _lastIp != null) {
            _scheduleReconnect();
          }
        },
      );
      notifyListeners();
    } catch (e) {
      debugPrint('WebSocketService: Connect failed: $e');
      _connected = false;
      if (!_intentionalDisconnect && _lastIp != null) {
        _scheduleReconnect();
      }
    }
  }

  void _scheduleReconnect() {
    if (_intentionalDisconnect || _lastIp == null) return;
    
    // Exponential backoff: 2s, 4s, 8s, 16s, capped at 30s
    final int delaySeconds = (2 << _reconnectAttempts).clamp(2, 30);
    if (_reconnectAttempts < 5) _reconnectAttempts++;
    
    debugPrint('WebSocketService: Scheduling reconnect in ${delaySeconds}s (Attempt: $_reconnectAttempts)...');
    Future.delayed(Duration(seconds: delaySeconds), () {
      if (!_intentionalDisconnect && _lastIp != null && !_connected) {
        debugPrint('WebSocketService: Attempting reconnect to $_lastIp');
        final secret = ObjectBoxService.instance.settings.jwtSecret;
        _doConnect(_lastIp!, secret);
      }
    });
  }

  void disconnect() {
    _intentionalDisconnect = true;
    _heartbeatTimer?.cancel();
    _channel?.sink.close();
    _connected = false;
    _lastIp = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _intentionalDisconnect = true;
    _heartbeatTimer?.cancel();
    _eventController.close();
    super.dispose();
  }
}
