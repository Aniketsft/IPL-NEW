import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../../core/network_service.dart';
import '../../../../../core/secure_storage_service.dart';
import '../local/local_database_helper.dart';
import '../models/sales_rep_model.dart';
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

  String _extractX3InvoiceId(String fallbackInvoiceId, dynamic responseData) {
    String displayId = fallbackInvoiceId;
    if (responseData is Map && responseData.containsKey('rawPayload')) {
      final rawPayload = responseData['rawPayload']?.toString() ?? '';
      final match = RegExp(r'[Cc]reation of\s+([A-Za-z0-9_-]+)').firstMatch(rawPayload);
      if (match != null && match.groupCount >= 1) {
        displayId = match.group(1)!;
      }
    }
    return displayId;
  }

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
            "salesRep": invoice['salesRep'] ?? '',
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
              "total": (l['total'] as num?)?.toDouble() ??
                  (((l['quantity'] as num?)?.toDouble() ?? 0.0) * ((l['basePrice'] as num?)?.toDouble() ?? 0.0) -
                      ((l['discountAmount'] as num?)?.toDouble() ?? 0.0) +
                      ((l['vatAmount'] as num?)?.toDouble() ?? 0.0)),
              "lotNumber": l['lotNumber'] ?? '',
              "warehouse": l['warehouse'] ?? '',
              "salesUnit": l['salesUnit'] ?? 'EA',
              "cce0": l['cce0'] ?? '',
              "taxRule": l['taxRule'] ?? '',
              "isFoc": (l['isFoc'] ?? 0) == 1,
              "pricingSource": l['pricingSource'] ?? '',
              "discountAmountFlat": l['discountAmountFlat'] ?? 0.0,
              "priceListCode": l['priceListCode'] ?? '',
              "reasonType": l['reasonType'] ?? 0
            }).toList()
          };

          // POST to backend
          final response = await _dio.post('SalesInvoice/sync', data: payload);
          if (response.statusCode == 200 || response.statusCode == 201) {
             await LocalDatabaseHelper.instance.markSalesInvoiceSynced(invoiceId);
             
             final displayId = _extractX3InvoiceId(invoiceId, response.data);
             successes.add(displayId);
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
                
                final displayId = _extractX3InvoiceId(invoiceId, data);
                successes.add(displayId);
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

      // Helper to safely execute a network request without failing sibling requests
      Future<Response?> safeGet(String path, {Map<String, dynamic>? queryParameters, Options? options, String? label}) async {
        try {
          return await _dio.get(path, queryParameters: queryParameters, options: options);
        } catch (e) {
          debugPrint('Sync: Failed to fetch $label ($path): $e');
          return null;
        }
      }

      final schemaStr = await SecureStorageService().getSchema();
      final schema = (schemaStr == null || schemaStr.isEmpty) ? 'INLDRYRUN' : schemaStr;
      if (schema == 'INLDRYRUN') {
        debugPrint('⚠️ WARNING: Fetching price lists from INLDRYRUN schema. Ensure the correct schema is configured in app settings. Prices may not reflect production rules.');
      }

      final openInvParams = <String, dynamic>{'daysCutoff': 90};
      if (siteCode.isNotEmpty) openInvParams['sitecode'] = siteCode;

      final x3Params = <String, dynamic>{'months': 6};
      if (siteCode.isNotEmpty && siteCode != 'ALL') x3Params['sitecode'] = siteCode;

      debugPrint('Sync: Initiating parallel download of master data & 6-month X3 history...');
      final results = await Future.wait([
        safeGet('SalesInvoice/customers', label: 'Customers'),
        safeGet('SalesInvoice/tax-determinations', label: 'Tax Determinations'),
        safeGet('SalesInvoice/tax-rates', label: 'Tax Rates'),
        safeGet('SalesInvoice/price-lists', queryParameters: {'schema': schema}, label: 'Price Lists'),
        safeGet('SalesInvoice/salesreps', queryParameters: siteCode.isNotEmpty ? {'siteCode': siteCode} : null, label: 'Sales Reps'),
        safeGet('SalesInvoice/open-invoices', queryParameters: openInvParams, label: 'Open Invoices'),
        safeGet('SalesInvoice/x3-history', queryParameters: x3Params, options: Options(receiveTimeout: const Duration(seconds: 90)), label: 'X3 History'),
        _productRepository.syncSalesInvoiceItemStockDetails(siteCode).then((_) => null).catchError((e) {
          debugPrint('Sync: Failed to fetch stock details: $e');
          return null;
        }),
      ]);

      final custResp = results[0];
      final taxMatrixResp = results[1];
      final taxRatesResp = results[2];
      final priceListResp = results[3];
      final repsResp = results[4];
      final openInvResp = results[5];
      final x3Resp = results[6];

      // Ingest Customers
      if (custResp != null && custResp.data is List) {
        final siCustomers = custResp.data as List<dynamic>;
        await LocalDatabaseHelper.instance.refreshSalesInvoiceCustomers(siCustomers);
        debugPrint('Sync: Synced ${siCustomers.length} Sales Invoice Customers.');
      }

      // Ingest Tax Matrix & Rates
      if (taxMatrixResp != null && taxRatesResp != null) {
        final taxMatrix = taxMatrixResp.data as List<dynamic>? ?? [];
        final taxRates = taxRatesResp.data as List<dynamic>? ?? [];
        await LocalDatabaseHelper.instance.refreshSalesInvoiceTaxData(taxMatrix, taxRates);
        debugPrint('Sync: Synced ${taxMatrix.length} Tax Determinations and ${taxRates.length} Tax Rates.');
      }

      // Ingest Price Lists
      if (priceListResp != null && priceListResp.data is List) {
        final priceLists = priceListResp.data as List<dynamic>;
        await LocalDatabaseHelper.instance.refreshPriceLists(priceLists);
        debugPrint('Sync: Synced ${priceLists.length} Price Lists.');
      }

      // Ingest Sales Reps
      if (repsResp != null && repsResp.data is List) {
        final rawReps = repsResp.data as List<dynamic>;
        final repsList = rawReps.map((item) => Map<String, dynamic>.from(item as Map)).toList();
        await LocalDatabaseHelper.instance.upsertSalesReps(repsList);
        debugPrint('Sync: Synced ${repsList.length} Sales Reps.');
      }

      // Ingest Open Invoices
      if (openInvResp != null && openInvResp.data is List) {
        final rawOpenInvoices = openInvResp.data as List<dynamic>;
        await LocalDatabaseHelper.instance.refreshOpenInvoices(rawOpenInvoices);
        debugPrint('Sync: Synced ${rawOpenInvoices.length} Open Invoices & Credit Notes (Site: $siteCode, Cutoff: 90d).');
      }

      // Ingest 6-Month X3 History
      if (x3Resp != null && x3Resp.data is List) {
        final rawX3Docs = x3Resp.data as List<dynamic>;
        if (rawX3Docs.isNotEmpty) {
          await LocalDatabaseHelper.instance.pruneX3HistoryOlderThan(months: 6);
          await LocalDatabaseHelper.instance.saveX3HistoryDocuments(rawX3Docs);
          debugPrint('Sync: Synced ${rawX3Docs.length} X3 History Documents (Site: $siteCode, 6 months).');
        }
      }

      // 8. Push Unsynced Open Invoice Payments
      try {
        final unsyncedOpenPayments = await LocalDatabaseHelper.instance.getUnsyncedOpenInvoicePayments();
        if (unsyncedOpenPayments.isNotEmpty) {
          debugPrint('Sync: Found ${unsyncedOpenPayments.length} unsynced Open Invoice Payments.');
          final paymentsPayload = unsyncedOpenPayments.map((p) => {
            'paymentId': p['paymentId'],
            'documentNo': p['documentNo'],
            'customerNo': p['customerNo'],
            'amount': p['amount'],
            'paymentMethod': p['paymentMethod'],
            'bankCode': p['bankCode'],
            'bankName': p['bankName'],
            'chequeNumber': p['chequeNumber'],
            'chequeDate': p['chequeDate'],
            'qrTransactionRef': p['qrTransactionRef'],
            'siteCode': p['siteCode'] ?? siteCode,
            'company': p['company'] ?? '',
            'createdAt': p['createdAt'],
            'userName': p['userName'],
            'deviceId': p['deviceId'],
          }).toList();

          final payResponse = await _dio.post('SalesInvoice/open-invoices/payments/sync', data: paymentsPayload);
          if (payResponse.statusCode == 200) {
            final ids = unsyncedOpenPayments.map((p) => p['paymentId'] as String).toList();
            await LocalDatabaseHelper.instance.markOpenInvoicePaymentsSynced(ids);
            debugPrint('Sync: Successfully marked ${ids.length} open invoice payments synced.');
          }
        }
      } catch (e) {
        debugPrint('Sync: Failed to push open invoice payments: $e');
      }

      final duration = stopwatch.elapsedMilliseconds;
      debugPrint('Sales Invoice Sync completed in ${duration}ms');
      
      return SyncBatchResult(successes: successes, failures: failures);
    } on DioException catch (e) {
      debugPrint('Failed to synchronize Sales Invoice data (DioException): $e');
      if (e.response != null) {
        debugPrint('DioException Response Data: ${e.response?.data}');
      }
      final isOffline = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          (e.error != null && e.error.toString().toLowerCase().contains('offline'));
      final serverError = isOffline
          ? 'Cannot sync while offline. All records are safely saved locally.'
          : (e.response?.data?.toString() ?? e.message ?? 'Network error');
      failures.add(serverError);
      return SyncBatchResult(successes: successes, failures: failures, errorMessage: serverError);
    } catch (e) {
      debugPrint('Failed to synchronize Sales Invoice data: $e');
      final errStr = e.toString();
      final isOffline = errStr.toLowerCase().contains('offline') ||
          errStr.toLowerCase().contains('socketexception') ||
          errStr.toLowerCase().contains('connection');
      final serverError = isOffline
          ? 'Cannot sync while offline. All records are safely saved locally.'
          : errStr;
      failures.add(serverError);
      return SyncBatchResult(successes: successes, failures: failures, errorMessage: serverError);
    }
  }

  Future<List<SalesRepModel>> fetchAndSyncSalesReps({String? siteCode}) async {
    try {
      final response = await _dio.get(
        'SalesInvoice/salesreps',
        queryParameters: (siteCode != null && siteCode.isNotEmpty) ? {'siteCode': siteCode} : null,
      );
      final rawList = response.data as List<dynamic>? ?? [];
      final reps = rawList
          .map((item) => SalesRepModel.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList();
      await LocalDatabaseHelper.instance.upsertSalesReps(reps.map((r) => r.toMap()).toList());
      return reps;
    } catch (e) {
      debugPrint('Failed to fetch and sync sales reps: $e');
      final localData = await LocalDatabaseHelper.instance.getSalesReps(siteCode: siteCode);
      return localData.map((m) => SalesRepModel.fromMap(m)).toList();
    }
  }
}
