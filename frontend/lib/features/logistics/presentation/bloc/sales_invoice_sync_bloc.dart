import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/repositories/sales_invoice_sync_repository.dart';
import '../../domain/usecases/synchronize_sales_invoice_use_case.dart';
import 'sales_invoice_sync_event.dart';
import 'sales_invoice_sync_state.dart';

class SalesInvoiceSyncBloc extends Bloc<SalesInvoiceSyncEvent, SalesInvoiceSyncState> {
  final SynchronizeSalesInvoiceUseCase _useCase;
  final SalesInvoiceSyncRepository _repository;

  SalesInvoiceSyncBloc({
    required SynchronizeSalesInvoiceUseCase synchronizeSalesInvoiceUseCase,
    required SalesInvoiceSyncRepository repository,
  })  : _useCase = synchronizeSalesInvoiceUseCase,
        _repository = repository,
        super(SalesInvoiceSyncInitial()) {
    on<StartSalesInvoiceSyncRequested>(_onStartSyncRequested);
    on<StartSingleCustomerSyncRequested>(_onStartCustomerSyncRequested);
    on<ResetSalesInvoiceSyncRequested>((event, emit) => emit(SalesInvoiceSyncInitial()));
  }

  Future<void> _onStartSyncRequested(
    StartSalesInvoiceSyncRequested event,
    Emitter<SalesInvoiceSyncState> emit,
  ) async {
    if (state is SalesInvoiceSyncInProgress || state is SalesInvoiceCustomerSyncInProgress) return;

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

  Future<void> _onStartCustomerSyncRequested(
    StartSingleCustomerSyncRequested event,
    Emitter<SalesInvoiceSyncState> emit,
  ) async {
    if (state is SalesInvoiceSyncInProgress || state is SalesInvoiceCustomerSyncInProgress) return;

    emit(SalesInvoiceCustomerSyncInProgress(
      customerCode: event.customerCode,
      customerName: event.customerName,
      message: 'Fetching live balance, open invoices & 6-month X3 history for ${event.customerName}...',
    ));

    try {
      final result = await _repository.syncSingleCustomerData(
        customerCode: event.customerCode,
        siteCode: event.siteCode,
      );

      if (result.success) {
        final lastSync = DateTime.now().toString().substring(0, 16);
        emit(SalesInvoiceCustomerSyncSuccess(
          customerCode: event.customerCode,
          customerName: event.customerName,
          lastSyncTime: lastSync,
          result: result,
        ));
      } else {
        emit(SalesInvoiceCustomerSyncFailure(
          customerCode: event.customerCode,
          customerName: event.customerName,
          error: result.errorMessage ?? 'Failed to synchronize customer data from Sage X3.',
        ));
      }
    } catch (e) {
      final errStr = e.toString();
      final isOffline = errStr.toLowerCase().contains('offline') ||
          errStr.toLowerCase().contains('connection') ||
          errStr.toLowerCase().contains('socketexception');
      final msg = isOffline
          ? 'Cannot sync while offline. Customer data safely stored locally.'
          : errStr;
      emit(SalesInvoiceCustomerSyncFailure(
        customerCode: event.customerCode,
        customerName: event.customerName,
        error: msg,
      ));
    }
  }
}
