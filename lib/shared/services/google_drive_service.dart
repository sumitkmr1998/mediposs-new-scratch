import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'objectbox_service.dart';

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
      final creds = AccessCredentials.fromJson(jsonDecode(credsJson));
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

  /// Zips multiple data directories and uploads them as a single backup.
  Future<bool> uploadBackup() async {
    if (_client == null) throw Exception('Google Drive not connected');

    try {
      final driveApi = drive.DriveApi(_client!);
      
      // 1. Determine Source Paths
      final appDocDir = await getApplicationDocumentsDirectory();
      final dbDirStr = ObjectBoxService.instance.dbDirectory;
      
      final sources = <String, Directory>{
        'database': Directory(dbDirStr),
        'patient_photos': Directory(p.join(appDocDir.path, 'patient_photos')),
        'prescriptions': Directory(p.join(appDocDir.path, 'prescriptions')),
      };

      // 2. Prepare Temp Staging Area
      final tempDir = await getTemporaryDirectory();
      final stagingName = 'mediposs_staging_${DateTime.now().millisecondsSinceEpoch}';
      final stagingDir = Directory(p.join(tempDir.path, stagingName));
      await stagingDir.create(recursive: true);

      bool foundAnything = false;
      for (final entry in sources.entries) {
        if (await entry.value.exists()) {
          final target = Directory(p.join(stagingDir.path, entry.key));
          await target.create(recursive: true);
          // Simple directory copy (recursive)
          await _copyDirectory(entry.value, target);
          foundAnything = true;
        }
      }

      if (!foundAnything) {
        throw Exception('Source data folders not found. Database at: $dbDirStr');
      }

      // 3. Zip the staging folder
      final zipFilePath = p.join(tempDir.path, 'mediposs_full_backup.zip');
      final encoder = ZipFileEncoder();
      encoder.create(zipFilePath);
      encoder.addDirectory(stagingDir);
      encoder.close();

      final zipFile = File(zipFilePath);
      final media = drive.Media(zipFile.openRead(), zipFile.lengthSync());

      // 4. Drive Upload
      String folderId = await _getOrCreateFolder(driveApi);
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      
      final fileToUpload = drive.File()
        ..name = 'mediposs_full_backup_$timestamp.zip'
        ..parents = [folderId]
        ..description = 'MediPoss complete system backup';

      await driveApi.files.create(fileToUpload, uploadMedia: media);
      
      // 5. Clean up
      if (await zipFile.exists()) await zipFile.delete();
      if (await stagingDir.exists()) await stagingDir.delete(recursive: true);
      
      return true;
    } catch (e) {
      debugPrint('GoogleDriveUpload Error: $e');
      rethrow;
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
 
  Future<void> downloadAndRestore(String fileId) async {
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
 
    // 2. Prepare Targets
    final appDocDir = await getApplicationDocumentsDirectory();
    final dbDirStr = ObjectBoxService.instance.dbDirectory;
 
    // 3. Safety: Create Local Backup first (as requested)
    await ObjectBoxService.instance.createLocalSafetyBackup();
 
    // 4. Critical: Close Store
    await ObjectBoxService.instance.close();
 
    // 5. Extract and Overwrite
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
 
    for (final file in archive) {
      if (file.isFile) {
        // The zip structure is: staging_dir/folder_name/actual_files
        // We need to parse: folder_name/actual_files
        final parts = p.split(file.name);
        if (parts.length < 2) continue;
        
        final type = parts[parts.length - 2]; // database, patient_photos, etc.
        final fileName = parts.last;
        
        String? targetPath;
        if (type == 'database') {
          targetPath = p.join(dbDirStr, fileName);
        } else if (type == 'patient_photos') {
          targetPath = p.join(appDocDir.path, 'patient_photos', fileName);
        } else if (type == 'prescriptions') {
          targetPath = p.join(appDocDir.path, 'prescriptions', fileName);
        }
 
        if (targetPath != null) {
          final outFile = File(targetPath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        }
      }
    }
 
    // 6. Cleanup
    if (await zipFile.exists()) await zipFile.delete();
  }
 
  Future<String> _getOrCreateFolder(drive.DriveApi driveApi) async {
    const folderName = 'MediPoss Backups';
    final query = "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    
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
