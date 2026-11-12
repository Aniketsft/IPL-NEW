abstract class SalesInvoiceSyncEvent {
  const SalesInvoiceSyncEvent();
}

class StartSalesInvoiceSyncRequested extends SalesInvoiceSyncEvent {
  final String siteCode;
  final bool uploadOnly;
  final bool downloadOnly;
  const StartSalesInvoiceSyncRequested({
    required this.siteCode,
    this.uploadOnly = false,
    this.downloadOnly = false,
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
