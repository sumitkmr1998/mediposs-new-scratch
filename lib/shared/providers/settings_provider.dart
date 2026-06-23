import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_user.dart';
import '../services/objectbox_service.dart';
import '../services/sync_service.dart';
import '../services/google_drive_service.dart';
import '../services/backup_restore_service.dart';
import '../services/subscription_service.dart';
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

  bool _isAutoBackingUp = false;
  bool get isAutoBackingUp => _isAutoBackingUp;

  Future<void> load() async {
    _settings = ObjectBoxService.instance.settings;
    
    // Attempt silent reconnect if linked
    if (_settings.googleDriveLinked && _settings.googleAuthData != null) {
      try {
        final success = await _googleDrive.loginWithCredentials(_settings.googleAuthData!);
        if (!success) {
          debugPrint('SettingsProvider: Silent Google login failed. Keeping link for manual retry.');
          // Don't unlink immediately, maybe it's just a network issue
        }
      } catch (e) {
        debugPrint('SettingsProvider: Error during silent login: $e');
      }
    }
    notifyListeners();
  }

  Future<void> linkGoogleDrive() async {
    if (!SubscriptionService.instance.isPro) {
      _googleError = 'Google Drive features require Pro or Enterprise tier';
      notifyListeners();
      return;
    }
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
    if (!SubscriptionService.instance.isPro) {
      _googleError = 'Google Drive Backup requires Pro or Enterprise tier';
      notifyListeners();
      return false;
    }
    if (!_settings.googleDriveSyncEnabled) {
      _googleError = 'Google Drive Sync is disabled';
      notifyListeners();
      return false;
    }
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

  Future<String?> exportFullLocalBackup() async {
    _isGoogleLoading = true;
    notifyListeners();

    try {
      final zipFile = await _googleDrive.generateFullBackupZip();
      if (zipFile == null) return null;

      String? outputPath = Platform.isWindows 
          ? '${Platform.environment['USERPROFILE']}\\Downloads' 
          : (await getDownloadsDirectory())?.path;
      
      if (outputPath == null) throw Exception('Downloads folder not found');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final targetPath = "$outputPath/mediposs_full_backup_$timestamp.zip";
      
      await zipFile.copy(targetPath);
      await zipFile.delete(); // Clean up temp

      _isGoogleLoading = false;
      notifyListeners();
      return targetPath;
    } catch (e) {
      debugPrint('Export Local Backup Err: $e');
      _isGoogleLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Triggers auto-backup based on the specified logic ('At Startup', 'On Close', 'Periodic')
  Future<void> checkAndPerformAutoBackup(String trigger) async {
    if (!SubscriptionService.instance.isPro) {
      debugPrint('Auto-Backup: skipped because Google Drive Sync requires Pro or Enterprise tier.');
      return;
    }
    if (!_settings.googleDriveSyncEnabled) {
      debugPrint('Auto-Backup: skipped because googleDriveSyncEnabled is false.');
      return;
    }
    if (_settings.autoBackupFrequency == 'Never') return;
    if (_settings.autoBackupLogic != trigger) return;

    // Logic for Daily/Weekly/Monthly timing (Simplified for check)
    final now = DateTime.now();
    final last = _settings.lastBackupMillis != null 
        ? DateTime.fromMillisecondsSinceEpoch(_settings.lastBackupMillis!) 
        : DateTime(2000);

    bool shouldBackup = false;
    
    // Check if we are past the scheduled time today
    bool isPastScheduledTime = true;
    if (_settings.autoBackupTime != null) {
      try {
        final parts = _settings.autoBackupTime!.split(':');
        final scheduledHour = int.parse(parts[0]);
        final scheduledMinute = int.parse(parts[1]);
        if (now.hour < scheduledHour || (now.hour == scheduledHour && now.minute < scheduledMinute)) {
          isPastScheduledTime = false;
        }
      } catch (_) {}
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
    } else if (_settings.autoBackupFrequency == 'Always') {
       shouldBackup = true;
    }

    if (shouldBackup) {
      try {
        _isAutoBackingUp = true;
        notifyListeners();
        
        debugPrint('Auto-Backup triggered by $trigger');
        await _googleDrive.uploadBackup();
        
        _settings.lastBackupMillis = now.millisecondsSinceEpoch;
        ObjectBoxService.instance.settingsBox.put(_settings);
        
        _isAutoBackingUp = false;
        notifyListeners();
      } catch (e) {
        debugPrint('Auto-Backup failed ($trigger): $e');
        _isAutoBackingUp = false;
        notifyListeners();
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
 
  Future<bool> restoreFromCloud(String fileId, {RestoreConfig? config}) async {
    _isGoogleLoading = true;
    _googleError = null;
    notifyListeners();
 
    try {
      await _googleDrive.downloadAndRestore(fileId, config: config);
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
