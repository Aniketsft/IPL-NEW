import '../../data/repositories/sales_invoice_sync_repository.dart';

class SynchronizeSalesInvoiceUseCase {
  final SalesInvoiceSyncRepository _repository;

  SynchronizeSalesInvoiceUseCase(this._repository);

  Future<SyncBatchResult> execute({
    required String siteCode,
    bool uploadOnly = false,
    bool downloadOnly = false,
    void Function(String stepMessage)? onProgress,
  }) async {
    return await _repository.synchronizeSalesInvoiceData(
      siteCode,
      uploadOnly: uploadOnly,
      downloadOnly: downloadOnly,
      onProgress: onProgress,
    );
  }
}
