import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../../core/network_service.dart';
import '../../../../../core/secure_storage_service.dart';
import '../../../../../core/services/device_info_service.dart';
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
    if (responseData is Map) {
      if (responseData.containsKey('x3DocumentId') &&
          responseData['x3DocumentId'] != null &&
          responseData['x3DocumentId'].toString().trim().isNotEmpty) {
        return responseData['x3DocumentId'].toString().trim();
      }
      if (responseData.containsKey('rawPayload')) {
        final rawPayload = responseData['rawPayload']?.toString() ?? '';
        final match = RegExp(r'[Cc]reation of\s+([A-Za-z0-9_-]+)').firstMatch(rawPayload);
        if (match != null && match.groupCount >= 1) {
          displayId = match.group(1)!;
        }
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
        final payments = await LocalDatabaseHelper.instance.getPaymentsForInvoice(invoiceId);

        try {
          final payload = {
            "invoiceId": invoiceId,
            "salesSite": invoice['salesSite'] ?? siteCode,
            "salesRep": invoice['salesRep'] ?? '',
            "customerCode": invoice['customerCode'],
            "pricingRule": invoice['pricingRule'] ?? 'DEFAULT',
            "dueDate": invoice['dueDate'] ?? DateTime.now().toIso8601String(),
            "createdAt": invoice['createdAt'] ?? DateTime.now().toIso8601String(),
            "userName": invoice['userName'] ?? invoice['createdBy'] ?? '',
            "createdBy": invoice['createdBy'] ?? invoice['userName'] ?? '',
            "deviceId": (invoice['deviceId'] != null && (invoice['deviceId'] as String).isNotEmpty)
                ? invoice['deviceId']
                : DeviceInfoService.instance.deviceInfo,
            "reference": invoice['reference'] ?? '',
            "invoiceType": invoice['invoiceType'] ?? 'STD',
            "transactionalId": invoice['transactionalId'] ?? invoiceId,
            "paymentTerm": invoice['paymentTerm'] ?? '',
            "lines": lines.map((l) => {
              "sku": l['sku'],
              "name": l['name'],
              "lineNo": l['lineId'],
              "quantity": l['quantity'] ?? 0.0,
              "basePrice": l['basePrice'] ?? 0.0,
              "discountAmount": l['discountAmount'] ?? 0.0,
              "discountAmountFlat": l['discountAmountFlat'] ?? 0.0,
              "discount1": (l['discountAmount'] as num?)?.toDouble() ?? 0.0,
              "discount2": (l['discountAmountFlat'] as num?)?.toDouble() ?? 0.0,
              "discount3": 0.0,
              "vatAmount": l['vatAmount'] ?? 0.0,
              "total": (l['total'] as num?)?.toDouble() ??
                  (((l['quantity'] as num?)?.toDouble() ?? 0.0) * ((l['basePrice'] as num?)?.toDouble() ?? 0.0) -
                      ((l['discountAmount'] as num?)?.toDouble() ?? 0.0) +
                      ((l['vatAmount'] as num?)?.toDouble() ?? 0.0)),
              "lotNumber": l['lotNumber'] ?? '',
              "warehouse": l['warehouse'] ?? '',
              "location": l['location'] ?? '',
              "salesUnit": l['salesUnit'] ?? 'EA',
              "cce0": l['cce0'] ?? '',
              "taxRule": l['taxRule'] ?? '',
              "isFoc": (l['isFoc'] ?? 0) == 1,
              "pricingSource": l['pricingSource'] ?? '',
              "priceListCode": l['priceListCode'] ?? '',
              "reasonType": l['reasonType'] ?? 0
            }).toList(),
            "payments": payments.map((p) => {
              "localPaymentId": p['paymentId'],
              "method": p['method'] ?? 'CASH',
              "amount": (p['amount'] as num?)?.toDouble() ?? 0.0,
              "bankCode": p['bankCode'],
              "bankName": p['bankName'],
              "chequeNumber": p['chequeNumber'],
              "chequeDate": p['chequeDate'],
              "qrTransactionRef": p['qrTransactionRef'],
            }).toList()
          };

          // POST to backend
          final response = await _dio.post('SalesInvoice/sync', data: payload);
          if (response.statusCode == 200 || response.statusCode == 201) {
             final displayId = _extractX3InvoiceId(invoiceId, response.data);
             await LocalDatabaseHelper.instance.markSalesInvoiceSynced(invoiceId, x3DocumentId: displayId);
             if (response.data is Map && (response.data['paymentSynced'] == true || response.data['x3PaymentId'] != null)) {
               final x3PayId = response.data['x3PaymentId']?.toString();
               await LocalDatabaseHelper.instance.markPaymentsSynced(invoiceId, x3PaymentId: x3PayId, x3InvoiceDocumentId: displayId);
             }
             successes.add(displayId);
          } else {
             failures.add('$invoiceId: ${response.data}');
          }
        } catch (e) {
          if (e is DioException && e.response != null) {
            // Include backend X3 error message directly
            final data = e.response?.data;
            if (data is Map) {
              final rawPayload = data['rawPayload']?.toString();
              if (rawPayload != null && rawPayload.toLowerCase().contains("creation of ")) {
                final displayId = _extractX3InvoiceId(invoiceId, data);
                await LocalDatabaseHelper.instance.markSalesInvoiceSynced(invoiceId, x3DocumentId: displayId);
                if (data['paymentSynced'] == true || data['x3PaymentId'] != null) {
                  final x3PayId = data['x3PaymentId']?.toString();
                  await LocalDatabaseHelper.instance.markPaymentsSynced(invoiceId, x3PaymentId: x3PayId, x3InvoiceDocumentId: displayId);
                }
                successes.add(displayId);
              } else if (data.containsKey('error')) {
                failures.add('$invoiceId: ${data['error']}');
              } else {
                failures.add('$invoiceId: [HTTP ${e.response?.statusCode}] $data');
              }
            } else {
              failures.add('$invoiceId: [HTTP ${e.response?.statusCode}] $data');
            }
          } else {
            failures.add('$invoiceId: Failed to sync ($e)');
          }
        }
      }

      // 1b. Push Unsynced Credit Notes
      final unsyncedCreditNotes = await LocalDatabaseHelper.instance.getUnsyncedCreditNotes();
      debugPrint('Sync: Found ${unsyncedCreditNotes.length} unsynced Credit Notes.');

      for (final cn in unsyncedCreditNotes) {
        final creditNoteId = cn['creditNoteId'] as String;
        final lines = await LocalDatabaseHelper.instance.getMergedCreditNoteLines(creditNoteId);
        final refunds = await LocalDatabaseHelper.instance.getCreditNoteRefunds(creditNoteId);

        try {
          final originalInvoiceId = (cn['originalInvoiceId'] as String?)?.trim();
          final isLinked = originalInvoiceId != null && originalInvoiceId.isNotEmpty;
          final category = (cn['creditNoteType'] == 'RETURN') ? 3 : 2;
          final transactionMode = (cn['transactionMode'] != null && (cn['transactionMode'] as String).trim().isNotEmpty)
              ? (cn['transactionMode'] as String).trim()
              : (isLinked ? "4" : "1");

          String? resolvedOriginalInvoiceId = originalInvoiceId;
          if (isLinked) {
            try {
              final invRows = await LocalDatabaseHelper.instance.database.then(
                (db) => db.query(
                  LocalDatabaseHelper.tableSiInvoices,
                  columns: ['x3DocumentId'],
                  where: 'invoiceId = ?',
                  whereArgs: [originalInvoiceId],
                  limit: 1,
                ),
              );
              if (invRows.isNotEmpty && invRows.first['x3DocumentId'] != null) {
                final x3Id = (invRows.first['x3DocumentId'] as String).trim();
                if (x3Id.isNotEmpty) {
                  resolvedOriginalInvoiceId = x3Id;
                }
              }
            } catch (e) {
              debugPrint('Warning: Could not fetch x3DocumentId for invoice $originalInvoiceId: $e');
            }
          }

          final payload = {
            "creditNoteId": creditNoteId,
            "creditNoteType": cn['creditNoteType'] ?? 'CRN',
            "salesSite": cn['salesSite'] ?? siteCode,
            "customerCode": cn['customerCode'],
            "customerName": cn['customerName'] ?? '',
            "category": category,
            "salesRep": cn['salesRep'] ?? '',
            "reason": cn['reason'] ?? 'CREDIT_NOTE',
            "originalInvoiceId": resolvedOriginalInvoiceId,
            "transactionMode": transactionMode,
            "reference": cn['reference'] ?? '',
            "createdAt": cn['createdAt'] ?? DateTime.now().toIso8601String(),
            "dueDate": cn['createdAt'] ?? DateTime.now().toIso8601String(),
            "createdBy": cn['createdBy'] ?? '',
            "userName": cn['createdBy'] ?? '',
            "deviceId": (cn['deviceId'] != null && (cn['deviceId'] as String).isNotEmpty)
                ? cn['deviceId']
                : DeviceInfoService.instance.deviceInfo,
            "transactionalId": creditNoteId,
            "grandTotal": (cn['grandTotal'] as num?)?.toDouble() ?? 0.0,
            "lines": lines.map((l) => {
              "lineNo": l['lineNo'] ?? 1000,
              "quantity": (l['quantity'] as num?)?.toDouble() ?? 0.0,
              "sku": l['sku'] ?? '',
              "name": l['name'] ?? '',
              "salesUnit": l['salesUnit'] ?? 'EA',
              "basePrice": (l['basePrice'] as num?)?.toDouble() ?? 0.0,
              "taxRule": l['taxRule'] ?? '',
              "lotNumber": l['lotNumber'] ?? '',
              "warehouse": l['warehouse'] ?? '',
              "cce0": l['cce0'] ?? '',
              "originLineNo": l['lineNo']
            }).toList(),
            "refunds": refunds.map((r) => {
              "localRefundId": r['refundId'],
              "method": r['method'] ?? 'CASH',
              "amount": (r['amount'] as num?)?.toDouble() ?? 0.0,
              "bankCode": r['bankCode'],
              "bankName": r['bankName'],
              "chequeNumber": r['chequeNumber'],
              "chequeDate": r['chequeDate']
            }).toList()
          };

          final response = await _dio.post('SalesInvoice/sync-credit-note', data: payload);
          if (response.statusCode == 200 || response.statusCode == 201) {
            final displayId = _extractX3InvoiceId(creditNoteId, response.data);
            await LocalDatabaseHelper.instance.markCreditNoteSynced(creditNoteId, x3DocumentId: displayId);
            if (response.data is Map && (response.data['refundSynced'] == true || response.data['x3RefundPaymentId'] != null)) {
              final x3RefundId = response.data['x3RefundPaymentId']?.toString();
              await LocalDatabaseHelper.instance.markCreditNoteRefundsSynced(creditNoteId, x3PaymentId: x3RefundId);
            }
            successes.add(displayId);
          } else {
            failures.add('$creditNoteId: ${response.data}');
          }
        } catch (e) {
          if (e is DioException && e.response != null) {
            final data = e.response?.data;
            if (data is Map) {
              final rawPayload = data['rawPayload']?.toString();
              if (rawPayload != null && rawPayload.toLowerCase().contains("creation of ")) {
                final displayId = _extractX3InvoiceId(creditNoteId, data);
                await LocalDatabaseHelper.instance.markCreditNoteSynced(creditNoteId, x3DocumentId: displayId);
                if (data['refundSynced'] == true || data['x3RefundPaymentId'] != null) {
                  final x3RefundId = data['x3RefundPaymentId']?.toString();
                  await LocalDatabaseHelper.instance.markCreditNoteRefundsSynced(creditNoteId, x3PaymentId: x3RefundId);
                }
                successes.add(displayId);
              } else if (data.containsKey('error')) {
                failures.add('$creditNoteId: ${data['error']}');
              } else {
                failures.add('$creditNoteId: [HTTP ${e.response?.statusCode}] $data');
              }
            } else {
              failures.add('$creditNoteId: [HTTP ${e.response?.statusCode}] $data');
            }
          } else {
            failures.add('$creditNoteId: Failed to sync ($e)');
          }
        }
      }

      // 1c. Push Unsynced Standalone / Retried Payments for existing X3 documents
      try {
        final unsyncedPayments = await LocalDatabaseHelper.instance.getUnsyncedPayments();
        if (unsyncedPayments.isNotEmpty) {
          debugPrint('Sync: Found ${unsyncedPayments.length} unsynced payment rows.');
          final eligiblePayments = <Map<String, dynamic>>[];
          for (final p in unsyncedPayments) {
            final invId = p['invoiceId']?.toString() ?? '';
            if (invId.isEmpty) continue;
            final inv = await LocalDatabaseHelper.instance.getSalesInvoiceById(invId);
            final x3Doc = inv?['x3DocumentId']?.toString();
            if (x3Doc != null && x3Doc.isNotEmpty) {
              eligiblePayments.add({
                "localPaymentId": p['paymentId'],
                "documentType": "INVOICE",
                "documentId": invId,
                "x3InvoiceDocumentId": x3Doc,
                "salesSite": p['salesSite'] ?? inv?['salesSite'] ?? siteCode,
                "customerCode": p['customerCode'] ?? inv?['customerCode'] ?? '',
                "customerName": inv?['customerName'] ?? '',
                "method": p['method'] ?? 'CASH',
                "amount": (p['amount'] as num?)?.toDouble() ?? 0.0,
                "bankCode": p['bankCode'],
                "bankName": p['bankName'],
                "chequeNumber": p['chequeNumber'],
                "chequeDate": p['chequeDate'],
                "qrTransactionRef": p['qrTransactionRef'],
              });
            }
          }

          if (eligiblePayments.isNotEmpty) {
            final payResp = await _dio.post('SalesInvoice/sync-payments', data: eligiblePayments);
            if (payResp.statusCode == 200 && payResp.data is Map && payResp.data['results'] is List) {
              for (final res in (payResp.data['results'] as List)) {
                if (res is Map && res['success'] == true) {
                  final docId = res['documentId']?.toString();
                  final x3PayId = res['x3PaymentId']?.toString();
                  final x3InvDocId = res['x3InvoiceDocumentId']?.toString();
                  if (docId != null && docId.isNotEmpty) {
                    await LocalDatabaseHelper.instance.markPaymentsSynced(
                      docId,
                      x3PaymentId: x3PayId,
                      x3InvoiceDocumentId: x3InvDocId,
                    );
                  }
                }
              }
            }
          }
        }
      } catch (payRetryEx) {
        debugPrint('Sync: Standalone payment sync retry warning: $payRetryEx');
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

      final custParams = <String, dynamic>{};
      if (siteCode.isNotEmpty) custParams['sitecode'] = siteCode;

      final openInvParams = <String, dynamic>{'daysCutoff': 90};
      if (siteCode.isNotEmpty) openInvParams['sitecode'] = siteCode;

      final x3Params = <String, dynamic>{'months': 6};
      if (siteCode.isNotEmpty && siteCode != 'ALL') x3Params['sitecode'] = siteCode;

      debugPrint('Sync: Initiating parallel download of master data & 6-month X3 history...');
      final results = await Future.wait([
        safeGet('SalesInvoice/customers', queryParameters: custParams.isNotEmpty ? custParams : null, label: 'Customers'),
        safeGet('SalesInvoice/tax-determinations', label: 'Tax Determinations'),
        safeGet('SalesInvoice/tax-rates', label: 'Tax Rates'),
        safeGet('SalesInvoice/price-lists', queryParameters: {'schema': schema}, label: 'Price Lists'),
        safeGet('SalesInvoice/salesreps', queryParameters: siteCode.isNotEmpty ? {'siteCode': siteCode} : null, label: 'Sales Reps'),
        safeGet('SalesInvoice/open-invoices', queryParameters: openInvParams, label: 'Open Invoices'),
        safeGet('SalesInvoice/x3-history', queryParameters: x3Params, options: Options(receiveTimeout: const Duration(seconds: 90)), label: 'X3 History'),
        safeGet('SalesInvoice/credit-note-reasons', label: 'Credit Note Reasons'),
        safeGet('SalesInvoice/banks', label: 'Banks'),
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
      final reasonsResp = results[7];
      final banksResp = results[8];

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

      // Ingest Credit Note Reasons (Sage X3 Table 8)
      if (reasonsResp != null && reasonsResp.data is List) {
        final rawReasons = reasonsResp.data as List<dynamic>;
        if (rawReasons.isNotEmpty) {
          await LocalDatabaseHelper.instance.refreshCreditNoteReasons(rawReasons);
          debugPrint('Sync: Synced ${rawReasons.length} Sage X3 Credit Note Reasons.');
        }
      }

      // Ingest Banks (Sage X3 Table BANK)
      if (banksResp != null && banksResp.data is List) {
        final rawBanks = banksResp.data as List<dynamic>;
        if (rawBanks.isNotEmpty) {
          final banksList = rawBanks.map((item) => Map<String, dynamic>.from(item as Map)).toList();
          await LocalDatabaseHelper.instance.upsertBanks(banksList);
          debugPrint('Sync: Synced ${banksList.length} Sage X3 Banks.');
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
