import '../../data/repositories/sales_invoice_sync_repository.dart';

abstract class SalesInvoiceSyncState {
  const SalesInvoiceSyncState();
}

class SalesInvoiceSyncInitial extends SalesInvoiceSyncState {}

class SalesInvoiceSyncInProgress extends SalesInvoiceSyncState {
  final String message;
  const SalesInvoiceSyncInProgress(this.message);
}

class SalesInvoiceSyncSuccess extends SalesInvoiceSyncState {
  final String lastSyncTime;
  final SyncBatchResult batchResult;
  const SalesInvoiceSyncSuccess(this.lastSyncTime, this.batchResult);
}

class SalesInvoiceSyncFailure extends SalesInvoiceSyncState {
  final String error;
  const SalesInvoiceSyncFailure(this.error);
}
