import 'package:flutter_bloc/flutter_bloc.dart';
import '../../logistics/domain/usecases/get_production_tracking_use_case.dart';
import 'manufacturing_event.dart';
import 'manufacturing_state.dart';

class ManufacturingBloc extends Bloc<ManufacturingEvent, ManufacturingState> {
  final GetProductionTrackingUseCase _getProductionTracking;

  ManufacturingBloc({
    required GetProductionTrackingUseCase getProductionTracking,
  }) : _getProductionTracking = getProductionTracking,
       super(ManufacturingInitial()) {
    on<LoadProductionTrackingRequested>(_onLoadProductionTrackingRequested);
  }

  Future<void> _onLoadProductionTrackingRequested(
    LoadProductionTrackingRequested event,
    Emitter<ManufacturingState> emit,
  ) async {
    emit(ManufacturingLoadInProgress());
    try {
      final items = await _getProductionTracking.execute(
        location: event.location,
      );
      emit(ProductionTrackingLoaded(items));
    } catch (e) {
      emit(ManufacturingFailure(e.toString()));
    }
  }
}
