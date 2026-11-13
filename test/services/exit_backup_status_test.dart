import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/models/exit_backup_status.dart';
import 'package:medipos/widgets/exit_backup_dialog.dart';

void main() {
  group('ExitBackupStatus Model Tests', () {
    test('initial factory sets default values', () {
      final status = ExitBackupStatus.initial();
      expect(status.phase, equals(ExitBackupPhase.preparing));
      expect(status.title, equals('Securing Your Data'));
      expect(status.currentStep, equals(1));
      expect(status.totalSteps, equals(4));
      expect(status.isComplete, isFalse);
      expect(status.progressFraction, equals(0.05));
    });

    test('copyWith updates state attributes cleanly', () {
      final initial = ExitBackupStatus.initial();
      final updated = initial.copyWith(
        phase: ExitBackupPhase.makingZip,
        title: 'Creating Zip Archive',
        detail: 'Exporting 14 tables into ZIP...',
        currentStep: 1,
        progressFraction: 0.25,
      );

      expect(updated.phase, equals(ExitBackupPhase.makingZip));
      expect(updated.title, equals('Creating Zip Archive'));
      expect(updated.detail, equals('Exporting 14 tables into ZIP...'));
      expect(updated.currentStep, equals(1));
      expect(updated.progressFraction, equals(0.25));
      expect(updated.totalSteps, equals(4));
    });

    test('step sequence reflects local save, drive upload, and cloud sync', () {
      var status = ExitBackupStatus.initial();

      // Step 1: Zip
      status = status.copyWith(
        phase: ExitBackupPhase.makingZip,
        title: 'Creating Zip Archive',
        detail: 'Exporting database tables...',
        currentStep: 1,
        progressFraction: 0.25,
      );
      expect(status.currentStep, equals(1));

      // Step 2: Local save
      status = status.copyWith(
        phase: ExitBackupPhase.savingLocal,
        title: 'Saving Local Copy',
        detail: 'Storing offline backup...',
        currentStep: 2,
        progressFraction: 0.50,
      );
      expect(status.currentStep, equals(2));

      // Step 3: Google Drive
      status = status.copyWith(
        phase: ExitBackupPhase.uploadingDrive,
        title: 'Uploading to Google Drive',
        detail: 'Uploading archive...',
        currentStep: 3,
        progressFraction: 0.85,
      );
      expect(status.currentStep, equals(3));

      // Step 4: Cloud Sync
      status = status.copyWith(
        phase: ExitBackupPhase.syncingCloud,
        title: 'Syncing Cloud Mirror',
        detail: 'Broadcasting to Cloud...',
        currentStep: 4,
        progressFraction: 0.95,
      );
      expect(status.currentStep, equals(4));

      // Complete
      status = status.copyWith(
        phase: ExitBackupPhase.complete,
        title: 'Backup Complete!',
        detail: 'Closing MediPoss...',
        currentStep: 4,
        progressFraction: 1.0,
        isComplete: true,
      );
      expect(status.phase, equals(ExitBackupPhase.complete));
      expect(status.isComplete, isTrue);
    });
  });

  group('ExitBackupDialog Widget Tests', () {
    testWidgets('renders dynamic stage title and detail from statusNotifier', (tester) async {
      final notifier = ValueNotifier<ExitBackupStatus>(
        const ExitBackupStatus(
          phase: ExitBackupPhase.makingZip,
          title: 'Creating Zip Archive',
          detail: 'Exporting medicines and sales to ZIP...',
          currentStep: 1,
          totalSteps: 4,
          progressFraction: 0.3,
        ),
      );

      bool forceExitTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExitBackupDialog(
              statusNotifier: notifier,
              onForceExit: () => forceExitTriggered = true,
            ),
          ),
        ),
      );

      // Verify title and detail rendered
      expect(find.text('Creating Zip Archive'), findsOneWidget);
      expect(find.text('Exporting medicines and sales to ZIP...'), findsWidgets);
      expect(find.text('ZIP Archive'), findsOneWidget);
      expect(find.text('Google Drive'), findsOneWidget);
      expect(find.text('Cloud Sync'), findsOneWidget);

      // Update notifier to Google Drive upload
      notifier.value = notifier.value.copyWith(
        phase: ExitBackupPhase.uploadingDrive,
        title: 'Uploading to Google Drive',
        detail: 'Uploading mediposs_delta.zip (1.2 MB)...',
        currentStep: 3,
        progressFraction: 0.75,
      );

      await tester.pump();

      expect(find.text('Uploading to Google Drive'), findsOneWidget);
      expect(find.text('Uploading mediposs_delta.zip (1.2 MB)...'), findsWidgets);

      // Test force exit button
      await tester.tap(find.text('Close without Backup'));
      expect(forceExitTriggered, isTrue);
    });
  });
}
