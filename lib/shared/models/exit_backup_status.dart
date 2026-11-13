enum ExitBackupPhase {
  preparing,
  makingZip,
  savingLocal,
  uploadingDrive,
  syncingCloud,
  complete,
  error,
}

class ExitBackupStatus {
  final ExitBackupPhase phase;
  final String title;
  final String detail;
  final int currentStep;
  final int totalSteps;
  final double? progressFraction;
  final bool isComplete;
  final String? errorMessage;

  const ExitBackupStatus({
    required this.phase,
    required this.title,
    required this.detail,
    required this.currentStep,
    this.totalSteps = 4,
    this.progressFraction,
    this.isComplete = false,
    this.errorMessage,
  });

  factory ExitBackupStatus.initial() {
    return const ExitBackupStatus(
      phase: ExitBackupPhase.preparing,
      title: 'Securing Your Data',
      detail: 'Initializing backup sequence...',
      currentStep: 1,
      totalSteps: 4,
      progressFraction: 0.05,
    );
  }

  ExitBackupStatus copyWith({
    ExitBackupPhase? phase,
    String? title,
    String? detail,
    int? currentStep,
    int? totalSteps,
    double? progressFraction,
    bool? isComplete,
    String? errorMessage,
  }) {
    return ExitBackupStatus(
      phase: phase ?? this.phase,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      currentStep: currentStep ?? this.currentStep,
      totalSteps: totalSteps ?? this.totalSteps,
      progressFraction: progressFraction ?? this.progressFraction,
      isComplete: isComplete ?? this.isComplete,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

