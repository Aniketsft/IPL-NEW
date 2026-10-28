import '../../data/repositories/sales_invoice_sync_repository.dart';

abstract class SalesInvoiceSyncState {
  const SalesInvoiceSyncState();
}

class SalesInvoiceSyncInitial extends SalesInvoiceSyncState {}

class SalesInvoiceSyncInProgress extends SalesInvoiceSyncState {
  final String message;
  const SalesInvoiceSyncInProgress(this.message);
}

class SalesInvoiceCustomerSyncInProgress extends SalesInvoiceSyncState {
  final String customerCode;
  final String customerName;
  final String message;
  const SalesInvoiceCustomerSyncInProgress({
    required this.customerCode,
    required this.customerName,
    required this.message,
  });
}

class SalesInvoiceSyncSuccess extends SalesInvoiceSyncState {
  final String lastSyncTime;
  final SyncBatchResult batchResult;
  const SalesInvoiceSyncSuccess(this.lastSyncTime, this.batchResult);
}

class SalesInvoiceCustomerSyncSuccess extends SalesInvoiceSyncState {
  final String customerCode;
  final String customerName;
  final String lastSyncTime;
  final CustomerSyncResult result;
  const SalesInvoiceCustomerSyncSuccess({
    required this.customerCode,
    required this.customerName,
    required this.lastSyncTime,
    required this.result,
  });
}

class SalesInvoiceSyncFailure extends SalesInvoiceSyncState {
  final String error;
  final SyncBatchResult? batchResult;
  const SalesInvoiceSyncFailure(this.error, {this.batchResult});
}

class SalesInvoiceCustomerSyncFailure extends SalesInvoiceSyncState {
  final String customerCode;
  final String customerName;
  final String error;
  const SalesInvoiceCustomerSyncFailure({
    required this.customerCode,
    required this.customerName,
    required this.error,
  });
}
