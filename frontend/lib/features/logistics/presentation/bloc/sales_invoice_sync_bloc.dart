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

    emit(const SalesInvoiceSyncInProgress('Synchronizing Mobile Sales Data...'));

    try {
      final batchResult = await _useCase.execute(siteCode: event.siteCode);
      if (batchResult.isTotalFailure) {
        emit(SalesInvoiceSyncFailure(
          batchResult.errorMessage ?? 'Synchronization failed. Could not communicate with server.',
          batchResult: batchResult,
        ));
      } else {
        final lastSync = DateTime.now().toString().substring(0, 16);
        emit(SalesInvoiceSyncSuccess(lastSync, batchResult));
      }
    } catch (e) {
      final errStr = e.toString();
      final isOffline = errStr.toLowerCase().contains('offline') ||
          errStr.toLowerCase().contains('connection') ||
          errStr.toLowerCase().contains('socketexception');
      final msg = isOffline
          ? 'Cannot sync while offline. All records are safely saved locally.'
          : errStr;
      emit(SalesInvoiceSyncFailure(msg));
    }
  }
}
