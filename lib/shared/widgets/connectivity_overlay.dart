import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class ConnectivityOverlay extends StatelessWidget {
  final String title;
  final String message;
  final List<Widget> actions;
  final bool isBlocking;

  const ConnectivityOverlay({
    super.key,
    required this.title,
    required this.message,
    required this.actions,
    this.isBlocking = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: AppTheme.danger),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 32),
                  ...actions,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
