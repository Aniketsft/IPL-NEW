import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/synchronize_logistics_use_case.dart';
import 'sync_event.dart';
import 'sync_state.dart';

class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final SynchronizeLogisticsUseCase _synchronizeLogisticsUseCase;
  StreamSubscription? _progressSubscription;

  SyncBloc({
    required SynchronizeLogisticsUseCase synchronizeLogisticsUseCase,
  }) : _synchronizeLogisticsUseCase = synchronizeLogisticsUseCase,
       super(SyncInitial()) {
    on<StartSyncRequested>(_onStartSyncRequested);
    on<SyncProgressUpdated>(_onSyncProgressUpdated);
  }

  Future<void> _onStartSyncRequested(
    StartSyncRequested event,
    Emitter<SyncState> emit,
  ) async {
    emit(const SyncInProgress(0.0, 'Initializing sync...'));

    await _progressSubscription?.cancel();

    // Use a Completer to await the stream's natural completion.
    // Previously, both executeWithProgress() AND execute() were called
    // concurrently, causing a double-sync race condition that zeroed
    // manufactured quantities.
    final completer = Completer<void>();
    String? syncError;

    _progressSubscription = _synchronizeLogisticsUseCase.executeWithProgress().listen(
      (progress) {
        add(SyncProgressUpdated(progress.progress, progress.status));
      },
      onError: (e) {
        syncError = e.toString();
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
    );

    await completer.future;
    await _progressSubscription?.cancel();

    if (syncError != null) {
      emit(SyncFailure(syncError!));
    } else {
      final lastSync = DateTime.now().toString().substring(0, 16);
      emit(SyncSuccess(lastSync));
    }
  }

  void _onSyncProgressUpdated(
    SyncProgressUpdated event,
    Emitter<SyncState> emit,
  ) {
    if (state is SyncInProgress) {
      emit(SyncInProgress(event.progress, event.message));
    }
  }

  @override
  Future<void> close() {
    _progressSubscription?.cancel();
    return super.close();
  }
}
