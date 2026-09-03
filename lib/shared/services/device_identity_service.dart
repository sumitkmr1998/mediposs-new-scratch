import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'objectbox_service.dart';

class DeviceIdentityService {
  static String? _cachedDeviceId;

  static String get cachedDeviceId => _cachedDeviceId ?? 'Unknown-Device';

  /// Resolves a human-readable, persistent device identifier.
  /// Example outputs:
  /// - "Android: Google Pixel 7"
  /// - "Windows: DESKTOP-MAIN (Hub)"
  /// - "Windows: LAPTOP-FRONT (Terminal)"
  static Future<String> initDeviceId() async {
    try {
      if (ObjectBoxService.isInitialized) {
        final settings = ObjectBoxService.instance.settings;
        if (settings.deviceId != null &&
            settings.deviceId!.isNotEmpty &&
            settings.deviceId != 'Unknown-Device' &&
            settings.deviceId != 'unknown') {
          _cachedDeviceId = settings.deviceId;
          return _cachedDeviceId!;
        }
      }

      final resolvedName = await _detectDeviceName();
      _cachedDeviceId = resolvedName;

      if (ObjectBoxService.isInitialized) {
        final settings = ObjectBoxService.instance.settings;
        settings.deviceId = resolvedName;
        ObjectBoxService.instance.settingsBox.put(settings);
      }

      return resolvedName;
    } catch (e) {
      debugPrint('DeviceIdentityService: Error resolving device ID: $e');
      final fallback = 'Device-${const Uuid().v4().substring(0, 8)}';
      _cachedDeviceId = fallback;
      return fallback;
    }
  }

  static Future<String> _detectDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();

    if (kIsWeb) {
      final webInfo = await deviceInfo.webBrowserInfo;
      return 'Web: ${webInfo.browserName.name}';
    }

    if (Platform.isAndroid) {
      try {
        final android = await deviceInfo.androidInfo;
        final brand = _capitalize(android.brand);
        final model = android.model;
        if (brand.isNotEmpty && model.isNotEmpty && !model.toLowerCase().contains(brand.toLowerCase())) {
          return 'Android: $brand $model';
        }
        return 'Android: $model';
      } catch (_) {
        return 'Android: Device';
      }
    }

    if (Platform.isWindows) {
      try {
        final win = await deviceInfo.windowsInfo;
        final compName = win.computerName.trim();
        final isTerminal = ObjectBoxService.isInitialized &&
            ObjectBoxService.instance.settings.isWindowsClient;
        final roleTag = isTerminal ? 'Terminal' : 'Hub';
        return compName.isNotEmpty
            ? 'Windows: $compName ($roleTag)'
            : 'Windows ($roleTag)';
      } catch (_) {
        return 'Windows Device';
      }
    }

    if (Platform.isIOS) {
      try {
        final ios = await deviceInfo.iosInfo;
        return 'iOS: ${ios.utsname.machine}';
      } catch (_) {
        return 'iOS Device';
      }
    }

    if (Platform.isMacOS) {
      try {
        final mac = await deviceInfo.macOsInfo;
        return 'macOS: ${mac.computerName}';
      } catch (_) {
        return 'macOS Device';
      }
    }

    if (Platform.isLinux) {
      try {
        final linux = await deviceInfo.linuxInfo;
        return 'Linux: ${linux.name}';
      } catch (_) {
        return 'Linux Device';
      }
    }

    return 'Device-${Platform.operatingSystem}';
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
