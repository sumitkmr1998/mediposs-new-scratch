import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:medipos/shared/models/exit_backup_status.dart';
import 'package:medipos/widgets/exit_backup_dialog.dart';

/// Helper mirroring the exact decision logic in SettingsProvider.checkAndPerformAutoBackup
bool evaluateShouldAutoBackup({
  required String frequency, // 'Never', 'Daily', 'Weekly', 'Monthly', 'Always'
  required String configuredLogic, // 'At Startup', 'On Close', 'Periodic'
  required String? scheduledTime, // e.g. '22:00'
  required DateTime? lastBackup,
  required DateTime now,
  required String currentTrigger, // 'At Startup', 'On Close', 'Periodic'
}) {
  if (frequency == 'Never') return false;

  final isDifferentDay = lastBackup == null ||
      (lastBackup.year != now.year ||
          lastBackup.month != now.month ||
          lastBackup.day != now.day);

  bool isPastScheduledTime = true;
  if (scheduledTime != null && scheduledTime.isNotEmpty) {
    try {
      final parts = scheduledTime.split(':');
      final scheduledHour = int.parse(parts[0]);
      final scheduledMinute = int.parse(parts[1]);
      if (now.hour < scheduledHour ||
          (now.hour == scheduledHour && now.minute < scheduledMinute)) {
        isPastScheduledTime = false;
      }
    } catch (_) {}
  }

  final isConfiguredTrigger = configuredLogic == currentTrigger;
  final isCloseCatchUp = currentTrigger == 'On Close' && isDifferentDay;
  final isPeriodicCatchUp =
      currentTrigger == 'Periodic' && isDifferentDay && isPastScheduledTime;

  if (!isConfiguredTrigger && !isCloseCatchUp && !isPeriodicCatchUp) {
    return false;
  }

  if (frequency == 'Daily') {
    if (currentTrigger == 'Periodic') {
      return (isDifferentDay && isPastScheduledTime) ||
          (lastBackup != null && now.difference(lastBackup).inHours >= 24) ||
          lastBackup == null;
    } else {
      return isDifferentDay;
    }
  } else if (frequency == 'Weekly') {
    final daysSince = lastBackup == null
        ? 999
        : now
            .difference(
                DateTime(lastBackup.year, lastBackup.month, lastBackup.day))
            .inDays;
    if (currentTrigger == 'Periodic') {
      return daysSince >= 7 && isPastScheduledTime;
    } else {
      return daysSince >= 7;
    }
  } else if (frequency == 'Monthly') {
    final monthsDiff = lastBackup == null
        ? 999
        : (now.year - lastBackup.year) * 12 +
            (now.month - lastBackup.month);
    if (currentTrigger == 'Periodic') {
      return monthsDiff >= 1 && isPastScheduledTime;
    } else {
      return monthsDiff >= 1;
    }
  } else if (frequency == 'Always') {
    return true;
  }

  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Auto-Backup Workflow Trigger & Schedule Tests', () {
    test('On Close trigger executes when closing before 22:00 (Daily Frequency)', () {
      // Clinic closes at 5:30 PM (17:30), autoBackupTime is 22:00
      final now = DateTime(2026, 11, 6, 17, 30);
      final lastBackup = DateTime(2026, 11, 5, 22, 0); // Yesterday

      final shouldRun = evaluateShouldAutoBackup(
        frequency: 'Daily',
        configuredLogic: 'On Close',
        scheduledTime: '22:00',
        lastBackup: lastBackup,
        now: now,
        currentTrigger: 'On Close',
      );

      expect(shouldRun, isTrue,
          reason: 'Daily backup on close must run even if current hour (17) < scheduled 22:00');
    });

    test('On Close trigger does not repeat if backup was already done today (Daily)', () {
      final now = DateTime(2026, 11, 6, 18, 0);
      final lastBackup = DateTime(2026, 11, 6, 17, 30); // Earlier today

      final shouldRun = evaluateShouldAutoBackup(
        frequency: 'Daily',
        configuredLogic: 'On Close',
        scheduledTime: '22:00',
        lastBackup: lastBackup,
        now: now,
        currentTrigger: 'On Close',
      );

      expect(shouldRun, isFalse,
          reason: 'Daily backup on close should not duplicate if already performed today');
    });

    test('On Close trigger runs every time when frequency is Always', () {
      final now = DateTime(2026, 11, 6, 18, 0);
      final lastBackup = DateTime(2026, 11, 6, 17, 30); // Earlier today

      final shouldRun = evaluateShouldAutoBackup(
        frequency: 'Always',
        configuredLogic: 'On Close',
        scheduledTime: '22:00',
        lastBackup: lastBackup,
        now: now,
        currentTrigger: 'On Close',
      );

      expect(shouldRun, isTrue,
          reason: 'Frequency "Always" should run on every close');
    });

    test('On Close acts as catch-up even if configuredLogic was Periodic or At Startup', () {
      // If user had logic set to Periodic or At Startup, but closes the app with no backup yet today
      final now = DateTime(2026, 11, 6, 19, 0);
      final lastBackup = DateTime(2026, 11, 5, 12, 0); // Yesterday

      final shouldRunPeriodicLogic = evaluateShouldAutoBackup(
        frequency: 'Daily',
        configuredLogic: 'Periodic',
        scheduledTime: '22:00',
        lastBackup: lastBackup,
        now: now,
        currentTrigger: 'On Close',
      );

      expect(shouldRunPeriodicLogic, isTrue,
          reason: 'On Close must protect against data loss when shutting down before scheduled periodic time');

      final shouldRunStartupLogic = evaluateShouldAutoBackup(
        frequency: 'Daily',
        configuredLogic: 'At Startup',
        scheduledTime: '22:00',
        lastBackup: lastBackup,
        now: now,
        currentTrigger: 'On Close',
      );

      expect(shouldRunStartupLogic, isTrue,
          reason: 'On Close must protect against data loss even if configured as At Startup');
    });

    test('At Startup triggers on new day in the morning (before 22:00)', () {
      final morning = DateTime(2026, 11, 6, 9, 15);
      final lastBackup = DateTime(2026, 11, 5, 20, 0);

      final shouldRun = evaluateShouldAutoBackup(
        frequency: 'Daily',
        configuredLogic: 'At Startup',
        scheduledTime: '22:00',
        lastBackup: lastBackup,
        now: morning,
        currentTrigger: 'At Startup',
      );

      expect(shouldRun, isTrue,
          reason: 'At Startup must execute on morning launch without waiting for 22:00');
    });

    test('Periodic trigger waits for scheduled time on same day', () {
      final afternoon = DateTime(2026, 11, 6, 14, 0);
      final lastBackup = DateTime(2026, 11, 5, 22, 10); // Yesterday

      final shouldRunBefore = evaluateShouldAutoBackup(
        frequency: 'Daily',
        configuredLogic: 'Periodic',
        scheduledTime: '22:00',
        lastBackup: lastBackup,
        now: afternoon,
        currentTrigger: 'Periodic',
      );

      expect(shouldRunBefore, isFalse,
          reason: 'Periodic timer at 14:00 should not trigger daily backup scheduled for 22:00');

      final night = DateTime(2026, 11, 6, 22, 5);
      final shouldRunAfter = evaluateShouldAutoBackup(
        frequency: 'Daily',
        configuredLogic: 'Periodic',
        scheduledTime: '22:00',
        lastBackup: lastBackup,
        now: night,
        currentTrigger: 'Periodic',
      );

      expect(shouldRunAfter, isTrue,
          reason: 'Periodic timer after 22:00 on a new day must trigger backup');
    });

    test('Periodic trigger forces catch-up when 24 hours have elapsed', () {
      final now = DateTime(2026, 11, 6, 16, 0);
      final lastBackup = DateTime(2026, 11, 5, 14, 0); // 26 hours ago

      final shouldRun = evaluateShouldAutoBackup(
        frequency: 'Daily',
        configuredLogic: 'Periodic',
        scheduledTime: '22:00',
        lastBackup: lastBackup,
        now: now,
        currentTrigger: 'Periodic',
      );

      expect(shouldRun, isTrue,
          reason: 'Periodic must trigger catch-up if >24 hours have elapsed since last backup');
    });

    test('Never frequency disables backup regardless of trigger', () {
      final now = DateTime(2026, 11, 6, 23, 0);
      expect(
        evaluateShouldAutoBackup(
          frequency: 'Never',
          configuredLogic: 'On Close',
          scheduledTime: '22:00',
          lastBackup: null,
          now: now,
          currentTrigger: 'On Close',
        ),
        isFalse,
      );
      expect(
        evaluateShouldAutoBackup(
          frequency: 'Never',
          configuredLogic: 'Periodic',
          scheduledTime: '22:00',
          lastBackup: null,
          now: now,
          currentTrigger: 'Periodic',
        ),
        isFalse,
      );
    });
  });

  group('Local Backup Retention & Directory Logic Tests', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('medipos_backup_test_');
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('Creates backup subfolders (daily and full) and copies file', () async {
      final dailyDir = Directory(p.join(tempRoot.path, 'daily'));
      await dailyDir.create(recursive: true);

      // Create a dummy backup zip
      final dummyZip = File(p.join(tempRoot.path, 'mediposs_delta_test.zip'));
      await dummyZip.writeAsString('test zip content');

      // Copy to daily dir
      final targetPath = p.join(dailyDir.path, p.basename(dummyZip.path));
      final copied = await dummyZip.copy(targetPath);

      expect(await copied.exists(), isTrue);
      expect(await copied.readAsString(), equals('test zip content'));
    });

    test('Cleans up files older than retention policy while keeping recent ones', () async {
      final backupDir = Directory(p.join(tempRoot.path, 'daily'));
      await backupDir.create(recursive: true);

      final now = DateTime.now();

      // Recent backup (today)
      final recentFile = File(p.join(backupDir.path, 'mediposs_recent.zip'));
      await recentFile.writeAsString('recent');

      // Old backup (20 days old)
      final oldFile = File(p.join(backupDir.path, 'mediposs_old.zip'));
      await oldFile.writeAsString('old');
      await oldFile.setLastModified(now.subtract(const Duration(days: 20)));

      // Simulate cleanup logic (keep 14 days for daily deltas)
      const daysToKeep = 14;
      final expirationDate = now.subtract(const Duration(days: daysToKeep));

      final files = backupDir.listSync().whereType<File>();
      for (final file in files) {
        if (p.extension(file.path) == '.zip') {
          final stats = await file.stat();
          if (stats.modified.isBefore(expirationDate)) {
            await file.delete();
          }
        }
      }

      expect(await recentFile.exists(), isTrue, reason: 'Recent file should be kept');
      expect(await oldFile.exists(), isFalse, reason: 'File older than 14 days should be purged');
    });
  });

  group('ExitBackupDialog Visual Workflow Tests', () {
    testWidgets('Steps accurately reflect Local Save, Google Drive, and Cloud Sync',
        (tester) async {
      final statusNotifier = ValueNotifier<ExitBackupStatus>(
        const ExitBackupStatus(
          phase: ExitBackupPhase.makingZip,
          title: 'Creating Zip Archive',
          detail: 'Exporting database tables into ZIP...',
          currentStep: 1,
          totalSteps: 4,
          progressFraction: 0.15,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExitBackupDialog(
              statusNotifier: statusNotifier,
              onForceExit: () {},
            ),
          ),
        ),
      );

      // Verify Step 1: ZIP Archive
      expect(find.text('Creating Zip Archive'), findsOneWidget);
      expect(find.text('ZIP Archive'), findsOneWidget);

      // Step 2: Local Save with path
      statusNotifier.value = statusNotifier.value.copyWith(
        phase: ExitBackupPhase.savingLocal,
        title: 'Local Backup Saved',
        detail: 'Saved to Documents\\MediPoss Backups\\daily\\mediposs_delta.zip',
        currentStep: 2,
        progressFraction: 0.65,
      );
      await tester.pump();

      expect(find.text('Local Backup Saved'), findsOneWidget);
      expect(find.text('Saved to Documents\\MediPoss Backups\\daily\\mediposs_delta.zip'),
          findsWidgets);

      // Step 3: Google Drive Uploaded
      statusNotifier.value = statusNotifier.value.copyWith(
        phase: ExitBackupPhase.uploadingDrive,
        title: 'Google Drive Uploaded',
        detail: 'Cloud backup uploaded successfully to Google Drive.',
        currentStep: 3,
        progressFraction: 0.88,
      );
      await tester.pump();

      expect(find.text('Google Drive Uploaded'), findsOneWidget);

      // Step 4: Cloud Sync
      statusNotifier.value = statusNotifier.value.copyWith(
        phase: ExitBackupPhase.syncingCloud,
        title: 'Syncing Cloud Mirror',
        detail: 'Broadcasting recent mutations to Cloud...',
        currentStep: 4,
        progressFraction: 0.95,
      );
      await tester.pump();

      expect(find.text('Syncing Cloud Mirror'), findsOneWidget);

      // Complete
      statusNotifier.value = statusNotifier.value.copyWith(
        phase: ExitBackupPhase.complete,
        title: 'Backup Complete!',
        detail: 'All data secured. Closing MediPoss...',
        currentStep: 4,
        progressFraction: 1.0,
        isComplete: true,
      );
      await tester.pump();

      expect(find.text('Backup Complete!'), findsOneWidget);
    });

    testWidgets('Detail message wraps cleanly up to 2 lines without throwing overflow',
        (tester) async {
      final statusNotifier = ValueNotifier<ExitBackupStatus>(
        const ExitBackupStatus(
          phase: ExitBackupPhase.savingLocal,
          title: 'Saving Local Backup',
          detail:
              'C:\\Users\\Pharmacist\\Documents\\MediPoss Backups\\daily\\mediposs_delta_2026-11-06T17-30-00.zip',
          currentStep: 2,
          totalSteps: 4,
          progressFraction: 0.55,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ExitBackupDialog(
                statusNotifier: statusNotifier,
                onForceExit: () {},
              ),
            ),
          ),
        ),
      );

      // Should render without any Flutter overflow errors
      expect(tester.takeException(), isNull);
    });
  });
}

