abstract class SalesInvoiceSyncEvent {
  const SalesInvoiceSyncEvent();
}

class StartSalesInvoiceSyncRequested extends SalesInvoiceSyncEvent {
  final String siteCode;
  const StartSalesInvoiceSyncRequested({required this.siteCode});
}

class ResetSalesInvoiceSyncRequested extends SalesInvoiceSyncEvent {
  const ResetSalesInvoiceSyncRequested();
}
