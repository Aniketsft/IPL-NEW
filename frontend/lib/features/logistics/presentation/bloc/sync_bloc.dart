import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/repositories/delivery_repository.dart';
import '../../domain/usecases/synchronize_logistics_use_case.dart';
import 'sync_event.dart';
import 'sync_state.dart';
import 'package:enterprise_auth_mobile/core/bloc/app_sync/app_sync_bloc.dart';
import 'package:enterprise_auth_mobile/core/bloc/app_sync/app_sync_event.dart';

class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final SynchronizeLogisticsUseCase _synchronizeLogisticsUseCase;
  final AppSyncBloc _appSyncBloc;
  StreamSubscription? _progressSubscription;

  SyncBloc({
    required SynchronizeLogisticsUseCase synchronizeLogisticsUseCase,
    required AppSyncBloc appSyncBloc,
  }) : _synchronizeLogisticsUseCase = synchronizeLogisticsUseCase,
       _appSyncBloc = appSyncBloc,
       super(SyncInitial()) {
    on<StartSyncRequested>(_onStartSyncRequested);
    on<SyncProgressUpdated>(_onSyncProgressUpdated);
    on<ResetSyncRequested>((event, emit) => emit(SyncInitial()));
    on<StartX3SoapExportRequested>(_onStartX3SoapExportRequested);
  }

  Future<void> _onStartX3SoapExportRequested(
    StartX3SoapExportRequested event,
    Emitter<SyncState> emit,
  ) async {
    if (state is SyncInProgress) {
      print("SyncBloc: Action already in progress, ignoring request.");
      return;
    }

    emit(SyncInProgress(0.5, event.message));

    try {
      await event.exportAction();
      final lastSync = DateTime.now().toString().substring(0, 16);
      _appSyncBloc.add(UpdateAppSyncTimeEvent(lastSync));
      emit(SyncSuccess(lastSync));
    } catch (e) {
      emit(SyncFailure(e.toString()));
    }
  }

  Future<void> _onStartSyncRequested(
    StartSyncRequested event,
    Emitter<SyncState> emit,
  ) async {
    // Prevent overlapping sync requests at the Bloc level
    if (state is SyncInProgress || (_synchronizeLogisticsUseCase.repository is DeliveryRepository && 
        (_synchronizeLogisticsUseCase.repository as DeliveryRepository).isSyncing)) {
      print("SyncBloc: Sync already in progress, ignoring request.");
      return;
    }

    emit(const SyncInProgress(0.0, 'Initializing sync...'));

    await _progressSubscription?.cancel();

    // Use a Completer to await the stream's natural completion.
    // Previously, both executeWithProgress() AND execute() were called
    // concurrently, causing a double-sync race condition that zeroed
    // scanned quantities.
    final completer = Completer<void>();
    String? syncError;

    _progressSubscription = _synchronizeLogisticsUseCase.executeWithProgress(siteCode: event.siteCode).listen(
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
      _appSyncBloc.add(UpdateAppSyncTimeEvent(lastSync));
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
