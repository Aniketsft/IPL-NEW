import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/get_production_tracking_use_case.dart';
import 'order_event.dart';
import 'order_state.dart';

class OrderBloc extends Bloc<OrderEvent, OrderState> {
  final GetProductionTrackingUseCase _getProductionTrackingUseCase;

  OrderBloc({
    required GetProductionTrackingUseCase getProductionTrackingUseCase,
  }) : _getProductionTrackingUseCase = getProductionTrackingUseCase,
       super(OrderInitial()) {
    on<LoadSalesOrderItemsRequested>(_onLoadSalesOrderItemsRequested);
  }

  Future<void> _onLoadSalesOrderItemsRequested(
    LoadSalesOrderItemsRequested event,
    Emitter<OrderState> emit,
  ) async {
    emit(OrderLoadInProgress());
    try {
      final items = await _getProductionTrackingUseCase.execute();
      emit(SalesOrderItemsLoaded(items));
    } catch (e) {
      emit(OrderFailure(e.toString()));
    }
  }
}
