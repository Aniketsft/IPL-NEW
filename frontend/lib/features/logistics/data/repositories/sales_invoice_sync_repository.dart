import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../../core/network_service.dart';
import '../../../../../core/secure_storage_service.dart';
import '../local/local_database_helper.dart';
import 'sales_invoice_product_repository.dart';

class SyncBatchResult {
  final List<String> successes;
  final List<String> failures;
  final String? errorMessage;
  SyncBatchResult({this.successes = const [], this.failures = const [], this.errorMessage});
}

class SalesInvoiceSyncRepository {
  final NetworkService _networkService;
  final SalesInvoiceProductRepository _productRepository;

  SalesInvoiceSyncRepository({
    required NetworkService networkService,
    required SalesInvoiceProductRepository productRepository,
  })  : _networkService = networkService,
        _productRepository = productRepository;

  Dio get _dio => _networkService.dio;

  Future<SyncBatchResult> synchronizeSalesInvoiceData(String siteCode) async {
    final stopwatch = Stopwatch()..start();
    final List<String> successes = [];
    final List<String> failures = [];

    try {
      // 1. Push Unsynced Sales Invoices
      final unsyncedInvoices = await LocalDatabaseHelper.instance.getUnsyncedSalesInvoices();
      debugPrint('Sync: Found ${unsyncedInvoices.length} unsynced Sales Invoices.');

      for (final invoice in unsyncedInvoices) {
        final invoiceId = invoice['invoiceId'] as String;
        final lines = await LocalDatabaseHelper.instance.getSalesInvoiceLines(invoiceId);

        try {
          final payload = {
            "invoiceId": invoiceId,
            "salesSite": invoice['salesSite'] ?? siteCode,
            "customerCode": invoice['customerCode'],
            "pricingRule": invoice['pricingRule'] ?? 'DEFAULT',
            "dueDate": invoice['dueDate'] ?? DateTime.now().toIso8601String(),
            "createdAt": invoice['createdAt'] ?? DateTime.now().toIso8601String(),
            "userName": invoice['userName'] ?? '',
            "reference": invoice['reference'] ?? '',
            "invoiceType": invoice['invoiceType'] ?? 'STD',
            "transactionalId": invoice['transactionalId'] ?? invoiceId,
            "lines": lines.map((l) => {
              "sku": l['sku'],
              "name": l['name'],
              "lineNo": l['lineId'],
              "quantity": l['quantity'] ?? 0.0,
              "basePrice": l['basePrice'] ?? 0.0,
              "discountAmount": l['discountAmount'] ?? 0.0,
              "vatAmount": l['vatAmount'] ?? 0.0,
              "lotNumber": l['lotNumber'] ?? '',
              "warehouse": l['warehouse'] ?? '',
              "salesUnit": l['salesUnit'] ?? 'EA',
              "cce0": l['cce0'] ?? '',
              "taxRule": l['taxRule'] ?? ''
            }).toList()
          };

          // POST to backend
          final response = await _dio.post('SalesInvoice/sync', data: payload);
          if (response.statusCode == 200 || response.statusCode == 201) {
             await LocalDatabaseHelper.instance.markSalesInvoiceSynced(invoiceId);
             successes.add(invoiceId);
          } else {
             failures.add('$invoiceId: ${response.data}');
          }
        } catch (e) {
          if (e is DioException && e.response?.statusCode == 400) {
            // Include backend X3 error message directly
            final data = e.response?.data;
            if (data is Map) {
              final rawPayload = data['rawPayload']?.toString();
              if (rawPayload != null && rawPayload.toLowerCase().contains("creation of ")) {
                await LocalDatabaseHelper.instance.markSalesInvoiceSynced(invoiceId);
                successes.add(invoiceId);
              } else if (data.containsKey('error')) {
                failures.add('$invoiceId: ${data['error']}');
              } else {
                failures.add('$invoiceId: $data');
              }
            } else {
              failures.add('$invoiceId: $data');
            }
          } else {
            failures.add('$invoiceId: Failed to sync ($e)');
          }
        }
      }

      // 2. Fetch Sales Invoice Customers
      final siResponse = await _dio.get('SalesInvoice/customers');
      final siCustomers = siResponse.data as List<dynamic>? ?? [];
      await LocalDatabaseHelper.instance.refreshSalesInvoiceCustomers(siCustomers);
      debugPrint('Sync: Synced ${siCustomers.length} Sales Invoice Customers.');

      // 3. Fetch Sales Invoice Item Stock Details
      await _productRepository.syncSalesInvoiceItemStockDetails();
      
      // 4. Fetch Tax Matrix and Tax Rates
      final taxMatrixResponse = await _dio.get('SalesInvoice/tax-determinations');
      final taxRatesResponse = await _dio.get('SalesInvoice/tax-rates');
      final taxMatrix = taxMatrixResponse.data as List<dynamic>? ?? [];
      final taxRates = taxRatesResponse.data as List<dynamic>? ?? [];
      await LocalDatabaseHelper.instance.refreshSalesInvoiceTaxData(taxMatrix, taxRates);
      debugPrint('Sync: Synced ${taxMatrix.length} Tax Determinations and ${taxRates.length} Tax Rates.');
      
      // 5. Fetch Price Lists (fallback to INLDRYRUN if no schema is selected)
      final schemaStr = await SecureStorageService().getSchema();
      final schema = (schemaStr == null || schemaStr.isEmpty) ? 'INLDRYRUN' : schemaStr;
      
      final priceListResponse = await _dio.get(
        'SalesInvoice/price-lists',
        queryParameters: {'schema': schema},
      );
      final priceLists = priceListResponse.data as List<dynamic>? ?? [];
      await LocalDatabaseHelper.instance.refreshPriceLists(priceLists);
      debugPrint('Sync: Synced ${priceLists.length} Price Lists.');

      final duration = stopwatch.elapsedMilliseconds;
      debugPrint('Sales Invoice Sync completed in ${duration}ms');
      
      return SyncBatchResult(successes: successes, failures: failures);
    } catch (e) {
      debugPrint('Failed to synchronize Sales Invoice data: $e');
      return SyncBatchResult(successes: successes, failures: failures, errorMessage: e.toString());
    }
  }
}
