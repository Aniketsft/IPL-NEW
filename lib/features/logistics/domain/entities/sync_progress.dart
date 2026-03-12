class SyncProgress {
  final String status;
  final double progress; // 0.0 to 1.0
  final bool isCompleted;
  final String? error;

  SyncProgress({
    required this.status,
    required this.progress,
    this.isCompleted = false,
    this.error,
  });

  factory SyncProgress.initial() => SyncProgress(status: 'Starting...', progress: 0.0);
  factory SyncProgress.error(String message) => SyncProgress(status: 'Error', progress: 0.0, error: message);
  factory SyncProgress.completed() => SyncProgress(status: 'Completed', progress: 1.0, isCompleted: true);
}
