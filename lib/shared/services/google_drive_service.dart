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
    return await BackupRestoreService.exportToJsonBackup();
  }

  /// Performs a full system backup (Local + Google Drive).
  Future<bool> uploadBackup() async {
    try {
      final zipFile = await generateFullBackupZip();
      if (zipFile == null) return false;

      final zipFileName = p.basename(zipFile.path);

      // 4. STEP 1: Offline Local Backup
      await _handleLocalBackup(zipFile);

      // 5. STEP 2: Google Drive Upload (If Connected)
      if (_client != null) {
        final driveApi = drive.DriveApi(_client!);
        final media = drive.Media(zipFile.openRead(), zipFile.lengthSync());
        String folderId = await _getOrCreateFolder(driveApi);
        
        final fileToUpload = drive.File()
          ..name = zipFileName
          ..parents = [folderId]
          ..description = 'MediPoss complete system backup (Cloud)';

        await driveApi.files.create(fileToUpload, uploadMedia: media);
      } else {
        debugPrint('Google Drive not connected - Cloud upload skipped.');
      }
      
      // 6. Clean up temp zip
      if (await zipFile.exists()) await zipFile.delete();
      
      return true;
    } catch (e) {
      debugPrint('Backup System Error: $e');
      rethrow;
    }
  }

  Future<void> _handleLocalBackup(File zipFile) async {
    try {
      final backupDir = await _getLocalBackupDirectory();
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      // Copy the zip to the local backup folder
      final targetPath = p.join(backupDir.path, p.basename(zipFile.path));
      await zipFile.copy(targetPath);
      debugPrint('Local offline backup saved to: $targetPath');

      // Cleanup files older than 10 days
      await _cleanupOldLocalBackups(backupDir);
    } catch (e) {
      debugPrint('Local Backup Error: $e. This might be due to folder permissions.');
    }
  }

  Future<Directory> _getLocalBackupDirectory() async {
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
      
      return idealDir;
    } catch (_) {
      // 2. Fallback to App Support Directory if Program Files is restricted
      final supportDir = await getApplicationSupportDirectory();
      return Directory(p.join(supportDir.path, 'backups'));
    }
  }

  Future<void> _cleanupOldLocalBackups(Directory backupDir) async {
    final now = DateTime.now();
    final expirationDate = now.subtract(const Duration(days: 10));

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

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (final entity in source.list()) {
      if (entity is Directory) {
        final newDir = Directory(p.join(destination.path, p.basename(entity.path)));
        await newDir.create();
        await _copyDirectory(entity, newDir);
      } else if (entity is File) {
        await entity.copy(p.join(destination.path, p.basename(entity.path)));
      }
    }
  }

  Future<List<drive.File>> fetchBackups() async {
    if (_client == null) throw Exception('Google Drive not connected');
    final driveApi = drive.DriveApi(_client!);
    
    // 1. Get Folder ID
    final folderId = await _getOrCreateFolder(driveApi);
    
    // 2. List Files In Folder
    final query = "'$folderId' in parents and trashed = false";
    final list = await driveApi.files.list(q: query, orderBy: 'createdTime desc', $fields: 'files(id, name, createdTime, size)');
    
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
}
