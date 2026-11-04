import 'dart:io';
import 'package:flutter/foundation.dart';

class NetworkHelper {
  /// Returns the best local LAN IPv4 address (e.g. Wi-Fi or Ethernet: 192.168.x.x, 10.x.x.x),
  /// filtering out virtual, loopback, and link-local adapters (vgate, vethernet, tailscale, etc.).
  static Future<String> getLocalIp() async {
    final ips = await getAllLocalIps();
    return ips.isNotEmpty ? ips.first : '127.0.0.1';
  }

  /// Returns all valid physical/LAN IPv4 addresses sorted by likelihood of being the primary local network.
  static Future<List<String>> getAllLocalIps() async {
    final List<String> results = [];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );

      final List<_ScoredIp> scored = [];

      for (final iface in interfaces) {
        final nameLower = iface.name.toLowerCase();
        final isVirtual = nameLower.contains('vgate') ||
            nameLower.contains('vethernet') ||
            nameLower.contains('virtual') ||
            nameLower.contains('vmware') ||
            nameLower.contains('vbox') ||
            nameLower.contains('wsl') ||
            nameLower.contains('tailscale') ||
            nameLower.contains('tap') ||
            nameLower.contains('tun') ||
            nameLower.contains('loopback') ||
            nameLower.contains('bluetooth') ||
            nameLower.contains('hyper-v');

        for (final addr in iface.addresses) {
          if (addr.isLoopback || addr.isLinkLocal) continue;
          final ip = addr.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;

          int score = 0;
          if (isVirtual) {
            score = -100;
          } else {
            // Physical adapters
            if (nameLower.contains('wi-fi') ||
                nameLower.contains('wifi') ||
                nameLower.contains('wlan')) {
              score += 50;
            } else if (nameLower.contains('ethernet') ||
                nameLower.contains('lan')) {
              score += 40;
            }

            // IP subnet preference
            if (ip.startsWith('192.168.')) {
              score += 30;
            } else if (ip.startsWith('10.')) {
              score += 25;
            } else if (ip.startsWith('172.')) {
              final parts = ip.split('.');
              final second = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
              if (second >= 16 && second <= 31) {
                score += 15;
              }
            }
          }

          scored.add(_ScoredIp(ip, score));
        }
      }

      scored.sort((a, b) => b.score.compareTo(a.score));
      for (final s in scored) {
        if (s.score > 0 && !results.contains(s.ip)) {
          results.add(s.ip);
        }
      }

      // If no positive-score IP found, fallback to any non-loopback IP
      if (results.isEmpty) {
        for (final s in scored) {
          if (!results.contains(s.ip)) {
            results.add(s.ip);
          }
        }
      }
    } catch (e) {
      debugPrint('NetworkHelper.getAllLocalIps error: $e');
    }

    return results;
  }
}

class _ScoredIp {
  final String ip;
  final int score;
  _ScoredIp(this.ip, this.score);
}

