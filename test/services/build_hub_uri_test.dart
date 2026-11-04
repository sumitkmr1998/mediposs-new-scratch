import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/services/sync_service.dart';

void main() {
  group('SyncService.buildHubUri', () {
    test('formats raw IP without port', () {
      final uri = SyncService.buildHubUri('192.168.1.5', '/health');
      expect(uri.toString(), 'http://192.168.1.5:8080/health');
    });

    test('formats IP that already has port 8080 without duplicating it', () {
      final uri = SyncService.buildHubUri('192.168.1.5:8080', '/health');
      expect(uri.toString(), 'http://192.168.1.5:8080/health');
    });

    test('formats full http URL with port and trailing slash', () {
      final uri = SyncService.buildHubUri('http://192.168.1.5:8080/', '/health');
      expect(uri.toString(), 'http://192.168.1.5:8080/health');
    });

    test('formats HTTPS tunnel URL', () {
      final uri = SyncService.buildHubUri('https://abc.ngrok-free.app', '/api/medicines/push');
      expect(uri.toString(), 'https://abc.ngrok-free.app/api/medicines/push');
    });

    test('formats WebSocket URI for raw IP', () {
      final uri = SyncService.buildHubUri(
        '192.168.1.5',
        '/ws/updates',
        queryParams: {'secret': 'test1234'},
        scheme: 'ws',
      );
      expect(uri.toString(), 'ws://192.168.1.5:8080/ws/updates?secret=test1234');
    });

    test('formats WebSocket URI for secure tunnel', () {
      final uri = SyncService.buildHubUri(
        'https://abc.ngrok-free.app',
        '/ws/updates',
        queryParams: {'secret': 'test1234'},
        scheme: 'wss',
      );
      expect(uri.toString(), 'wss://abc.ngrok-free.app/ws/updates?secret=test1234');
    });
  });
}

