import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

class DiscoveryService {
  static const int _udpPort = 8888;
  static const String _magicPing = 'MediPoss_Client_Ping';

  /// Blasts a magic UDP packet across the subnet and waits up to 2.5 seconds for a reply from the Hub.
  static Future<String?> discoverHub() async {
    RawDatagramSocket? socket;
    try {
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP();
      debugPrint('AnalysisApp: My IP is $wifiIP');

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
                if (!completer.isCompleted) {
                  // Hub found! Return its IP with the API port
                  final apiPort = payload['apiPort'] ?? 8080;
                  completer.complete('${datagram.address.address}:$apiPort');
                }
              }
            } catch (_) {}
          }
        }
      });

      // Blast to specific subnet broadcast
      socket.send(
        utf8.encode(_magicPing),
        InternetAddress(broadcastAddr),
        _udpPort,
      );

      // Blast to global broadcast just in case
      socket.send(
        utf8.encode(_magicPing),
        InternetAddress('255.255.255.255'),
        _udpPort,
      );

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
