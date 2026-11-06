abstract class SalesInvoiceSyncEvent {
  const SalesInvoiceSyncEvent();
}

class StartSalesInvoiceSyncRequested extends SalesInvoiceSyncEvent {
  final String siteCode;
  final bool uploadOnly;
  const StartSalesInvoiceSyncRequested({
    required this.siteCode,
    this.uploadOnly = false,
  });
}

class StartSingleCustomerSyncRequested extends SalesInvoiceSyncEvent {
  final String customerCode;
  final String customerName;
  final String? siteCode;

  const StartSingleCustomerSyncRequested({
    required this.customerCode,
    required this.customerName,
    this.siteCode,
  });
}

class ResetSalesInvoiceSyncRequested extends SalesInvoiceSyncEvent {
  const ResetSalesInvoiceSyncRequested();
}
