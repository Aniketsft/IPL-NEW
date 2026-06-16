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
  const SalesInvoiceSyncSuccess(this.lastSyncTime);
}

class SalesInvoiceSyncFailure extends SalesInvoiceSyncState {
  final String error;
  const SalesInvoiceSyncFailure(this.error);
}
