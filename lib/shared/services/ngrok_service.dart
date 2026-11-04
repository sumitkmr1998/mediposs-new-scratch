import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'firebase_sync_service.dart';

/// Service managing the ngrok tunnel lifecycle on Windows Hub.
/// Exposes the local Shelf server (default port 8080) to the internet via ngrok,
/// registers the public URL with Firebase for remote clients, and maintains health.
class NgrokService {
  static NgrokService? _instance;
  static NgrokService get instance {
    _instance ??= NgrokService._();
    return _instance!;
  }

  Process? _tunnelProcess;
  Timer? _healthTimer;
  String? _currentUrl;
  bool _isInitializing = false;

  NgrokService._();

  static Future<void> init() async {
    if (_instance != null) return;
    _instance = NgrokService._();
  }

  /// Starts the ngrok tunnel if running on Windows and not already active.
  Future<void> start() async {
    if (!Platform.isWindows || _isInitializing) return;
    _isInitializing = true;

    try {
      final exePath = await _findNgrokExecutable();
      await _runTunnel(exePath);
      _startHealthMonitoring(exePath);
    } catch (e) {
      debugPrint('NgrokService: Error starting tunnel: $e');
    } finally {
      _isInitializing = false;
    }
  }

  /// Finds ngrok executable either on system PATH or in AppData/WinApps.
  Future<String> _findNgrokExecutable() async {
    // 1. Check system PATH first
    try {
      final whereResult = await Process.run('where', ['ngrok']);
      if (whereResult.exitCode == 0) {
        final path = whereResult.stdout.toString().split(RegExp(r'[\r\n]+')).firstWhere(
          (line) => line.trim().isNotEmpty,
          orElse: () => '',
        );
        if (path.isNotEmpty && await File(path).exists()) {
          return path;
        }
      }
    } catch (_) {}

    // 2. Common Windows Apps / LocalAppData locations
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    final candidates = [
      p.join(localAppData, 'Microsoft', 'WindowsApps', 'ngrok.exe'),
      p.join(localAppData, 'ngrok', 'ngrok.exe'),
      p.join(localAppData, 'Programs', 'ngrok', 'ngrok.exe'),
    ];

    for (final c in candidates) {
      if (await File(c).exists()) {
        return c;
      }
    }

    // 3. App Support Directory fallback
    final appDir = await getApplicationSupportDirectory();
    final localExe = File(p.join(appDir.path, 'ngrok.exe'));
    if (await localExe.exists()) {
      return localExe.path;
    }

    // Default to 'ngrok' assuming environment PATH
    return 'ngrok';
  }

  /// Spawns the ngrok tunnel process and queries the local 127.0.0.1:4040 API for public URL.
  Future<void> _runTunnel(String exePath) async {
    await _killExistingProcesses();

    debugPrint('NgrokService: Starting ngrok tunnel on port 8080...');
    try {
      _tunnelProcess = await Process.start(
        exePath,
        ['http', '8080', '--log=stdout'],
        mode: ProcessStartMode.normal,
      );
    } catch (e) {
      debugPrint('NgrokService: Process start failed: $e');
      return;
    }

    // Monitor process output
    _tunnelProcess!.stdout.transform(utf8.decoder).listen((data) {
      // In case ngrok outputs tunnel url in stdout
      if (data.contains('.ngrok-free.app') || data.contains('.ngrok.io') || data.contains('.ngrok.app')) {
        _extractUrlFromText(data);
      }
    });

    _tunnelProcess!.stderr.transform(utf8.decoder).listen((data) {
      debugPrint('Ngrok stderr: $data');
    });

    _tunnelProcess!.exitCode.then((code) {
      debugPrint('NgrokService: Process exited with code $code');
      _tunnelProcess = null;
    });

    // Query ngrok's local inspection API (127.0.0.1:4040) to reliably retrieve the public URL
    await _pollPublicUrlFromApi();
  }

  void _extractUrlFromText(String data) {
    final match = RegExp(r'https://[a-zA-Z0-9-]+\.(ngrok-free\.app|ngrok\.io|ngrok\.app)').firstMatch(data);
    if (match != null && _currentUrl != match.group(0)) {
      _currentUrl = match.group(0);
      debugPrint('NgrokService: Public URL acquired from stdout: $_currentUrl');
      _reportToFirebase();
    }
  }

  /// Polls ngrok's local web agent at http://127.0.0.1:4040/api/tunnels
  Future<void> _pollPublicUrlFromApi() async {
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (_currentUrl != null) break;

      try {
        final res = await http.get(Uri.parse('http://127.0.0.1:4040/api/tunnels')).timeout(
          const Duration(seconds: 2),
        );
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          final tunnels = json['tunnels'] as List<dynamic>?;
          if (tunnels != null && tunnels.isNotEmpty) {
            for (final t in tunnels) {
              final publicUrl = t['public_url'] as String?;
              if (publicUrl != null && publicUrl.startsWith('https://')) {
                _currentUrl = publicUrl;
                debugPrint('NgrokService: Public URL acquired via API: $_currentUrl');
                await _reportToFirebase();
                return;
              }
            }
          }
        }
      } catch (_) {
        // ngrok web agent starting up
      }
    }
  }

  Future<void> _killExistingProcesses() async {
    if (Platform.isWindows) {
      try {
        await Process.run('taskkill', ['/F', '/IM', 'ngrok.exe']);
        await Process.run('taskkill', ['/F', '/IM', 'cloudflared.exe']);
      } catch (_) {}
    }
  }

  void _startHealthMonitoring(String exePath) {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (_tunnelProcess == null) {
        debugPrint('NgrokService: Tunnel process is down, restarting...');
        await _runTunnel(exePath);
      } else if (_currentUrl == null) {
        await _pollPublicUrlFromApi();
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
    _healthTimer = null;
    _tunnelProcess?.kill();
    _tunnelProcess = null;
    _currentUrl = null;
    await FirebaseSyncService.instance.updateHubStatus(isOnline: false);
  }

  /// Restarts the ngrok tunnel process and fetches a fresh public URL.
  Future<void> redeploy() async {
    await stop();
    await _killExistingProcesses();
    await start();
  }

  String? get currentUrl => _currentUrl;
}

