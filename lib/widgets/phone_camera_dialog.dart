import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../shared/services/local_server_service.dart';
import '../shared/services/objectbox_service.dart';
import '../theme/app_theme.dart';

class PhoneCameraDialog extends StatefulWidget {
  final String patientUhid;
  final String patientName;

  const PhoneCameraDialog({
    super.key,
    required this.patientUhid,
    required this.patientName,
  });

  @override
  State<PhoneCameraDialog> createState() => _PhoneCameraDialogState();
}

class _PhoneCameraDialogState extends State<PhoneCameraDialog> {
  StreamSubscription? _subscription;
  String? _localIp;
  bool _isLoading = true;
  String? _error;
  bool _received = false;

  @override
  void initState() {
    super.initState();
    _initConnection();
  }

  Future<void> _initConnection() async {
    try {
      final info = NetworkInfo();
      _localIp = await info.getWifiIP();
      
      if (_localIp == null) {
        // Fallback or handle no WiFi
        _error = 'Could not detect local WiFi IP. Please ensure the PC is on WiFi.';
      } else {
        // Broadcast trigger to any connected Android devices
        LocalServerService.instance.broadcast({
          'event': 'remote_camera_trigger',
          'patientUhid': widget.patientUhid,
          'patientName': widget.patientName,
          'hubIp': _localIp,
        });

        _subscription = LocalServerService.instance.incomingDataStream.listen((data) {
          if (data.startsWith('patient_photos:')) {
            final path = data.substring('patient_photos:'.length);
            setState(() {
              _received = true;
            });
            // Give it a moment to save to DB then close with the path
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) Navigator.pop(context, path);
            });
          }
        });
      }
    } catch (e) {
      _error = 'Error initializing: $e';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payload = jsonEncode({
      'type': 'remote_camera',
      'hubIp': _localIp,
      'patientUhid': widget.patientUhid,
      'patientName': widget.patientName,
      'hubSecret': ObjectBoxService.instance.settings.jwtSecret,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    return Dialog(
      backgroundColor: AppTheme.darkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(LucideIcons.smartphone, color: AppTheme.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Wireless Phone Camera',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Using Android companion for ${widget.patientName}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(LucideIcons.x, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 32),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              _buildErrorState()
            else if (_received)
              _buildSuccessState()
            else
              _buildQrState(payload),
            const SizedBox(height: 24),
            Text(
              'Both devices must be on the same WiFi network.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrState(String payload) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: QrImageView(
            data: payload,
            version: QrVersions.auto,
            size: 200.0,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Scan this QR with the MediPoss Android App',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
            Text(
              'Waiting for photo...',
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSuccessState() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(LucideIcons.checkCircle2, color: Colors.green, size: 64),
        ),
        const SizedBox(height: 24),
        const Text(
          'Photo Received!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'The image has been added to the prescription.',
          style: TextStyle(color: Colors.white.withOpacity(0.6)),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Column(
      children: [
        const Icon(LucideIcons.wifiOff, color: Colors.redAccent, size: 48),
        const SizedBox(height: 16),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.redAccent),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _initConnection,
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          child: const Text('Retry'),
        ),
      ],
    );
  }
}
