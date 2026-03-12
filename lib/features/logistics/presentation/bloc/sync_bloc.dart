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
    _progressSubscription = _synchronizeLogisticsUseCase.executeWithProgress().listen(
      (progress) {
        add(SyncProgressUpdated(progress.progress, progress.status));
      },
    );

    try {
      await _synchronizeLogisticsUseCase.execute();
      final lastSync = DateTime.now().toString().substring(0, 16);
      emit(SyncSuccess(lastSync));
    } catch (e) {
      emit(SyncFailure(e.toString()));
    } finally {
      await _progressSubscription?.cancel();
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
