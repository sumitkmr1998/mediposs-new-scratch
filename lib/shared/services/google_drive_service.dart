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
  Future<File?> generateBackupZip({DateTime? since}) async {
    return await BackupRestoreService.exportBackupPackage(since: since);
  }

  /// Performs a system backup (Local + Google Drive).
  /// If [since] is provided, an incremental delta backup package is generated.
  /// If [since] is null, a full baseline backup package is generated.
  /// Local offline backup is ALWAYS saved to disk regardless of Google Drive connection.
  Future<bool> uploadBackup({DateTime? since}) async {
    try {
      final isIncremental = since != null;
      final zipFile = await generateBackupZip(since: since);
      if (zipFile == null) return false;

      final zipFileName = p.basename(zipFile.path);

      // STEP 1: Offline Local Backup (Guaranteed)
      await _handleLocalBackup(zipFile, isIncremental: isIncremental);

      // STEP 2: Google Drive Upload (If Connected)
      if (_client != null) {
        final driveApi = drive.DriveApi(_client!);
        final media = drive.Media(zipFile.openRead(), zipFile.lengthSync());
        final rootFolderId = await _getOrCreateFolder(driveApi);
        final targetFolderId = await _getOrCreateSubfolder(
          driveApi,
          rootFolderId,
          isIncremental ? 'daily' : 'full',
        );

        final fileToUpload = drive.File()
          ..name = zipFileName
          ..parents = [targetFolderId]
          ..description = isIncremental
              ? 'MediPoss incremental delta backup (Cloud)'
              : 'MediPoss complete baseline backup (Cloud)';

        await driveApi.files.create(fileToUpload, uploadMedia: media);
        debugPrint('Google Drive upload succeeded: $zipFileName in ${isIncremental ? "daily" : "full"}');

        // Clean up cloud files older than retention policy
        if (isIncremental) {
          await _cleanupOldDriveBackups(driveApi, targetFolderId, daysToKeep: 14);
        }
      } else {
        debugPrint('Google Drive not connected - Cloud upload skipped, local backup saved.');
      }

      // STEP 3: Clean up staging temp zip
      if (await zipFile.exists()) await zipFile.delete();

      return true;
    } catch (e) {
      debugPrint('Backup System Error: $e');
      rethrow;
    }
  }

  Future<void> _handleLocalBackup(File zipFile, {bool isIncremental = false}) async {
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
    } catch (e) {
      debugPrint('Local Backup Error: $e. This might be due to folder permissions.');
    }
  }

  Future<Directory> _getLocalBackupDirectory({String subfolder = ''}) async {
    Directory baseDir;
    try {
      // 1. Try Installation folder "backups"
      String exePath = Platform.resolvedExecutable;
      String appDir = p.dirname(exePath);
      final idealDir = Directory(p.join(appDir, 'backups'));

      // Test write permission (quick check)
      final testFile = File(p.join(idealDir.path, '.test'));
      await idealDir.create(recursive: true);
      await testFile.writeAsString('test');
      await testFile.delete();

      baseDir = idealDir;
    } catch (_) {
      // 2. Fallback to App Support Directory if Program Files is restricted
      final supportDir = await getApplicationSupportDirectory();
      baseDir = Directory(p.join(supportDir.path, 'backups'));
    }

    if (subfolder.isNotEmpty) {
      return Directory(p.join(baseDir.path, subfolder));
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
