import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

class DiscoveryService {
  static const int _udpPort = 8888;
  static const String _magicPing = 'MediPoss_Client_Ping';
  static RawDatagramSocket? _udpServer;

  /// Starts listening for UDP broadcasts on Windows.
  /// When a ping is received, it replies directly back to the Android client.
  static Future<void> startAdvertising(int apiPort, String shopId) async {
    if (!Platform.isWindows) return;

    try {
      _udpServer?.close();
      _udpServer =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, _udpPort);
      _udpServer!.broadcastEnabled = true;

      _udpServer!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpServer!.receive();
          if (datagram != null) {
            final msg = utf8.decode(datagram.data);
            if (msg == _magicPing) {
              // Valid ping received, send back our Hub IP and shopId
              final replyPayload = jsonEncode({
                'id': 'MediPoss_Hub',
                'apiPort': apiPort,
                'shopId': shopId,
              });
              _udpServer!.send(
                utf8.encode(replyPayload),
                datagram.address,
                datagram.port,
              );
              debugPrint(
                  'UDP Server: Responded to discovery ping from ${datagram.address.address} (Shop: $shopId)');
            }
          }
        }
      });
      debugPrint(
          'Hub is advertised actively via UDP on port $_udpPort and API on $apiPort');
    } catch (e) {
      debugPrint('Failed to start UDP listener: $e');
    }
  }

  /// Stops the UDP listener
  static void stopAdvertising() {
    _udpServer?.close();
    _udpServer = null;
  }

  /// Blasts a magic UDP packet across the subnet and waits up to 2 seconds for a reply.
  static Future<String?> discoverHub({String? targetShopId}) async {
    RawDatagramSocket? socket;
    try {
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP();
      debugPrint('DiscoveryService: My Android IP is $wifiIP, targetShopId: $targetShopId');

      String? broadcastAddr = '255.255.255.255'; // Global broadcast fallback
      if (wifiIP != null) {
        final parts = wifiIP.split('.');
        if (parts.length == 4) {
          broadcastAddr = '${parts[0]}.${parts[1]}.${parts[2]}.255';
        }
      }

      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final completer = Completer<String?>();

      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket!.receive();
          if (datagram != null) {
            try {
              final payload = jsonDecode(utf8.decode(datagram.data));
              if (payload['id'] == 'MediPoss_Hub') {
                final hubShopId = payload['shopId'] as String? ?? '';
                if (targetShopId == null ||
                    targetShopId.isEmpty ||
                    hubShopId.trim().toLowerCase() == targetShopId.trim().toLowerCase()) {
                  if (!completer.isCompleted) {
                    completer.complete(datagram.address.address);
                  }
                } else {
                  debugPrint('DiscoveryService: Discovered Hub (Shop: $hubShopId) does not match target ($targetShopId). Skipping.');
                }
              }
            } catch (_) {}
          }
        }
      });

      // Blast to specific calculated subnet broadcast
      socket.send(
        utf8.encode(_magicPing),
        InternetAddress(broadcastAddr),
        _udpPort,
      );

      // List of fallback subnet broadcasts to try in case wifiIP is null or inaccurate
      final fallbacks = [
        '255.255.255.255',
        '192.168.1.255',
        '192.168.0.255',
        '192.168.43.255',
        '192.168.8.255',
        '10.0.2.255',
      ];

      for (final addr in fallbacks) {
        if (addr != broadcastAddr) {
          socket.send(
            utf8.encode(_magicPing),
            InternetAddress(addr),
            _udpPort,
          );
        }
      }

      // Timeout after 2.5 seconds
      return await completer.future.timeout(
        const Duration(milliseconds: 2500),
        onTimeout: () => null,
      );
    } catch (e) {
      debugPrint('UDP Discovery Error: $e');
      return null;
    } finally {
      socket?.close();
    }
  }
}
