import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'firebase_sync_service.dart';

class CloudflareService {
  static CloudflareService? _instance;
  static CloudflareService get instance {
    if (_instance == null) {
      _instance = CloudflareService._();
    }
    return _instance!;
  }

  Process? _tunnelProcess;
  Timer? _healthTimer;
  String? _currentUrl;
  bool _isInitializing = false;

  CloudflareService._();

  static Future<void> init() async {
    if (_instance != null) return;
    _instance = CloudflareService._();
  }

  Future<void> start() async {
    if (!Platform.isWindows || _isInitializing) return;
    _isInitializing = true;

    try {
      final exePath = await _ensureBinaryExists();
      await _runTunnel(exePath);
      _startHealthMonitoring(exePath);
    } catch (e) {
      debugPrint('Cloudflare Error: $e');
    } finally {
      _isInitializing = false;
    }
  }

  Future<String> _ensureBinaryExists() async {
    final appDir = await getApplicationSupportDirectory();
    final exeFile = File(p.join(appDir.path, 'cloudflared.exe'));

    if (!await exeFile.exists()) {
      debugPrint('Downloading cloudflared.exe...');
      final url = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-stable-windows-amd64.exe';
      final request = await HttpClient().getUrl(Uri.parse(url));
      final response = await request.close();
      await response.pipe(exeFile.openWrite());
      debugPrint('Download complete.');
    }
    return exeFile.path;
  }

  Future<void> _runTunnel(String exePath) async {
    await _killExistingProcesses();

    debugPrint('Starting Cloudflare Tunnel...');
    _tunnelProcess = await Process.start(
      exePath,
      ['tunnel', '--url', 'http://localhost:8080'],
      mode: ProcessStartMode.normal,
    );

    // Parse the output to find the URL
    _tunnelProcess!.stderr.transform(utf8.decoder).listen((data) {
      if (data.contains('.trycloudflare.com')) {
        final match = RegExp(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com').firstMatch(data);
        if (match != null) {
          _currentUrl = match.group(0);
          debugPrint('Cloudflare URL: $_currentUrl');
          _reportToFirebase();
        }
      }
    });

    _tunnelProcess!.exitCode.then((code) {
      debugPrint('Cloudflare tunnel exited with code $code');
      _tunnelProcess = null;
    });
  }

  Future<void> _killExistingProcesses() async {
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/F', '/IM', 'cloudflared.exe']);
    }
  }

  void _startHealthMonitoring(String exePath) {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (_tunnelProcess == null) {
        debugPrint('Tunnel down, repairing...');
        await _runTunnel(exePath);
      }
    });
  }

  Future<void> _reportToFirebase() async {
    if (_currentUrl != null) {
      await FirebaseSyncService.instance.updateHubStatus(
        isOnline: true,
        cloudflareUrl: _currentUrl,
      );
    }
  }

  Future<void> stop() async {
    _healthTimer?.cancel();
    _tunnelProcess?.kill();
    _tunnelProcess = null;
    _currentUrl = null;
    await FirebaseSyncService.instance.updateHubStatus(isOnline: false);
  }

  String? get currentUrl => _currentUrl;
}
