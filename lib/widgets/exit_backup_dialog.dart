import 'package:flutter/material.dart';
import '../shared/models/exit_backup_status.dart';
import '../theme/app_theme.dart';

class ExitBackupDialog extends StatefulWidget {
  final VoidCallback onForceExit;
  final ValueNotifier<ExitBackupStatus>? statusNotifier;

  const ExitBackupDialog({
    super.key,
    required this.onForceExit,
    this.statusNotifier,
  });

  @override
  State<ExitBackupDialog> createState() => _ExitBackupDialogState();
}

class _ExitBackupDialogState extends State<ExitBackupDialog> {
  late final ValueNotifier<ExitBackupStatus> _effectiveNotifier;
  bool _ownsNotifier = false;

  @override
  void initState() {
    super.initState();
    if (widget.statusNotifier != null) {
      _effectiveNotifier = widget.statusNotifier!;
    } else {
      _effectiveNotifier = ValueNotifier<ExitBackupStatus>(ExitBackupStatus.initial());
      _ownsNotifier = true;
    }
  }

  @override
  void dispose() {
    if (_ownsNotifier) {
      _effectiveNotifier.dispose();
    }
    super.dispose();
  }

  IconData _getPhaseIcon(ExitBackupPhase phase) {
    switch (phase) {
      case ExitBackupPhase.makingZip:
        return Icons.folder_zip_rounded;
      case ExitBackupPhase.savingLocal:
        return Icons.save_rounded;
      case ExitBackupPhase.uploadingDrive:
        return Icons.cloud_upload_rounded;
      case ExitBackupPhase.syncingCloud:
        return Icons.cloud_sync_rounded;
      case ExitBackupPhase.complete:
        return Icons.check_circle_rounded;
      case ExitBackupPhase.error:
        return Icons.warning_amber_rounded;
      case ExitBackupPhase.preparing:
        return Icons.security_rounded;
    }
  }

  Color _getPhaseColor(ExitBackupPhase phase) {
    switch (phase) {
      case ExitBackupPhase.makingZip:
        return Colors.amber.shade700;
      case ExitBackupPhase.savingLocal:
        return AppTheme.primary;
      case ExitBackupPhase.uploadingDrive:
        return Colors.blue.shade600;
      case ExitBackupPhase.syncingCloud:
        return Colors.indigo.shade600;
      case ExitBackupPhase.complete:
        return AppTheme.success;
      case ExitBackupPhase.error:
        return AppTheme.danger;
      case ExitBackupPhase.preparing:
        return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false, // Prevent closing with ESC while backing up
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 500,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ValueListenableBuilder<ExitBackupStatus>(
            valueListenable: _effectiveNotifier,
            builder: (context, status, _) {
              final activeColor = _getPhaseColor(status.phase);
              final activeIcon = _getPhaseIcon(status.phase);
              final isDone = status.phase == ExitBackupPhase.complete;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header Animated Icon Badge
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (!isDone)
                          SizedBox(
                            width: 68,
                            height: 68,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              value: status.progressFraction,
                              valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                              backgroundColor: activeColor.withValues(alpha: 0.15),
                            ),
                          ),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: activeColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            activeIcon,
                            color: activeColor,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Dynamic Title
                  Text(
                    status.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                  ),
                  const SizedBox(height: 8),

                  // Subtitle / Detail Description
                  Text(
                    status.detail,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.7),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 4-Step Tracker Row
                  Row(
                    children: [
                      _buildStepPill(
                        stepIndex: 1,
                        currentStep: status.currentStep,
                        isComplete: isDone,
                        label: 'ZIP Archive',
                        icon: Icons.folder_zip_outlined,
                        context: context,
                      ),
                      const SizedBox(width: 6),
                      _buildStepPill(
                        stepIndex: 2,
                        currentStep: status.currentStep,
                        isComplete: isDone,
                        label: 'Local Save',
                        icon: Icons.save_outlined,
                        context: context,
                      ),
                      const SizedBox(width: 6),
                      _buildStepPill(
                        stepIndex: 3,
                        currentStep: status.currentStep,
                        isComplete: isDone,
                        label: 'Google Drive',
                        icon: Icons.cloud_upload_outlined,
                        context: context,
                      ),
                      const SizedBox(width: 6),
                      _buildStepPill(
                        stepIndex: 4,
                        currentStep: status.currentStep,
                        isComplete: isDone,
                        label: 'Cloud Sync',
                        icon: Icons.cloud_sync_outlined,
                        context: context,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: status.progressFraction,
                      minHeight: 6,
                      backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Current Activity Detail Box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: activeColor.withValues(alpha: 0.15),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          activeIcon,
                          color: activeColor,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            status.detail,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface.withValues(alpha: 0.9),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (status.progressFraction != null)
                          Text(
                            '${(status.progressFraction! * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: activeColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Force Exit Button
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(
                              color: cs.outline.withValues(alpha: 0.25),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: widget.onForceExit,
                          child: Text(
                            'Close without Backup',
                            style: TextStyle(
                              color: AppTheme.danger.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStepPill({
    required int stepIndex,
    required int currentStep,
    required bool isComplete,
    required String label,
    required IconData icon,
    required BuildContext context,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isPassed = isComplete || currentStep > stepIndex;
    final isActive = !isComplete && currentStep == stepIndex;

    Color bg;
    Color border;
    Color fg;

    if (isPassed) {
      bg = AppTheme.success.withValues(alpha: 0.12);
      border = AppTheme.success.withValues(alpha: 0.3);
      fg = AppTheme.success;
    } else if (isActive) {
      bg = AppTheme.primary.withValues(alpha: 0.12);
      border = AppTheme.primary.withValues(alpha: 0.4);
      fg = AppTheme.primary;
    } else {
      bg = cs.surfaceContainerHighest.withValues(alpha: 0.2);
      border = Colors.transparent;
      fg = cs.onSurface.withValues(alpha: 0.4);
    }

    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPassed ? Icons.check_circle_rounded : icon,
              size: 14,
              color: fg,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                color: fg,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
