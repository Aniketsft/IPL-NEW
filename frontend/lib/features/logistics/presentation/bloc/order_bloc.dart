import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/get_production_tracking_use_case.dart';
import '../../domain/usecases/get_sites_use_case.dart';
import '../../domain/usecases/get_customers_use_case.dart';
import '../../domain/usecases/get_sales_reps_use_case.dart';
import 'order_event.dart';
import 'order_state.dart';

class OrderBloc extends Bloc<OrderEvent, OrderState> {
  final GetProductionTrackingUseCase _getProductionTrackingUseCase;
  final GetSitesUseCase _getSitesUseCase;
  final GetCustomersUseCase _getCustomersUseCase;
  final GetSalesRepsUseCase _getSalesRepsUseCase;

  OrderBloc({
    required GetProductionTrackingUseCase getProductionTrackingUseCase,
    required GetSitesUseCase getSitesUseCase,
    required GetCustomersUseCase getCustomersUseCase,
    required GetSalesRepsUseCase getSalesRepsUseCase,
  }) : _getProductionTrackingUseCase = getProductionTrackingUseCase,
       _getSitesUseCase = getSitesUseCase,
       _getCustomersUseCase = getCustomersUseCase,
       _getSalesRepsUseCase = getSalesRepsUseCase,
       super(OrderInitial()) {
    on<LoadSalesOrderItemsRequested>(_onLoadSalesOrderItemsRequested);
    on<LoadFiltersRequested>(_onLoadFiltersRequested);
  }

  Future<void> _onLoadFiltersRequested(
    LoadFiltersRequested event,
    Emitter<OrderState> emit,
  ) async {
    try {
      final sites = await _getSitesUseCase();
      final customers = await _getCustomersUseCase();
      final salesReps = await _getSalesRepsUseCase();

      if (state is SalesOrderItemsLoaded) {
        final currentState = state as SalesOrderItemsLoaded;
        emit(currentState.copyWith(
          sites: sites,
          customers: customers,
          salesReps: salesReps,
        ));
      } else {
        emit(SalesOrderItemsLoaded(
          items: const [],
          sites: sites,
          customers: customers,
          salesReps: salesReps,
        ));
      }
    } catch (e) {
      emit(OrderFailure(e.toString()));
    }
  }

  Future<void> _onLoadSalesOrderItemsRequested(
    LoadSalesOrderItemsRequested event,
    Emitter<OrderState> emit,
  ) async {
    final currentItemsState = state is SalesOrderItemsLoaded ? state as SalesOrderItemsLoaded : null;
    emit(OrderLoadInProgress());
    try {
      final items = await _getProductionTrackingUseCase.execute(
        siteCode: event.site,
        customerCode: event.customerCode,
        salesRepCode: event.salesRepCode,
        date: event.date,
      );
      
      if (currentItemsState != null) {
        emit(currentItemsState.copyWith(
          items: items,
          selectedDate: event.date,
          selectedSite: event.site,
          selectedCustomer: event.customerCode,
          selectedSalesRep: event.salesRepCode,
        ));
      } else {
        emit(SalesOrderItemsLoaded(
          items: items,
          selectedDate: event.date,
          selectedSite: event.site,
          selectedCustomer: event.customerCode,
          selectedSalesRep: event.salesRepCode,
        ));
      }
    } catch (e) {
      emit(OrderFailure(e.toString()));
    }
  }
}
