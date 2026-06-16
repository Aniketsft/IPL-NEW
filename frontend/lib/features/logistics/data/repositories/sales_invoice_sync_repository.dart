import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../../core/network_service.dart';
import '../local/local_database_helper.dart';
import 'sales_invoice_product_repository.dart';

class SalesInvoiceSyncRepository {
  final NetworkService _networkService;
  final SalesInvoiceProductRepository _productRepository;

  SalesInvoiceSyncRepository({
    required NetworkService networkService,
    required SalesInvoiceProductRepository productRepository,
  })  : _networkService = networkService,
        _productRepository = productRepository;

  Dio get _dio => _networkService.dio;

  Future<void> synchronizeSalesInvoiceData(String siteCode) async {
    final stopwatch = Stopwatch()..start();
    try {
      // 1. Fetch Sales Invoice Customers
      final siResponse = await _dio.get('SalesInvoice/customers');
      final siCustomers = siResponse.data as List<dynamic>? ?? [];
      await LocalDatabaseHelper.instance.refreshSalesInvoiceCustomers(siCustomers);
      debugPrint('Sync: Synced ${siCustomers.length} Sales Invoice Customers.');

      // 2. Fetch Sales Invoice Item Stock Details
      await _productRepository.syncSalesInvoiceItemStockDetails();
      
      final duration = stopwatch.elapsedMilliseconds;
      debugPrint('Sales Invoice Sync completed in ${duration}ms');
    } catch (e) {
      debugPrint('Failed to synchronize Sales Invoice data: $e');
      rethrow;
    }
  }
}
