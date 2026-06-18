import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/synchronize_sales_invoice_use_case.dart';
import 'sales_invoice_sync_event.dart';
import 'sales_invoice_sync_state.dart';

class SalesInvoiceSyncBloc extends Bloc<SalesInvoiceSyncEvent, SalesInvoiceSyncState> {
  final SynchronizeSalesInvoiceUseCase _useCase;

  SalesInvoiceSyncBloc({
    required SynchronizeSalesInvoiceUseCase synchronizeSalesInvoiceUseCase,
  })  : _useCase = synchronizeSalesInvoiceUseCase,
        super(SalesInvoiceSyncInitial()) {
    on<StartSalesInvoiceSyncRequested>(_onStartSyncRequested);
    on<ResetSalesInvoiceSyncRequested>((event, emit) => emit(SalesInvoiceSyncInitial()));
  }

  Future<void> _onStartSyncRequested(
    StartSalesInvoiceSyncRequested event,
    Emitter<SalesInvoiceSyncState> emit,
  ) async {
    if (state is SalesInvoiceSyncInProgress) return;

    emit(const SalesInvoiceSyncInProgress('Synchronizing Sales Invoice Data...'));

    try {
      final batchResult = await _useCase.execute(siteCode: event.siteCode);
      final lastSync = DateTime.now().toString().substring(0, 16);
      emit(SalesInvoiceSyncSuccess(lastSync, batchResult));
    } catch (e) {
      emit(SalesInvoiceSyncFailure(e.toString()));
    }
  }
}
