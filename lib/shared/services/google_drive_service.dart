import '../models/exit_backup_status.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'objectbox_service.dart';
import 'backup_restore_service.dart';

class GoogleDriveService {
  static const String _clientId = '865649525029-99ppibc69v7b6lf9a2ijojlsrvsmdcaq.apps.googleusercontent.com';
  static const String _clientSecret = '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';
  
  static const List<String> _scopes = [
    drive.DriveApi.driveFileScope,
  ];

  AuthClient? _client;
  
  bool get isConnected => _client != null;

  Future<AccessCredentials?> login() async {
    try {
      final id = ClientId(_clientId, _clientSecret);
      // prompt: 'consent' and access_type: 'offline' are often needed to get a refresh token consistently on desktop
      final client = await clientViaUserConsent(id, _scopes, (url) {
        launchUrl(Uri.parse(url));
      });
      _client = client;
      return client.credentials;
    } catch (e) {
      debugPrint('GoogleDriveLogin Error: $e');
      throw Exception('Login failed: $e');
    }
  }

  Future<bool> loginWithCredentials(String credsJson) async {
    try {
      final id = ClientId(_clientId, _clientSecret);
      final json = jsonDecode(credsJson);
      final creds = AccessCredentials.fromJson(json);
      
      // Use autoRefreshingClient to ensure the session stays alive
      _client = autoRefreshingClient(id, creds, http.Client());
      return true;
    } catch (e) {
      debugPrint('GoogleDriveSilentLogin Error: $e');
      return false;
    }
  }

  void logout() {
    _client?.close();
    _client = null;
  }

  /// Performs a full system backup (Local + Google Drive).
  Future<File?> generateFullBackupZip() async {
    return await BackupRestoreService.exportBackupPackage(since: null);
  }

  /// Performs an incremental delta backup package since the given timestamp.
  Future<File?> generateIncrementalBackupZip({DateTime? since}) async {
    return await BackupRestoreService.exportBackupPackage(
      since: since ?? DateTime.now().subtract(const Duration(days: 1)),
    );
  }

  /// Generates a backup package (full if since == null, incremental if since != null).
  Future<File?> generateBackupZip({
    DateTime? since,
    void Function(String message)? onProgress,
  }) async {
    return await BackupRestoreService.exportBackupPackage(
      since: since,
      onProgress: onProgress,
    );
  }

  /// Performs a system backup (Local + Google Drive).
  /// If [since] is provided, an incremental delta backup package is generated.
  /// If [since] is null, a full baseline backup package is generated.
  /// Local offline backup is ALWAYS saved to disk regardless of Google Drive connection.
  Future<bool> uploadBackup({
    DateTime? since,
    void Function(ExitBackupPhase phase, String title, String detail, double? progress)? onProgress,
  }) async {
    File? zipFile;
    try {
      final isIncremental = since != null;
      final backupTypeStr = isIncremental ? 'Incremental (Daily)' : 'Full (Complete)';

      onProgress?.call(
        ExitBackupPhase.makingZip,
        'Creating Zip Archive',
        'Exporting $backupTypeStr records and database tables...',
        0.15,
      );

      zipFile = await generateBackupZip(
        since: since,
        onProgress: (msg) {
          onProgress?.call(
            ExitBackupPhase.makingZip,
            'Creating Zip Archive',
            msg,
            0.35,
          );
        },
      );
      if (zipFile == null) {
        debugPrint('Backup generation returned null');
        return false;
      }

      final zipFileName = p.basename(zipFile.path);

      // STEP 1: Offline Local Backup (Guaranteed First)
      onProgress?.call(
        ExitBackupPhase.savingLocal,
        'Saving Local Backup',
        'Writing local archive ($zipFileName) to disk...',
        0.5,
      );
      final savedLocalPath = await _handleLocalBackup(zipFile, isIncremental: isIncremental);

      final displayLocalPath = savedLocalPath != null
          ? '${p.basename(p.dirname(savedLocalPath))}\\${p.basename(savedLocalPath)}'
          : zipFileName;

      onProgress?.call(
        ExitBackupPhase.savingLocal,
        'Local Backup Saved',
        'Saved to Documents\\MediPoss Backups\\$displayLocalPath',
        0.65,
      );

      // STEP 2: Google Drive Upload (If Connected & Enabled)
      final driveEnabled = ObjectBoxService.isInitialized
          ? ObjectBoxService.instance.settings.googleDriveSyncEnabled
          : true;

      // If client is not initialized but credentials are saved, attempt silent login
      if (_client == null && ObjectBoxService.isInitialized) {
        final authData = ObjectBoxService.instance.settings.googleAuthData;
        if (ObjectBoxService.instance.settings.googleDriveLinked && authData != null && authData.isNotEmpty) {
          try {
            await loginWithCredentials(authData);
          } catch (e) {
            debugPrint('Silent Google login failed before upload: $e');
          }
        }
      }

      if (_client != null && driveEnabled) {
        onProgress?.call(
          ExitBackupPhase.uploadingDrive,
          'Connecting to Google Drive',
          'Authenticating with Drive API & verifying folders...',
          0.70,
        );
        try {
          final driveApi = drive.DriveApi(_client!);
          final media = drive.Media(zipFile.openRead(), zipFile.lengthSync());
          final rootFolderId = await _getOrCreateFolder(driveApi);
          final targetFolderId = await _getOrCreateSubfolder(
            driveApi,
            rootFolderId,
            isIncremental ? 'daily' : 'full',
          );

          onProgress?.call(
            ExitBackupPhase.uploadingDrive,
            'Uploading to Google Drive',
            'Uploading $zipFileName to Google Drive...',
            0.85,
          );

          final fileToUpload = drive.File()
            ..name = zipFileName
            ..parents = [targetFolderId]
            ..description = isIncremental
                ? 'MediPoss incremental delta backup (Cloud)'
                : 'MediPoss complete baseline backup (Cloud)';

          await driveApi.files.create(fileToUpload, uploadMedia: media);
          debugPrint('Google Drive upload succeeded: $zipFileName in ${isIncremental ? "daily" : "full"}');

          onProgress?.call(
            ExitBackupPhase.uploadingDrive,
            'Google Drive Uploaded',
            'Cloud backup uploaded successfully to Google Drive.',
            0.88,
          );

          // Clean up cloud files older than retention policy
          if (isIncremental) {
            await _cleanupOldDriveBackups(driveApi, targetFolderId, daysToKeep: 14);
          }
        } catch (driveErr) {
          debugPrint('Google Drive upload error (local copy preserved): $driveErr');
          onProgress?.call(
            ExitBackupPhase.uploadingDrive,
            'Drive Upload Skipped',
            'Local backup preserved. Google Drive offline: $driveErr',
            0.88,
          );
        }
      } else {
        final reason = !driveEnabled
            ? 'Google Drive sync disabled in Settings'
            : 'Google Drive account is not connected';
        onProgress?.call(
          ExitBackupPhase.uploadingDrive,
          'Local Backup Secured',
          '$reason. Local offline copy is safely stored.',
          0.88,
        );
        debugPrint('Google Drive not active ($reason). Local backup safe.');
      }

      return true;
    } catch (e) {
      debugPrint('Backup System Error: $e');
      return false;
    } finally {
      // Clean up staging temp zip
      if (zipFile != null && await zipFile.exists()) {
        try {
          await zipFile.delete();
        } catch (_) {}
      }
    }
  }

  Future<String?> _handleLocalBackup(File zipFile, {bool isIncremental = false}) async {
    try {
      final subfolder = isIncremental ? 'daily' : 'full';
      final backupDir = await _getLocalBackupDirectory(subfolder: subfolder);
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      // Copy the zip to the local backup folder
      final targetPath = p.join(backupDir.path, p.basename(zipFile.path));
      await zipFile.copy(targetPath);
      debugPrint('Local offline backup saved to: $targetPath');

      // Cleanup: keep 14 days for daily deltas, 30 days for full baselines
      await _cleanupOldLocalBackups(backupDir, daysToKeep: isIncremental ? 14 : 30);
      return targetPath;
    } catch (e) {
      debugPrint('Local Backup Error: $e. This might be due to folder permissions.');
      return null;
    }
  }

  Future<Directory> _getLocalBackupDirectory({String subfolder = ''}) async {
    Directory baseDir;
    try {
      // 1. Prefer User Documents directory for visibility and easy access
      final docsDir = await getApplicationDocumentsDirectory();
      final idealDir = Directory(p.join(docsDir.path, 'MediPoss Backups'));
      if (!await idealDir.exists()) {
        await idealDir.create(recursive: true);
      }
      final testFile = File(p.join(idealDir.path, '.test_write'));
      await testFile.writeAsString('ok');
      await testFile.delete();
      baseDir = idealDir;
    } catch (_) {
      try {
        // 2. Fallback: Executable directory / backups
        String exePath = Platform.resolvedExecutable;
        String appDir = p.dirname(exePath);
        final fallbackDir = Directory(p.join(appDir, 'backups'));
        await fallbackDir.create(recursive: true);
        baseDir = fallbackDir;
      } catch (_) {
        // 3. Fallback: Application Support Directory (Roaming)
        final supportDir = await getApplicationSupportDirectory();
        baseDir = Directory(p.join(supportDir.path, 'backups'));
      }
    }

    if (subfolder.isNotEmpty) {
      final sub = Directory(p.join(baseDir.path, subfolder));
      if (!await sub.exists()) {
        await sub.create(recursive: true);
      }
      return sub;
    }
    return baseDir;
  }

  Future<void> _cleanupOldLocalBackups(Directory backupDir, {int daysToKeep = 14}) async {
    final now = DateTime.now();
    final expirationDate = now.subtract(Duration(days: daysToKeep));

    try {
      final files = backupDir.listSync().whereType<File>();
      for (final file in files) {
        if (p.extension(file.path) == '.zip') {
          final stats = await file.stat();
          if (stats.modified.isBefore(expirationDate)) {
            debugPrint('Cleaning up old backup: ${p.basename(file.path)}');
            await file.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('Backup Cleanup Error: $e');
    }
  }

  Future<void> _cleanupOldDriveBackups(drive.DriveApi driveApi, String folderId, {int daysToKeep = 14}) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: daysToKeep));
      final query = "'$folderId' in parents and mimeType != 'application/vnd.google-apps.folder' and trashed = false";
      final list = await driveApi.files.list(q: query, $fields: 'files(id, name, createdTime)');
      if (list.files != null) {
        for (final file in list.files!) {
          if (file.createdTime != null && file.createdTime!.isBefore(cutoff)) {
            debugPrint('Cleaning up old cloud backup: ${file.name} (${file.id})');
            await driveApi.files.delete(file.id!);
          }
        }
      }
    } catch (e) {
      debugPrint('Cloud backup cleanup error: $e');
    }
  }


  Future<List<drive.File>> fetchBackups() async {
    if (_client == null) throw Exception('Google Drive not connected');
    final driveApi = drive.DriveApi(_client!);

    // 1. Get Root Folder ID
    final rootFolderId = await _getOrCreateFolder(driveApi);

    // 2. Discover subfolders (daily, full)
    final subfoldersQuery = "'$rootFolderId' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final subfolders = await driveApi.files.list(q: subfoldersQuery);
    final folderIds = [rootFolderId];
    if (subfolders.files != null) {
      for (final f in subfolders.files!) {
        if (f.id != null) folderIds.add(f.id!);
      }
    }

    // 3. List Files in root or subfolders
    final parentClauses = folderIds.map((id) => "'$id' in parents").join(' or ');
    final query = "($parentClauses) and mimeType != 'application/vnd.google-apps.folder' and trashed = false";
    final list = await driveApi.files.list(
      q: query,
      orderBy: 'createdTime desc',
      $fields: 'files(id, name, createdTime, size, description)',
    );

    return list.files ?? [];
  }

  Future<void> downloadAndRestore(String fileId, {RestoreConfig? config}) async {
    if (_client == null) throw Exception('Google Drive not connected');
    final driveApi = drive.DriveApi(_client!);

    // 1. Download to Temp
    final tempDir = await getTemporaryDirectory();
    final zipPath = p.join(tempDir.path, 'downloaded_backup.zip');
    final zipFile = File(zipPath);

    final response = await driveApi.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final sink = zipFile.openWrite();
    await response.stream.pipe(sink);
    await sink.close();

    // 3. Safety: Create Local Backup first
    await ObjectBoxService.instance.createLocalSafetyBackup();

    // 4. Import Data
    final restoreConfig = config ?? RestoreConfig(); // default to restoring everything
    await BackupRestoreService.importFromJsonBackup(zipFile, restoreConfig);

    // 6. Cleanup
    if (await zipFile.exists()) await zipFile.delete();
  }

  Future<String> _getOrCreateFolder(drive.DriveApi driveApi) async {
    const folderName = 'MediPoss Backups';
    const query = "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";

    final list = await driveApi.files.list(q: query);
    if (list.files != null && list.files!.isNotEmpty) {
      return list.files!.first.id!;
    }

    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder';

    final created = await driveApi.files.create(folder);
    return created.id!;
  }

  Future<String> _getOrCreateSubfolder(drive.DriveApi driveApi, String parentId, String subfolderName) async {
    final query = "'$parentId' in parents and name = '$subfolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final list = await driveApi.files.list(q: query);
    if (list.files != null && list.files!.isNotEmpty) {
      return list.files!.first.id!;
    }

    final folder = drive.File()
      ..name = subfolderName
      ..parents = [parentId]
      ..mimeType = 'application/vnd.google-apps.folder';

    final created = await driveApi.files.create(folder);
    return created.id!;
  }
}
