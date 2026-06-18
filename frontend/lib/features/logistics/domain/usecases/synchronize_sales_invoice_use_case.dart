import '../../data/repositories/sales_invoice_sync_repository.dart';

class SynchronizeSalesInvoiceUseCase {
  final SalesInvoiceSyncRepository _repository;

  SynchronizeSalesInvoiceUseCase(this._repository);

  Future<SyncBatchResult> execute({required String siteCode}) async {
    return await _repository.synchronizeSalesInvoiceData(siteCode);
  }
}
