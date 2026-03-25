import 'package:flutter_bloc/flutter_bloc.dart';
import '../../logistics/domain/usecases/get_production_tracking_use_case.dart';
import '../../logistics/domain/usecases/synchronize_logistics_use_case.dart';
import '../../logistics/domain/usecases/set_preparation_status_use_case.dart';
import 'manufacturing_event.dart';
import 'manufacturing_state.dart';

class ManufacturingBloc extends Bloc<ManufacturingEvent, ManufacturingState> {
  final GetProductionTrackingUseCase _getProductionTracking;
  final SynchronizeLogisticsUseCase _synchronizeLogistics;
  final SetPreparationStatusUseCase _setPreparationStatus;

  ManufacturingBloc({
    required GetProductionTrackingUseCase getProductionTracking,
    required SynchronizeLogisticsUseCase synchronizeLogistics,
    required SetPreparationStatusUseCase setPreparationStatus,
  }) : _getProductionTracking = getProductionTracking,
       _synchronizeLogistics = synchronizeLogistics,
       _setPreparationStatus = setPreparationStatus,
       super(ManufacturingInitial()) {
    on<LoadProductionTrackingRequested>(_onLoadProductionTrackingRequested);
    on<SyncDataRequested>(_onSyncDataRequested);
    on<SiteFilterChanged>(_onSiteFilterChanged);
    on<DashboardSearchChanged>(_onDashboardSearchChanged);
    on<UpdateItemPreparationStatus>(_onUpdateItemPreparationStatus);
  }

  void _onSiteFilterChanged(
    SiteFilterChanged event,
    Emitter<ManufacturingState> emit,
  ) {
    emit(ManufacturingInitial()); // Optional: clear items or keep them
    add(LoadProductionTrackingRequested(siteCode: event.siteCode));
  }

  void _onDashboardSearchChanged(
    DashboardSearchChanged event,
    Emitter<ManufacturingState> emit,
  ) {
    if (state is ProductionTrackingLoaded) {
      final currentState = state as ProductionTrackingLoaded;
      emit(
        ProductionTrackingLoaded(
          items: currentState.items,
          currentSiteCode: currentState.currentSiteCode,
          dashboardSearchQuery: event.query,
        ),
      );
    } else {
      // If not loaded, we still update the query in the state
      // This is a bit tricky if we want to persist it across states
      // For now, let's just emit a new state with the query
    }
  }

  Future<void> _onLoadProductionTrackingRequested(
    LoadProductionTrackingRequested event,
    Emitter<ManufacturingState> emit,
  ) async {
    emit(ManufacturingLoadInProgress());
    try {
      final items = await _getProductionTracking.execute(siteCode: event.siteCode);
      emit(
        ProductionTrackingLoaded(
          items: items,
          currentSiteCode: event.siteCode,
          dashboardSearchQuery: state.dashboardSearchQuery,
        ),
      );
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
      await _synchronizeLogistics.execute(siteCode: event.siteCode);

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
      final items = await _getProductionTracking.execute(siteCode: event.siteCode);
      emit(
        ProductionTrackingLoaded(
          items: items,
          currentSiteCode: event.siteCode,
          dashboardSearchQuery: state.dashboardSearchQuery,
        ),
      );
    } catch (e) {
      emit(ManufacturingFailure('Sync failed: $e'));
    }
  }

  Future<void> _onUpdateItemPreparationStatus(
    UpdateItemPreparationStatus event,
    Emitter<ManufacturingState> emit,
  ) async {
    try {
      await _setPreparationStatus.execute(
        soNumber: event.soNumber,
        itemCode: event.itemCode,
        isPrepared: event.isPrepared,
      );

      // Refresh data to reflect changes
      if (state is ProductionTrackingLoaded) {
        final currentState = state as ProductionTrackingLoaded;
        final updatedItems = currentState.items.map((item) {
          if (item.soNumber == event.soNumber &&
              item.itemCode == event.itemCode) {
            return item.copyWith(isPrepared: event.isPrepared);
          }
          return item;
        }).toList();

        emit(ProductionTrackingLoaded(
          items: updatedItems,
          currentSiteCode: currentState.currentSiteCode,
          dashboardSearchQuery: currentState.dashboardSearchQuery,
        ));
      }
    } catch (e) {
      // In a real app we might want a specific error state or toast
      print('Failed to update preparation status: $e');
    }
  }
}
