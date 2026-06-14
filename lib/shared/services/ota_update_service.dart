import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../theme/app_theme.dart';

class OtaUpdateService {
  static const String _kSkipVersionPref = 'ota_skip_version_name';

  /// Compares two semantic version strings (e.g. "1.8.1" and "1.8.0")
  static bool _isNewerVersion(String current, String latest) {
    try {
      final cleanCurrent = current.toLowerCase().replaceAll('v', '').split('-').first.split('+').first;
      final cleanLatest = latest.toLowerCase().replaceAll('v', '').split('-').first.split('+').first;

      final currentParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final latestParts = cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < currentParts.length || i < latestParts.length; i++) {
        final cur = i < currentParts.length ? currentParts[i] : 0;
        final lat = i < latestParts.length ? latestParts[i] : 0;
        if (lat > cur) return true;
        if (lat < cur) return false;
      }
      return false;
    } catch (e) {
      return latest != current;
    }
  }

  /// Checks GitHub Releases for updates and prompts the user if one is found
  static Future<void> checkForUpdate(BuildContext context, {bool forceShowNoUpdate = false}) async {
    // Only support Android and Windows OTA updates
    if (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.windows) {
      if (forceShowNoUpdate) {
        _showNoUpdateSnackBar(context);
      }
      return;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final String currentVersionName = packageInfo.version;

      final response = await http.get(
        Uri.parse('https://api.github.com/repos/sumitkmr1998/mediposs-new-scratch/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to query GitHub Releases API (status ${response.statusCode})');
      }

      final data = jsonDecode(response.body);
      final String latestVersionName = data['tag_name'] ?? '';
      final String changelog = data['body'] ?? 'Bug fixes and performance improvements.';
      final List assets = data['assets'] ?? [];

      // A release is mandatory if the body/changelog contains '[mandatory]' keyword
      final bool isMandatory = changelog.toLowerCase().contains('[mandatory]');

      final bool isAndroid = defaultTargetPlatform == TargetPlatform.android;
      String downloadUrl = '';

      for (final asset in assets) {
        final String name = asset['name'] ?? '';
        final String url = asset['browser_download_url'] ?? '';
        if (isAndroid && name.toLowerCase().endsWith('.apk')) {
          downloadUrl = url;
          break;
        } else if (!isAndroid && name.toLowerCase().endsWith('.zip')) {
          downloadUrl = url;
          break;
        }
      }

      if (downloadUrl.isEmpty) {
        debugPrint('No release asset found matching the current platform on GitHub.');
        if (forceShowNoUpdate) {
          _showNoUpdateSnackBar(context);
        }
        return;
      }

      if (_isNewerVersion(currentVersionName, latestVersionName)) {
        // If not mandatory, check if user chose to skip this specific version
        if (!isMandatory && !forceShowNoUpdate) {
          final prefs = await SharedPreferences.getInstance();
          final skippedVersion = prefs.getString(_kSkipVersionPref) ?? '';
          if (skippedVersion == latestVersionName) {
            debugPrint('OtaUpdateService: User previously skipped version $latestVersionName. Ignoring popup.');
            return;
          }
        }

        if (context.mounted) {
          _showUpdateDialog(
            context,
            currentVersionName,
            latestVersionName,
            latestVersionName,
            downloadUrl,
            isMandatory,
            changelog,
          );
        }
      } else {
        if (forceShowNoUpdate && context.mounted) {
          _showNoUpdateSnackBar(context);
        }
      }
    } catch (e) {
      debugPrint('OtaUpdateService error: $e');
      if (forceShowNoUpdate && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking for updates: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  static void _showNoUpdateSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ You are on the latest version of MediPoss.'),
        backgroundColor: AppTheme.success,
      ),
    );
  }

  static void _showUpdateDialog(
    BuildContext context,
    String currentVersionName,
    String latestVersionName,
    String latestVersionTag,
    String downloadUrl,
    bool isMandatory,
    String changelog,
  ) {
    showDialog(
      context: context,
      barrierDismissible: !isMandatory,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => !isMandatory,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.system_update_rounded, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              const Text(
                'New Update Available',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MediPoss $latestVersionName is ready for download.',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Current version: $currentVersionName',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 16),
              const Text(
                'What\'s New:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primary),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  changelog,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (isMandatory) ...[
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 16),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'This is a mandatory update required to continue using the application.',
                        style: TextStyle(color: AppTheme.danger, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            if (!isMandatory) ...[
              TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString(_kSkipVersionPref, latestVersionTag);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Skip This Version', style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Later', style: TextStyle(color: Colors.grey)),
              ),
            ],
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _triggerOtaUpdate(context, downloadUrl);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Update Now'),
            ),
          ],
        ),
      ),
    );
  }

  static void _triggerOtaUpdate(BuildContext context, String url) {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _triggerWindowsUpdate(context, url);
      return;
    }

    // Show download indicator using overlay SnackBar or stateful dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _DownloadProgressDialog(),
    );

    OtaUpdate().execute(
      url,
      destinationFilename: 'medipos-update.apk',
    ).listen(
      (OtaEvent event) {
        if (event.status == OtaStatus.DOWNLOADING) {
          final progress = double.tryParse(event.value ?? '0') ?? 0.0;
          _progressNotifier.value = progress / 100.0;
        } else if (event.status == OtaStatus.INSTALLING) {
          // Close progress dialog
          final context = GlobalKey<NavigatorState>().currentContext;
          _progressNotifier.value = 1.0;
        } else {
          // Failure or internal error
          _progressNotifier.value = -1.0;
        }
      },
    );
  }

  static Future<void> _triggerWindowsUpdate(BuildContext context, String url) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _DownloadProgressDialog(),
    );

    try {
      _progressNotifier.value = 0.0;
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Failed to download file: Status code ${response.statusCode}');
      }

      final int totalBytes = response.contentLength ?? 0;
      int downloadedBytes = 0;

      final tempDir = await getTemporaryDirectory();
      final zipFile = File('${tempDir.path}/medipos_update.zip');
      
      if (zipFile.existsSync()) {
        zipFile.deleteSync();
      }

      final sink = zipFile.openWrite();

      await response.stream.listen(
        (chunk) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          if (totalBytes > 0) {
            _progressNotifier.value = downloadedBytes / totalBytes;
          }
        },
        onDone: () async {
          await sink.close();
          client.close();
          _progressNotifier.value = 1.0;

          // Now start the powershell updater script and exit the app!
          await _launchWindowsUpdaterScript(zipFile.path);
        },
        onError: (e) {
          sink.close();
          client.close();
          _progressNotifier.value = -1.0;
        },
        cancelOnError: true,
      ).asFuture();

    } catch (e) {
      debugPrint('Windows update download error: $e');
      _progressNotifier.value = -1.0;
    }
  }

  static Future<void> _launchWindowsUpdaterScript(String zipPath) async {
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;

      final escapedZipPath = zipPath.replaceAll("'", "''");
      final escapedDestPath = exeDir.replaceAll("'", "''");
      final escapedExePath = exePath.replaceAll("'", "''");

      final psCommand = 
          "Start-Sleep -s 2; "
          "\$proc = Get-Process -Id ${pid} -ErrorAction SilentlyContinue; "
          "if (\$proc) { \$proc.WaitForExit(5000) }; "
          "Expand-Archive -Path '$escapedZipPath' -DestinationPath '$escapedDestPath' -Force; "
          "Remove-Item -Path '$escapedZipPath' -Force; "
          "Start-Process -FilePath '$escapedExePath' -WorkingDirectory '$escapedDestPath';";

      debugPrint('Launching PowerShell updater script: $psCommand');

      await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          psCommand,
        ],
        mode: ProcessStartMode.detached,
      );

      exit(0);
    } catch (e) {
      debugPrint('Failed to launch Windows updater script: $e');
    }
  }

  static final ValueNotifier<double> _progressNotifier = ValueNotifier<double>(0.0);
}

class _DownloadProgressDialog extends StatefulWidget {
  const _DownloadProgressDialog();

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  @override
  void initState() {
    super.initState();
    OtaUpdateService._progressNotifier.value = 0.0;
    OtaUpdateService._progressNotifier.addListener(_onProgressChanged);
  }

  @override
  void dispose() {
    OtaUpdateService._progressNotifier.removeListener(_onProgressChanged);
    super.dispose();
  }

  void _onProgressChanged() {
    if (OtaUpdateService._progressNotifier.value == 1.0 || OtaUpdateService._progressNotifier.value < 0.0) {
      if (mounted) {
        Navigator.pop(context);
        if (OtaUpdateService._progressNotifier.value < 0.0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Failed to download update. Please check your internet connection.'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: OtaUpdateService._progressNotifier,
      builder: (context, value, _) {
        final percentage = (value * 100).toStringAsFixed(0);
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(strokeWidth: 5, color: AppTheme.primary),
                const SizedBox(height: 24),
                const Text(
                  'Downloading Update...',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  '$percentage%',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primary),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    backgroundColor: Colors.grey.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Downloading the package from Firebase. Please do not close the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
