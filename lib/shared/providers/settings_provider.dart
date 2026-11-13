import '../models/exit_backup_status.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_user.dart';
import '../services/objectbox_service.dart';
import '../services/sync_service.dart';
import '../services/google_drive_service.dart';
import '../services/backup_restore_service.dart';
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

  void setThemeMode(String mode) {
    _settings.themeMode = mode;
    ObjectBoxService.instance.settingsBox.put(_settings);
    notifyListeners();
  }

  bool _isAutoBackingUp = false;
  bool get isAutoBackingUp => _isAutoBackingUp;

  Future<void> load() async {
    _settings = ObjectBoxService.instance.settings;

    // Attempt silent reconnect if linked
    if (_settings.googleDriveLinked && _settings.googleAuthData != null) {
      try {
        final success =
            await _googleDrive.loginWithCredentials(_settings.googleAuthData!);
        if (!success) {
          debugPrint(
              'SettingsProvider: Silent Google login failed. Keeping link for manual retry.');
          // Don't unlink immediately, maybe it's just a network issue
        }
      } catch (e) {
        debugPrint('SettingsProvider: Error during silent login: $e');
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

  Future<bool> performManualBackup({
    bool incremental = false,
    void Function(ExitBackupPhase phase, String title, String detail, double? progress)? onProgress,
  }) async {
    _isGoogleLoading = true;
    _googleError = null;
    notifyListeners();

    try {
      final last = _settings.lastBackupMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(_settings.lastBackupMillis!)
          : null;
      final since = (incremental && last != null) ? last : null;

      final success = await _googleDrive.uploadBackup(
        since: since,
        onProgress: onProgress,
      );
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

  Future<String?> exportIncrementalLocalBackup({DateTime? since}) async {
    _isGoogleLoading = true;
    notifyListeners();

    try {
      final effectiveSince = since ??
          (_settings.lastBackupMillis != null
              ? DateTime.fromMillisecondsSinceEpoch(_settings.lastBackupMillis!)
              : DateTime.now().subtract(const Duration(days: 1)));

      final zipFile = await _googleDrive.generateIncrementalBackupZip(since: effectiveSince);
      if (zipFile == null) return null;

      String? outputPath = Platform.isWindows
          ? '${Platform.environment['USERPROFILE']}\\Downloads'
          : (await getDownloadsDirectory())?.path;

      if (outputPath == null) throw Exception('Downloads folder not found');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final targetPath = "$outputPath/mediposs_incremental_backup_$timestamp.zip";

      await zipFile.copy(targetPath);
      await zipFile.delete(); // Clean up temp

      _isGoogleLoading = false;
      notifyListeners();
      return targetPath;
    } catch (e) {
      debugPrint('Export Incremental Backup Err: $e');
      _isGoogleLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Triggers auto-backup based on the specified logic ('At Startup', 'On Close', 'Periodic')
  Future<bool> checkAndPerformAutoBackup(
    String trigger, {
    void Function(ExitBackupPhase phase, String title, String detail, double? progress)? onProgress,
  }) async {
    if (_settings.autoBackupFrequency == 'Never') {
      onProgress?.call(
        ExitBackupPhase.savingLocal,
        'Auto-Backup Disabled',
        'Auto-backup frequency is set to Never in Settings.',
        0.8,
      );
      return false;
    }

    final now = DateTime.now();
    final last = _settings.lastBackupMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(_settings.lastBackupMillis!)
        : null;

    final isDifferentDay = last == null ||
        (last.year != now.year || last.month != now.month || last.day != now.day);

    // Check if we are past the scheduled time today (only relevant for Periodic background timer)
    bool isPastScheduledTime = true;
    if (_settings.autoBackupTime != null && _settings.autoBackupTime!.isNotEmpty) {
      try {
        final parts = _settings.autoBackupTime!.split(':');
        final scheduledHour = int.parse(parts[0]);
        final scheduledMinute = int.parse(parts[1]);
        if (now.hour < scheduledHour ||
            (now.hour == scheduledHour && now.minute < scheduledMinute)) {
          isPastScheduledTime = false;
        }
      } catch (_) {}
    }

    // Determine if this trigger applies:
    // 1. Direct match: user selected this trigger in Settings (e.g. 'On Close', 'At Startup', 'Periodic')
    // 2. Safety catch-up on close: if today has no backup yet, closing the app should ensure data safety
    // 3. Periodic catch-up: if today has no backup and scheduled time passed while running
    final isConfiguredTrigger = _settings.autoBackupLogic == trigger;
    final isCloseCatchUp = trigger == 'On Close' && isDifferentDay;
    final isPeriodicCatchUp = trigger == 'Periodic' && isDifferentDay && isPastScheduledTime;

    if (!isConfiguredTrigger && !isCloseCatchUp && !isPeriodicCatchUp) {
      return false;
    }

    bool shouldBackup = false;
    if (_settings.autoBackupFrequency == 'Daily') {
      if (trigger == 'Periodic') {
        shouldBackup = (isDifferentDay && isPastScheduledTime) ||
            (last != null && now.difference(last).inHours >= 24) ||
            last == null;
      } else {
        // 'On Close' or 'At Startup' triggers once per day on different day
        shouldBackup = isDifferentDay;
      }
    } else if (_settings.autoBackupFrequency == 'Weekly') {
      final daysSince = last == null ? 999 : now.difference(DateTime(last.year, last.month, last.day)).inDays;
      if (trigger == 'Periodic') {
        shouldBackup = daysSince >= 7 && isPastScheduledTime;
      } else {
        shouldBackup = daysSince >= 7;
      }
    } else if (_settings.autoBackupFrequency == 'Monthly') {
      final monthsDiff = last == null ? 999 : (now.year - last.year) * 12 + (now.month - last.month);
      if (trigger == 'Periodic') {
        shouldBackup = monthsDiff >= 1 && isPastScheduledTime;
      } else {
        shouldBackup = monthsDiff >= 1;
      }
    } else if (_settings.autoBackupFrequency == 'Always') {
      shouldBackup = true;
    }

    if (!shouldBackup) {
      debugPrint('Auto-Backup check ($trigger): already up to date. Last backup: $last');
      if (trigger == 'On Close' && last != null) {
        onProgress?.call(
          ExitBackupPhase.savingLocal,
          'Backup Up-to-Date',
          'Latest backup already completed today (${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}).',
          0.85,
        );
      }
      return false;
    }

    if (_isAutoBackingUp) return false;

    try {
      _isAutoBackingUp = true;
      notifyListeners();

      debugPrint('Auto-Backup triggered by $trigger (Frequency: ${_settings.autoBackupFrequency})');

      // Incremental vs Full:
      // If last backup was within 7 days, generate an incremental daily delta.
      // Otherwise, run a full baseline snapshot.
      DateTime? since;
      if (last != null) {
        final daysSinceLast = now.difference(last).inDays;
        if (daysSinceLast < 7) {
          since = last;
        }
      }

      final success = await _googleDrive.uploadBackup(
        since: since,
        onProgress: onProgress,
      );

      if (success) {
        _settings.lastBackupMillis = now.millisecondsSinceEpoch;
        ObjectBoxService.instance.settingsBox.put(_settings);
        debugPrint('Auto-Backup succeeded ($trigger). Recorded timestamp: $now (Incremental: ${since != null})');
      }

      _isAutoBackingUp = false;
      notifyListeners();
      return success;
    } catch (e) {
      debugPrint('Auto-Backup failed ($trigger): $e');
      _isAutoBackingUp = false;
      notifyListeners();
      return false;
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
