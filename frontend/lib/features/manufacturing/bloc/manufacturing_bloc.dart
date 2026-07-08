import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/core/error/api_error_handler.dart';
import '../../logistics/domain/usecases/get_production_tracking_use_case.dart';
import '../../logistics/domain/usecases/synchronize_logistics_use_case.dart';
import '../../logistics/domain/usecases/set_preparation_status_use_case.dart';
import '../../logistics/domain/entities/sales_order_detail.dart';
import 'manufacturing_event.dart';
import 'manufacturing_state.dart';
import '../../../core/secure_storage_service.dart';

class ManufacturingBloc extends Bloc<ManufacturingEvent, ManufacturingState> {
  final GetProductionTrackingUseCase _getProductionTracking;
  final SynchronizeLogisticsUseCase _synchronizeLogistics;
  final SetPreparationStatusUseCase _setPreparationStatus;
  final SecureStorageService _storageService;

  ManufacturingBloc({
    required GetProductionTrackingUseCase getProductionTracking,
    required SynchronizeLogisticsUseCase synchronizeLogistics,
    required SetPreparationStatusUseCase setPreparationStatus,
    required SecureStorageService storageService,
  }) : _getProductionTracking = getProductionTracking,
       _synchronizeLogistics = synchronizeLogistics,
       _setPreparationStatus = setPreparationStatus,
       _storageService = storageService,
       super(const ManufacturingInitial()) {
    on<LoadProductionTrackingRequested>(_onLoadProductionTrackingRequested);
    on<SyncDataRequested>(_onSyncDataRequested);
    on<SiteFilterChanged>(_onSiteFilterChanged);
    on<DashboardSearchChanged>(_onDashboardSearchChanged);
    on<UpdateItemPreparationStatus>(_onUpdateItemPreparationStatus);
    on<ManufacturingSchemaChanged>(_onManufacturingSchemaChanged);
  }

  void _onSiteFilterChanged(
    SiteFilterChanged event,
    Emitter<ManufacturingState> emit,
  ) {
    emit(ManufacturingInitial(selectedSchema: state.selectedSchema)); 
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
          selectedSchema: state.selectedSchema,
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
    final targetDate = event.date ?? state.selectedDate ?? DateTime.now();
    emit(ManufacturingLoadInProgress(
      currentSiteCode: event.siteCode ?? state.currentSiteCode,
      dashboardSearchQuery: state.dashboardSearchQuery,
      selectedDate: targetDate,
      selectedSchema: state.selectedSchema,
    ));
    try {
      final result = await _getProductionTracking.execute(
        siteCode: event.siteCode ?? state.currentSiteCode,
        date: targetDate,
      );
      emit(
        ProductionTrackingLoaded(
          items: result['items'] as List<SalesOrderDetail>,
          excessPools: result['excessPools'] as Map<String, double>,
          currentSiteCode: event.siteCode ?? state.currentSiteCode,
          dashboardSearchQuery: state.dashboardSearchQuery,
          selectedDate: targetDate,
          selectedSchema: state.selectedSchema,
        ),
      );
    } catch (e) {
      emit(ManufacturingFailure(e.toString(), selectedSchema: state.selectedSchema));
    }
  }

  Future<void> _onSyncDataRequested(
    SyncDataRequested event,
    Emitter<ManufacturingState> emit,
  ) async {
    try {
      emit(
        ManufacturingSyncProgress(
          phase: SyncPhase.pushing,
          progress: 0.1,
          message: 'Preparing data update...',
          selectedDate: state.selectedDate,
          currentSiteCode: state.currentSiteCode,
          dashboardSearchQuery: state.dashboardSearchQuery,
          selectedSchema: state.selectedSchema,
        ),
      );

      // Step 1: Pushing
      emit(
        ManufacturingSyncProgress(
          phase: SyncPhase.pushing,
          progress: 0.3,
          message: 'Pushing local scans to server...',
          selectedDate: state.selectedDate,
          currentSiteCode: state.currentSiteCode,
          dashboardSearchQuery: state.dashboardSearchQuery,
          selectedSchema: state.selectedSchema,
        ),
      );

      // Step 2: Full Sync (Push + Pull handled in UseCase/Repo)
      await _synchronizeLogistics.execute(siteCode: event.siteCode);

      final targetDate = state.selectedDate ?? DateTime.now();
      
      emit(
        ManufacturingSyncProgress(
          phase: SyncPhase.pulling,
          progress: 0.7,
          message: 'Refreshing local mirrors...',
          selectedDate: targetDate,
          currentSiteCode: state.currentSiteCode,
          dashboardSearchQuery: state.dashboardSearchQuery,
          selectedSchema: state.selectedSchema,
        ),
      );

      emit(
        ManufacturingSyncProgress(
          phase: SyncPhase.success,
          progress: 1.0,
          message: 'Sync completed successfully!',
          selectedDate: targetDate,
          currentSiteCode: state.currentSiteCode,
          dashboardSearchQuery: state.dashboardSearchQuery,
          selectedSchema: state.selectedSchema,
        ),
      );

      // Hold success checkmark feedback for 1.5 seconds
      await Future.delayed(const Duration(milliseconds: 1500));

      // Reload local data after sync
      final result = await _getProductionTracking.execute(
        siteCode: event.siteCode ?? state.currentSiteCode,
        date: targetDate,
      );
      emit(
        ProductionTrackingLoaded(
          items: result['items'] as List<SalesOrderDetail>,
          excessPools: result['excessPools'] as Map<String, double>,
          currentSiteCode: event.siteCode ?? state.currentSiteCode,
          dashboardSearchQuery: state.dashboardSearchQuery,
          selectedDate: targetDate,
          selectedSchema: state.selectedSchema,
        ),
      );
    } catch (e) {
      emit(ManufacturingFailure('Sync failed: ${ApiErrorHandler.getErrorMessage(e)}', selectedSchema: state.selectedSchema));
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
          selectedSchema: state.selectedSchema,
        ));
      }
    } catch (e) {
      // In a real app we might want a specific error state or toast
      print('Failed to update preparation status: $e');
    }
  }

  Future<void> _onManufacturingSchemaChanged(
    ManufacturingSchemaChanged event,
    Emitter<ManufacturingState> emit,
  ) async {
    await _storageService.saveSchema(event.schema);
    
    // Clear state and reload data with the new schema target preserved in state
    emit(ManufacturingInitial(selectedSchema: event.schema)); 
    
    add(LoadProductionTrackingRequested(
      siteCode: state.currentSiteCode,
      date: state.selectedDate,
    ));
  }
}
