import 'package:flutter_bloc/flutter_bloc.dart';
import '../../logistics/domain/usecases/get_production_tracking_use_case.dart';
import '../../logistics/domain/usecases/synchronize_logistics_use_case.dart';
import 'manufacturing_event.dart';
import 'manufacturing_state.dart';

class ManufacturingBloc extends Bloc<ManufacturingEvent, ManufacturingState> {
  final GetProductionTrackingUseCase _getProductionTracking;
  final SynchronizeLogisticsUseCase _synchronizeLogistics;

  ManufacturingBloc({
    required GetProductionTrackingUseCase getProductionTracking,
    required SynchronizeLogisticsUseCase synchronizeLogistics,
  }) : _getProductionTracking = getProductionTracking,
       _synchronizeLogistics = synchronizeLogistics,
       super(ManufacturingInitial()) {
    on<LoadProductionTrackingRequested>(_onLoadProductionTrackingRequested);
    on<SyncDataRequested>(_onSyncDataRequested);
  }

  Future<void> _onLoadProductionTrackingRequested(
    LoadProductionTrackingRequested event,
    Emitter<ManufacturingState> emit,
  ) async {
    emit(ManufacturingLoadInProgress());
    try {
      final items = await _getProductionTracking.execute();
      emit(ProductionTrackingLoaded(items));
    } catch (e) {
      emit(ManufacturingFailure(e.toString()));
    }
  }

  Future<void> _onSyncDataRequested(
    SyncDataRequested event,
    Emitter<ManufacturingState> emit,
  ) async {
    try {
      emit(
        const ManufacturingSyncProgress(
          phase: SyncPhase.pushing,
          progress: 0.1,
          message: 'Preparing data update...',
        ),
      );

      // Step 1: Pushing
      emit(
        const ManufacturingSyncProgress(
          phase: SyncPhase.pushing,
          progress: 0.3,
          message: 'Pushing local scans to server...',
        ),
      );

      // Step 2: Full Sync (Push + Pull handled in UseCase/Repo)
      await _synchronizeLogistics.execute();

      emit(
        const ManufacturingSyncProgress(
          phase: SyncPhase.pulling,
          progress: 0.7,
          message: 'Refreshing local mirrors...',
        ),
      );

      emit(
        const ManufacturingSyncProgress(
          phase: SyncPhase.success,
          progress: 1.0,
          message: 'Sync completed successfully!',
        ),
      );

      // Reload local data after sync
      final items = await _getProductionTracking.execute();
      emit(ProductionTrackingLoaded(items));
    } catch (e) {
      emit(ManufacturingFailure('Sync failed: $e'));
    }
  }
}
