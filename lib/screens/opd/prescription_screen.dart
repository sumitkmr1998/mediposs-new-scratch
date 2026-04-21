import 'package:flutter/material.dart';
import '../../shared/models/appointment.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../windows/opd/prescription_windows.dart';
import '../android/opd/prescription_android.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/auth_provider.dart';

class PrescriptionScreen extends StatelessWidget {
  final Appointment appointment;

  const PrescriptionScreen({super.key, required this.appointment});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.canAccessMedicalRecords) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_person, size: 80, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Restricted Access',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Only Doctors and Admins can view medical records.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    if (!kIsWeb && Platform.isAndroid) {
      return PrescriptionAndroid(appointment: appointment);
    }
    return PrescriptionWindows(appointment: appointment);
  }
}