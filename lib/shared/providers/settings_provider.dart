import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../services/objectbox_service.dart';
import '../services/sync_service.dart';
import '../services/google_drive_service.dart';
import 'package:googleapis/drive/v3.dart' as drive;

class SettingsProvider extends ChangeNotifier {
  late AppSettings _settings;
  final GoogleDriveService _googleDrive = GoogleDriveService();
  bool _isGoogleLoading = false;
  String? _googleError;

  AppSettings get settings => _settings;
  bool get isGoogleLoading => _isGoogleLoading;
  bool get isGoogleConnected => _googleDrive.isConnected;
  String? get googleError => _googleError;

  ThemeMode get themeMode {
    switch (_settings.themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> load() async {
    _settings = ObjectBoxService.instance.settings;
    
    // Attempt silent reconnect if linked
    if (_settings.googleDriveLinked && _settings.googleAuthData != null) {
      final success = await _googleDrive.loginWithCredentials(_settings.googleAuthData!);
      if (!success) {
        _settings.googleDriveLinked = false;
        ObjectBoxService.instance.settingsBox.put(_settings);
      }
    }
    notifyListeners();
  }

  Future<void> linkGoogleDrive() async {
    _isGoogleLoading = true;
    notifyListeners();

    _googleError = null;
    try {
      final creds = await _googleDrive.login();
      if (creds != null) {
        _settings.googleDriveLinked = true;
        _settings.googleAuthData = jsonEncode(creds.toJson());
        ObjectBoxService.instance.settingsBox.put(_settings);
      }
    } catch (e) {
      _googleError = e.toString().replaceFirst('Exception: ', '');
    }

    _isGoogleLoading = false;
    notifyListeners();
  }

  void unlinkGoogleDrive() {
    _googleDrive.logout();
    _settings.googleDriveLinked = false;
    _settings.googleAuthData = null;
    ObjectBoxService.instance.settingsBox.put(_settings);
    notifyListeners();
  }

  Future<bool> performManualBackup() async {
    if (!isGoogleConnected) {
      _googleError = 'Google Drive not connected';
      notifyListeners();
      return false;
    }
    
    _isGoogleLoading = true;
    _googleError = null;
    notifyListeners();
 
    try {
      final success = await _googleDrive.uploadBackup();
      if (success) {
        _settings.lastBackupMillis = DateTime.now().millisecondsSinceEpoch;
        ObjectBoxService.instance.settingsBox.put(_settings);
      }
      _isGoogleLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _googleError = e.toString().replaceFirst('Exception: ', '');
      _isGoogleLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Triggers auto-backup based on the specified logic ('At Startup', 'On Close', 'Periodic')
  Future<void> checkAndPerformAutoBackup(String trigger) async {
    if (!_settings.googleDriveLinked || _settings.autoBackupFrequency == 'Never') return;
    if (_settings.autoBackupLogic != trigger) return;

    // Logic for Daily/Weekly/Monthly timing
    final now = DateTime.now();
    final last = _settings.lastBackupMillis != null 
        ? DateTime.fromMillisecondsSinceEpoch(_settings.lastBackupMillis!) 
        : DateTime(2000);

    bool shouldBackup = false;
    
    // Check if we are past the scheduled time today
    bool isPastScheduledTime = true;
    if (_settings.autoBackupTime != null) {
      final parts = _settings.autoBackupTime!.split(':');
      final scheduledHour = int.parse(parts[0]);
      final scheduledMinute = int.parse(parts[1]);
      final nowTime = TimeOfDay.fromDateTime(now);
      
      if (nowTime.hour < scheduledHour || (nowTime.hour == scheduledHour && nowTime.minute < scheduledMinute)) {
        isPastScheduledTime = false;
      }
    }

    if (_settings.autoBackupFrequency == 'Daily') {
      if (now.difference(last).inDays >= 1 && isPastScheduledTime) {
        shouldBackup = true;
      }
    } else if (_settings.autoBackupFrequency == 'Weekly') {
      if (now.difference(last).inDays >= 7 && isPastScheduledTime) {
        shouldBackup = true;
      }
    } else if (_settings.autoBackupFrequency == 'Monthly') {
      if (now.difference(last).inDays >= 30 && isPastScheduledTime) {
        shouldBackup = true;
      }
    }

    if (shouldBackup) {
      try {
        debugPrint('Auto-Backup triggered by $trigger');
        await _googleDrive.uploadBackup();
        _settings.lastBackupMillis = now.millisecondsSinceEpoch;
        ObjectBoxService.instance.settingsBox.put(_settings);
        notifyListeners();
      } catch (e) {
        debugPrint('Auto-Backup failed ($trigger): $e');
      }
    }
  }

  void save(AppSettings updated, {SyncService? syncService}) {
    updated.id = (_settings.id == 0) ? 0 : _settings.id;
    ObjectBoxService.instance.settingsBox.put(updated);
    _settings = updated;
    if (syncService != null && syncService.isConnected) {
      syncService.pushSettings(updated);
    }
    notifyListeners();
  }
 
  void toggleNavCollapse() {
    _settings.navCollapsed = !_settings.navCollapsed;
    ObjectBoxService.instance.settingsBox.put(_settings);
    notifyListeners();
  }

  Future<List<drive.File>> fetchCloudBackups() async {
    try {
      return await _googleDrive.fetchBackups();
    } catch (e) {
      _googleError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return [];
    }
  }
 
  Future<bool> restoreFromCloud(String fileId) async {
    _isGoogleLoading = true;
    _googleError = null;
    notifyListeners();
 
    try {
      await _googleDrive.downloadAndRestore(fileId);
      _isGoogleLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _googleError = e.toString().replaceFirst('Exception: ', '');
      _isGoogleLoading = false;
      notifyListeners();
      return false;
    }
  }
}
