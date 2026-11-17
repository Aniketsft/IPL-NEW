import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../core/network_service.dart';
import '../../../../../core/secure_storage_service.dart';
import '../../../../../core/services/device_info_service.dart';
import '../local/local_database_helper.dart';
import '../models/sales_rep_model.dart';
import 'sales_invoice_product_repository.dart';

enum SyncStatus {
  success,
  cached304,
  failed,
  skipped,
}

enum SyncDirection {
  download,
  upload,
}

class SyncEntityReport {
  final String entityName;
  final SyncDirection direction;
  final SyncStatus status;
  final int count;
  final String? errorCode;
  final String? userMessage;
  final String? technicalDetails;
  final Duration duration;
  final String? documentId;
  final List<String> messages;

  const SyncEntityReport({
    required this.entityName,
    required this.direction,
    required this.status,
    this.count = 0,
    this.errorCode,
    this.userMessage,
    this.technicalDetails,
    this.duration = Duration.zero,
    this.documentId,
    this.messages = const [],
  });
}

class CustomerSyncResult {
  final bool success;
  final String customerCode;
  final double liveBalance;
  final double creditLimit;
  final String statusFlag;
  final int openInvoicesCount;
  final int x3HistoryInvoicesCount;
  final String? errorMessage;

  const CustomerSyncResult({
    required this.success,
    required this.customerCode,
    this.liveBalance = 0.0,
    this.creditLimit = 0.0,
    this.statusFlag = '1',
    this.openInvoicesCount = 0,
    this.x3HistoryInvoicesCount = 0,
    this.errorMessage,
  });
}

class SyncBatchResult {
  final List<String> successes;
  final List<String> failures;
  final String? errorMessage;
  final List<SyncEntityReport> reports;
  final DateTime timestamp;

  SyncBatchResult({
    this.successes = const [],
    this.failures = const [],
    this.errorMessage,
    this.reports = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isCleanSuccess =>
      (errorMessage == null || errorMessage!.isEmpty) &&
      failures.isEmpty &&
      reports.isNotEmpty &&
      reports.every((r) => r.status == SyncStatus.success || r.status == SyncStatus.cached304);

  bool get hasFailures => failures.isNotEmpty || reports.any((r) => r.status == SyncStatus.failed);

  bool get isTotalFailure =>
      reports.isNotEmpty &&
      reports.every((r) => r.status == SyncStatus.failed || r.status == SyncStatus.skipped);

  List<SyncEntityReport> get failedReports =>
      reports.where((r) => r.status == SyncStatus.failed).toList();

  List<SyncEntityReport> get successfulReports =>
      reports.where((r) => r.status == SyncStatus.success || r.status == SyncStatus.cached304).toList();

  bool get hasUploadItems => reports.any((r) => r.direction == SyncDirection.upload);

  List<SyncEntityReport> get uploadReports =>
      reports.where((r) => r.direction == SyncDirection.upload).toList();

  String toDiagnosticJson({String? siteCode, String? schema, String? baseUrl, String? deviceId}) {
    final Map<String, dynamic> data = {
      'timestamp': timestamp.toIso8601String(),
      'siteCode': siteCode ?? 'N/A',
      'schema': schema ?? 'N/A',
      'baseUrl': baseUrl ?? 'N/A',
      'deviceId': deviceId ?? 'N/A',
      'isCleanSuccess': isCleanSuccess,
      'hasFailures': hasFailures,
      'isTotalFailure': isTotalFailure,
      'errorMessage': errorMessage,
      'successCount': successes.length,
      'failureCount': failures.length,
      'reports': reports.map((r) => {
        'entity': r.entityName,
        'direction': r.direction.name,
        'status': r.status.name,
        'count': r.count,
        if (r.errorCode != null) 'errorCode': r.errorCode,
        if (r.userMessage != null) 'userMessage': r.userMessage,
        if (r.technicalDetails != null) 'technicalDetails': r.technicalDetails,
        'durationMs': r.duration.inMilliseconds,
      }).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }
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

  Future<String> _resolveTabletSource([String? storedDeviceId]) async {
    final currentName = DeviceInfoService.instance.deviceName.trim();
    if (RegExp(r'^HM\d+$', caseSensitive: false).hasMatch(currentName) &&
        currentName.toUpperCase() != 'HM1') {
      return currentName.toUpperCase();
    }

    final lookupId = DeviceInfoService.instance.deviceId.isNotEmpty
        ? DeviceInfoService.instance.deviceId
        : (storedDeviceId ?? '');
    if (lookupId.isNotEmpty) {
      try {
        final devLoc = await LocalDatabaseHelper.instance.getDeviceLocation(lookupId);
        final dbName = devLoc?['deviceName']?.toString().trim() ?? '';
        if (dbName.isNotEmpty && !DeviceInfoService.isHardwareOrLegacyName(dbName)) {
          return dbName.toUpperCase();
        }
      } catch (_) {}
    }

    return currentName.isNotEmpty && !DeviceInfoService.isHardwareOrLegacyName(currentName)
        ? currentName.toUpperCase()
        : 'HM1';
  }

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

  Future<SyncBatchResult> synchronizeSalesInvoiceData(
    String siteCode, {
    bool uploadOnly = false,
    bool downloadOnly = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final List<String> successes = [];
    final List<String> failures = [];
    final List<SyncEntityReport> entityReports = [];

    // Pre-flight session check: Prevent flooding logs with suppressed requests
    final token = await SecureStorageService().getToken();
    if (token == null || token.isEmpty || token.startsWith('OFFLINE_SESSION_')) {
      final offlineMsg = 'Device is operating in Offline Mode. Connect to company network and log in online to synchronize.';
      debugPrint('Sync: Cannot synchronize because device is in Offline Session ($token).');
      entityReports.add(SyncEntityReport(
        entityName: 'Authentication Session',
        direction: SyncDirection.download,
        status: SyncStatus.failed,
        errorCode: 'ERR_AUTH_OFFLINE_SESSION',
        userMessage: offlineMsg,
        technicalDetails: 'Network requests suppressed: device running under OFFLINE_SESSION token.',
        duration: stopwatch.elapsed,
      ));
      return SyncBatchResult(
        successes: [],
        failures: [offlineMsg],
        errorMessage: offlineMsg,
        reports: entityReports,
      );
    }

    try {
      if (!downloadOnly) {
        // 1. Push Unsynced Sales Invoices
        final unsyncedInvoices = await LocalDatabaseHelper.instance.getUnsyncedSalesInvoices();
      debugPrint('Sync: Found ${unsyncedInvoices.length} unsynced Sales Invoices.');

      for (final invoice in unsyncedInvoices) {
        final invoiceId = invoice['invoiceId'] as String;
        final lines = await LocalDatabaseHelper.instance.getSalesInvoiceLines(invoiceId);
        final payments = await LocalDatabaseHelper.instance.getPaymentsForInvoice(invoiceId);

        try {
          final resolvedTablet = await _resolveTabletSource(invoice['deviceId']?.toString());
          final cleanDeviceId = DeviceInfoService.instance.deviceId.isNotEmpty
              ? DeviceInfoService.instance.deviceId
              : ((invoice['deviceId'] != null &&
                      (invoice['deviceId'] as String).isNotEmpty &&
                      !DeviceInfoService.isHardwareOrLegacyName(invoice['deviceId'] as String))
                  ? invoice['deviceId']
                  : resolvedTablet);

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
            "deviceId": cleanDeviceId,
            "tabletSource": resolvedTablet,
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
              "discount1": (l['discount1'] as num?)?.toDouble() ?? 0.0,
              "discount2": (l['discount2'] as num?)?.toDouble() ?? (l['discountAmountFlat'] as num?)?.toDouble() ?? 0.0,
              "discount3": (l['discount3'] as num?)?.toDouble() ?? 
                           (l['discountAmount'] as num?)?.toDouble() ?? 0.0,
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
              "mainItemSku": l['mainItemSku'] ?? '',
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
             final List<String> msgs = [];
             if (response.data is Map && response.data['messages'] is List) {
               msgs.addAll((response.data['messages'] as List).map((m) => m.toString()));
             }
             if (msgs.isEmpty) {
               msgs.add('Created in Sage X3: $displayId');
             }
             entityReports.add(SyncEntityReport(
               entityName: displayId,
               direction: SyncDirection.upload,
               status: SyncStatus.success,
               count: 1,
               documentId: displayId,
               messages: msgs,
             ));
          } else {
             final err = '$invoiceId: ${response.data}';
             failures.add(err);
             entityReports.add(SyncEntityReport(
               entityName: invoiceId,
               direction: SyncDirection.upload,
               status: SyncStatus.failed,
               errorCode: 'ERR_UPLOAD_INVOICE',
               userMessage: err,
               technicalDetails: 'HTTP ${response.statusCode}: ${response.data}',
               documentId: invoiceId,
               messages: [err],
             ));
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
                entityReports.add(SyncEntityReport(
                  entityName: displayId,
                  direction: SyncDirection.upload,
                  status: SyncStatus.success,
                  count: 1,
                  documentId: displayId,
                  messages: ['Recovered in Sage X3: $displayId'],
                ));
              } else {
                final List<String> msgs = [];
                if (data['messages'] is List) {
                  msgs.addAll((data['messages'] as List).map((m) => m.toString()));
                }
                final err = data['error']?.toString() ?? '$data';
                if (msgs.isEmpty && err.isNotEmpty) {
                  msgs.add(err);
                }
                final userMsg = '$invoiceId: $err';
                failures.add(userMsg);
                entityReports.add(SyncEntityReport(
                  entityName: 'Invoice $invoiceId',
                  direction: SyncDirection.upload,
                  status: SyncStatus.failed,
                  errorCode: 'ERR_UPLOAD_INVOICE',
                  userMessage: userMsg,
                  technicalDetails: '[HTTP ${e.response?.statusCode}] $data',
                  documentId: invoiceId,
                  messages: msgs,
                ));
              }
            } else {
              final err = '$invoiceId: [HTTP ${e.response?.statusCode}] $data';
              failures.add(err);
              entityReports.add(SyncEntityReport(
                entityName: 'Invoice $invoiceId',
                direction: SyncDirection.upload,
                status: SyncStatus.failed,
                errorCode: 'ERR_UPLOAD_INVOICE',
                userMessage: err,
                technicalDetails: '$data',
                documentId: invoiceId,
                messages: [err],
              ));
            }
          } else {
            final err = '$invoiceId: Failed to sync ($e)';
            failures.add(err);
            entityReports.add(SyncEntityReport(
              entityName: 'Invoice $invoiceId',
              direction: SyncDirection.upload,
              status: SyncStatus.failed,
              errorCode: 'ERR_UPLOAD_INVOICE',
              userMessage: err,
              technicalDetails: e.toString(),
              documentId: invoiceId,
              messages: [err],
            ));
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
          final category = (cn['creditNoteType'] == 'RETURN' || (cn['stockTransaction'] as num?)?.toInt() == 1) ? 3 : 2;
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

          final resolvedCrnTablet = await _resolveTabletSource(cn['deviceId']?.toString());
          final cleanCrnDeviceId = DeviceInfoService.instance.deviceId.isNotEmpty
              ? DeviceInfoService.instance.deviceId
              : ((cn['deviceId'] != null &&
                      (cn['deviceId'] as String).isNotEmpty &&
                      !DeviceInfoService.isHardwareOrLegacyName(cn['deviceId'] as String))
                  ? cn['deviceId']
                  : resolvedCrnTablet);

          String resolvedDeviceLorry = (DeviceInfoService.instance.assignedLocation ?? '').trim();
          if (resolvedDeviceLorry.isEmpty) {
            try {
              final devLoc = await LocalDatabaseHelper.instance.getDeviceLocation(cleanCrnDeviceId.toString());
              resolvedDeviceLorry = devLoc?['locationCode']?.toString().trim() ?? '';
            } catch (_) {}
          }
          final String effectiveCrnSite = (cn['salesSite'] ?? siteCode).toString().trim();

          final payload = {
            "creditNoteId": creditNoteId,
            "creditNoteType": (category == 3) ? 'RETURN' : (cn['creditNoteType'] ?? 'CRN'),
            "salesSite": cn['salesSite'] ?? siteCode,
            "customerCode": cn['customerCode'],
            "customerName": cn['customerName'] ?? '',
            "category": category,
            "stockTransaction": (category == 3) ? 1 : 0,
            "salesRep": cn['salesRep'] ?? '',
            "reason": cn['reason'] ?? 'CREDIT_NOTE',
            "originalInvoiceId": resolvedOriginalInvoiceId,
            "transactionMode": transactionMode,
            "reference": cn['reference'] ?? '',
            "createdAt": cn['createdAt'] ?? DateTime.now().toIso8601String(),
            "dueDate": cn['createdAt'] ?? DateTime.now().toIso8601String(),
            "createdBy": cn['createdBy'] ?? '',
            "userName": cn['createdBy'] ?? '',
            "deviceId": cleanCrnDeviceId,
            "tabletSource": resolvedCrnTablet,
            "transactionalId": creditNoteId,
            "settlementType": cn['settlementType'] ?? (refunds.any((r) => (r['method'] ?? '').toString().toUpperCase() == 'CASH') ? 'CASH' : 'CREDIT'),
            "grandTotal": (cn['grandTotal'] as num?)?.toDouble() ?? 0.0,
            "lines": lines.map((l) {
              final rawLoc = (l['location'] ?? '').toString().trim();
              final bool isValidLineLoc = rawLoc.isNotEmpty &&
                  rawLoc.toUpperCase() != 'LOC1' &&
                  rawLoc.toUpperCase() != effectiveCrnSite.toUpperCase();
              final resolvedLineLoc = resolvedDeviceLorry.isNotEmpty
                  ? resolvedDeviceLorry
                  : (isValidLineLoc ? rawLoc : 'LOC1');
              return {
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
                "stockStatus": l['stockStatus'] ?? 'A',
                "returnCondition": l['returnCondition'] ?? cn['reason'],
                "expiryDate": l['expiryDate'],
                "location": resolvedLineLoc,
                "originLineNo": l['originLineNo'] ?? l['lineNo']
              };
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
            String? x3StockReceiptId;
            String? x3RefundPaymentId;
            bool stockReceiptSynced = false;
            String? stockReceiptError;
            if (response.data is Map) {
              if (response.data['x3StockReceiptId'] != null &&
                  response.data['x3StockReceiptId'].toString().trim().isNotEmpty) {
                x3StockReceiptId = response.data['x3StockReceiptId'].toString().trim();
              }
              if (response.data['x3RefundPaymentId'] != null &&
                  response.data['x3RefundPaymentId'].toString().trim().isNotEmpty) {
                x3RefundPaymentId = response.data['x3RefundPaymentId'].toString().trim();
              }
              stockReceiptSynced = response.data['stockReceiptSynced'] == true;
              if (response.data['stockReceiptError'] != null &&
                  response.data['stockReceiptError'].toString().trim().isNotEmpty) {
                stockReceiptError = response.data['stockReceiptError'].toString().trim();
              }
            }

            await LocalDatabaseHelper.instance.markCreditNoteSynced(
              creditNoteId,
              x3DocumentId: displayId,
              x3StockReceiptId: x3StockReceiptId,
              x3RefundPaymentId: x3RefundPaymentId,
            );
            if (response.data is Map && (response.data['refundSynced'] == true || x3RefundPaymentId != null)) {
              await LocalDatabaseHelper.instance.markCreditNoteRefundsSynced(creditNoteId, x3PaymentId: x3RefundPaymentId);
            }
            if (x3StockReceiptId != null || stockReceiptSynced) {
              await LocalDatabaseHelper.instance.markCreditNoteStockReceiptSynced(
                creditNoteId,
                x3ReceiptId: x3StockReceiptId ?? 'ZSMRWEBA-OK',
              );
            }
            successes.add(displayId);
            final List<String> msgs = [];
            if (response.data is Map && response.data['messages'] is List) {
              msgs.addAll((response.data['messages'] as List).map((m) => m.toString()));
            }
            if (msgs.isEmpty) {
              msgs.add('Created in Sage X3: $displayId');
            }
            if (category == 3 && !msgs.any((m) => m.contains('ZSMRWEBA'))) {
              if (stockReceiptSynced || x3StockReceiptId != null) {
                msgs.add('Misc Stock Receipt (ZSMRWEBA) created in Sage X3: ${x3StockReceiptId ?? "OK"}');
              } else if (stockReceiptError != null) {
                msgs.add('Misc Stock Receipt (ZSMRWEBA) failed: $stockReceiptError');
              }
            }
            entityReports.add(SyncEntityReport(
              entityName: displayId,
              direction: SyncDirection.upload,
              status: SyncStatus.success,
              count: 1,
              documentId: displayId,
              messages: msgs,
            ));

            // Add explicit Misc Stock Receipt (ZSMRWEBA) report card for Customer Returns
            if (category == 3 || stockReceiptSynced || x3StockReceiptId != null || stockReceiptError != null) {
              if (stockReceiptSynced || x3StockReceiptId != null) {
                final receiptId = x3StockReceiptId ?? 'ZSMRWEBA ($creditNoteId)';
                successes.add(receiptId);
                entityReports.add(SyncEntityReport(
                  entityName: receiptId,
                  direction: SyncDirection.upload,
                  status: SyncStatus.success,
                  count: 1,
                  documentId: receiptId,
                  messages: [
                    'Misc Stock Receipt (ZSMRWEBA) created in Sage X3: $receiptId (Return $creditNoteId)',
                  ],
                ));
              } else if (stockReceiptError != null) {
                final err = 'Misc Stock Receipt ($creditNoteId): $stockReceiptError';
                failures.add(err);
                entityReports.add(SyncEntityReport(
                  entityName: 'ZSMRWEBA ($creditNoteId)',
                  direction: SyncDirection.upload,
                  status: SyncStatus.failed,
                  errorCode: 'ERR_UPLOAD_MISC_RECEIPT',
                  userMessage: err,
                  technicalDetails: stockReceiptError,
                  documentId: creditNoteId,
                  messages: ['Misc Stock Receipt (ZSMRWEBA) failed: $stockReceiptError'],
                ));
              }
            }
          } else {
            final err = '$creditNoteId: ${response.data}';
            failures.add(err);
            entityReports.add(SyncEntityReport(
              entityName: creditNoteId,
              direction: SyncDirection.upload,
              status: SyncStatus.failed,
              errorCode: 'ERR_UPLOAD_CREDIT_NOTE',
              userMessage: err,
              technicalDetails: 'HTTP ${response.statusCode}: ${response.data}',
              documentId: creditNoteId,
              messages: [err],
            ));
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
                entityReports.add(SyncEntityReport(
                  entityName: 'Credit Note $displayId',
                  direction: SyncDirection.upload,
                  status: SyncStatus.success,
                  count: 1,
                  documentId: displayId,
                  messages: ['Recovered in Sage X3: $displayId'],
                ));
              } else {
                final List<String> msgs = [];
                if (data['messages'] is List) {
                  msgs.addAll((data['messages'] as List).map((m) => m.toString()));
                }
                final err = data['error']?.toString() ?? '$data';
                if (msgs.isEmpty && err.isNotEmpty) {
                  msgs.add(err);
                }
                final userMsg = '$creditNoteId: $err';
                failures.add(userMsg);
                entityReports.add(SyncEntityReport(
                  entityName: 'Credit Note $creditNoteId',
                  direction: SyncDirection.upload,
                  status: SyncStatus.failed,
                  errorCode: 'ERR_UPLOAD_CREDIT_NOTE',
                  userMessage: userMsg,
                  technicalDetails: '[HTTP ${e.response?.statusCode}] $data',
                  documentId: creditNoteId,
                  messages: msgs,
                ));
              }
            } else {
              final err = '$creditNoteId: [HTTP ${e.response?.statusCode}] $data';
              failures.add(err);
              entityReports.add(SyncEntityReport(
                entityName: 'Credit Note $creditNoteId',
                direction: SyncDirection.upload,
                status: SyncStatus.failed,
                errorCode: 'ERR_UPLOAD_CREDIT_NOTE',
                userMessage: err,
                technicalDetails: '$data',
                documentId: creditNoteId,
                messages: [err],
              ));
            }
          } else {
            final err = '$creditNoteId: Failed to sync ($e)';
            failures.add(err);
            entityReports.add(SyncEntityReport(
              entityName: 'Credit Note $creditNoteId',
              direction: SyncDirection.upload,
              status: SyncStatus.failed,
              errorCode: 'ERR_UPLOAD_CREDIT_NOTE',
              userMessage: err,
              technicalDetails: e.toString(),
              documentId: creditNoteId,
              messages: [err],
            ));
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
                if (res is Map) {
                  final bool paySuccess = res['success'] == true;
                  final docId = res['documentId']?.toString() ?? 'Payment';
                  final x3PayId = res['x3PaymentId']?.toString();
                  final x3InvDocId = res['x3InvoiceDocumentId']?.toString();
                  if (paySuccess) {
                    if (docId.isNotEmpty) {
                      await LocalDatabaseHelper.instance.markPaymentsSynced(
                        docId,
                        x3PaymentId: x3PayId,
                        x3InvoiceDocumentId: x3InvDocId,
                      );
                    }
                    successes.add(x3PayId ?? docId);
                    entityReports.add(SyncEntityReport(
                      entityName: 'Payment for $docId',
                      direction: SyncDirection.upload,
                      status: SyncStatus.success,
                      count: 1,
                      documentId: x3PayId,
                      messages: ['Payment allocated in Sage X3: ${x3PayId ?? 'OK'}'],
                    ));
                  } else {
                    final payErr = res['error']?.toString() ?? 'Payment sync failed';
                    failures.add('Payment for $docId: $payErr');
                    entityReports.add(SyncEntityReport(
                      entityName: 'Payment for $docId',
                      direction: SyncDirection.upload,
                      status: SyncStatus.failed,
                      errorCode: 'ERR_UPLOAD_PAYMENT',
                      userMessage: payErr,
                      documentId: docId,
                      messages: [payErr],
                    ));
                  }
                }
              }
            }
          }
        }
      } catch (payRetryEx) {
        debugPrint('Sync: Standalone payment sync retry warning: $payRetryEx');
      }

      // 4. Push Unsynced Open Invoice Payments
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
      } // end if (!downloadOnly)

      if (!uploadOnly) {
      final prefs = await SharedPreferences.getInstance();
      final effectiveSiteKey = siteCode.isNotEmpty ? siteCode : 'default';
      final openInvEtagKey = 'etag_open_invoices_$effectiveSiteKey';
      final x3HistoryEtagKey = 'etag_x3_history_$effectiveSiteKey';
      final priceListEtagKey = 'etag_price_lists';

      // Helper to safely execute a network request with optional ETag 304 caching
      Future<Response?> safeGet(
        String path, {
        Map<String, dynamic>? queryParameters,
        Options? options,
        required String label,
        String? etagKey,
      }) async {
        final itemStopwatch = Stopwatch()..start();
        try {
          final effectiveOptions = options ?? Options();
          effectiveOptions.validateStatus = (status) => status != null && ((status >= 200 && status < 300) || status == 304);

          if (etagKey != null) {
            final cachedEtag = prefs.getString(etagKey);
            if (cachedEtag != null && cachedEtag.isNotEmpty) {
              effectiveOptions.headers = {
                ...?effectiveOptions.headers,
                'If-None-Match': cachedEtag,
              };
            }
          }

          final resp = await _dio.get(path, queryParameters: queryParameters, options: effectiveOptions);

          if (resp.statusCode == 304) {
            debugPrint('Sync: $label is up-to-date (HTTP 304 Not Modified). Bypassing download.');
            entityReports.add(SyncEntityReport(
              entityName: label,
              direction: SyncDirection.download,
              status: SyncStatus.cached304,
              duration: itemStopwatch.elapsed,
            ));
            return resp;
          }

          if (etagKey != null && resp.statusCode == 200) {
            final newEtag = resp.headers.value('etag');
            if (newEtag != null && newEtag.isNotEmpty) {
              await prefs.setString(etagKey, newEtag);
            }
          }

          final int count = (resp.data is List) ? (resp.data as List).length : 1;
          entityReports.add(SyncEntityReport(
            entityName: label,
            direction: SyncDirection.download,
            status: SyncStatus.success,
            count: count,
            duration: itemStopwatch.elapsed,
          ));

          return resp;
        } on DioException catch (e) {
          debugPrint('Sync: Failed to fetch $label ($path): $e');
          final isOffline = e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              (e.error != null && e.error.toString().toLowerCase().contains('offline'));
          final errCode = (e.error != null && e.error.toString().contains('offline'))
              ? 'ERR_AUTH_OFFLINE_SESSION'
              : (isOffline ? 'ERR_NET_UNREACHABLE' : 'ERR_HTTP_${e.response?.statusCode ?? "NET"}');
          final errMsg = isOffline
              ? (e.error?.toString() ?? 'Network connection failed')
              : (e.response?.statusMessage ?? e.message ?? 'Server error');
          final failMsg = '$label: $errMsg';
          failures.add(failMsg);
          entityReports.add(SyncEntityReport(
            entityName: label,
            direction: SyncDirection.download,
            status: SyncStatus.failed,
            errorCode: errCode,
            userMessage: failMsg,
            technicalDetails: '$path -> [${e.response?.statusCode}] ${e.message}',
            duration: itemStopwatch.elapsed,
          ));
          return null;
        } catch (e) {
          debugPrint('Sync: Failed to fetch $label ($path): $e');
          final failMsg = '$label: $e';
          failures.add(failMsg);
          entityReports.add(SyncEntityReport(
            entityName: label,
            direction: SyncDirection.download,
            status: SyncStatus.failed,
            errorCode: 'ERR_UNKNOWN',
            userMessage: failMsg,
            technicalDetails: '$path -> $e',
            duration: itemStopwatch.elapsed,
          ));
          return null;
        }
      }

      final schemaStr = await SecureStorageService().getSchema();
      final schema = (schemaStr == null || schemaStr.isEmpty) ? 'INLDRYRUN' : schemaStr;
      if (schema == 'INLDRYRUN') {
        debugPrint('⚠️ WARNING: Fetching price lists from INLDRYRUN schema. Ensure the correct schema is configured in app settings. Prices may not reflect production rules.');
      }

      debugPrint('Sync: Downloading Sage X3 facility mappings first to align financial and shipping sites...');
      final facilitiesResp = await safeGet('SalesInvoice/facilities', label: 'Facilities');
      if (facilitiesResp != null && facilitiesResp.data is List) {
        final rawFacilities = facilitiesResp.data as List<dynamic>;
        if (rawFacilities.isNotEmpty) {
          await LocalDatabaseHelper.instance.refreshFacilities(rawFacilities);
          debugPrint('Sync: Synced ${rawFacilities.length} Sage X3 Facility Mappings.');
        }
      }

      // Resolve centralized SiteContext (Shipping vs Financial facilities)
      final siteCtx = await LocalDatabaseHelper.instance.getSiteContext(siteCode);
      debugPrint('Sync: Resolved $siteCtx');

      final custParams = <String, dynamic>{};
      if (siteCtx.financialSiteCode.isNotEmpty) {
        custParams['sitecode'] = siteCtx.financialSiteCode;
      } else if (siteCtx.shippingSiteCode.isNotEmpty) {
        custParams['sitecode'] = siteCtx.shippingSiteCode;
      }

      final openInvParams = <String, dynamic>{'daysCutoff': 0};
      if (siteCtx.financialSiteCode.isNotEmpty) {
        openInvParams['sitecode'] = siteCtx.financialSiteCode;
      }

      final x3Params = <String, dynamic>{'months': 6};
      if (siteCtx.financialSiteCode.isNotEmpty && siteCtx.financialSiteCode != 'ALL') {
        x3Params['sitecode'] = siteCtx.financialSiteCode;
      }

      debugPrint('Sync: Initiating parallel download of master data & 6-month X3 history...');

      final results = await Future.wait([
        safeGet('SalesInvoice/customers', queryParameters: custParams.isNotEmpty ? custParams : null, label: 'Customers'),
        safeGet('SalesInvoice/tax-determinations', label: 'Tax Determinations'),
        safeGet('SalesInvoice/tax-rates', label: 'Tax Rates'),
        safeGet('SalesInvoice/price-lists', queryParameters: {'schema': schema}, label: 'Price Lists', etagKey: priceListEtagKey),
        safeGet('SalesInvoice/salesreps', queryParameters: siteCtx.financialSiteCode.isNotEmpty ? {'siteCode': siteCtx.financialSiteCode} : null, label: 'Sales Reps'),
        safeGet('SalesInvoice/open-invoices', queryParameters: openInvParams, label: 'Open Invoices', etagKey: openInvEtagKey),
        safeGet('SalesInvoice/x3-history', queryParameters: x3Params, options: Options(receiveTimeout: const Duration(seconds: 90)), label: 'X3 History', etagKey: x3HistoryEtagKey),
        safeGet('SalesInvoice/credit-note-reasons', label: 'Credit Note Reasons'),
        safeGet('SalesInvoice/banks', label: 'Banks'),
        safeGet('Sync/refresh', queryParameters: siteCtx.shippingSiteCode.isNotEmpty ? {'site': siteCtx.shippingSiteCode} : null, label: 'Sales Orders'),
        safeGet('SalesInvoice/document-sequences', queryParameters: siteCtx.financialSiteCode.isNotEmpty ? {'siteCode': siteCtx.financialSiteCode} : null, label: 'Document Sequences'),
        _productRepository.syncSalesInvoiceItemStockDetails(siteCtx.shippingSiteCode).then((_) {
          entityReports.add(const SyncEntityReport(
            entityName: 'Stock Details',
            direction: SyncDirection.download,
            status: SyncStatus.success,
          ));
          return null;
        }).catchError((e) {
          debugPrint('Sync: Failed to fetch stock details: $e');
          final isOffline = e.toString().toLowerCase().contains('offline') || e.toString().toLowerCase().contains('connection');
          final errCode = isOffline ? 'ERR_AUTH_OFFLINE_SESSION' : 'ERR_STOCK_SYNC';
          final errUser = isOffline ? 'Stock Details: Operating in offline mode' : 'Stock Details: $e';
          failures.add(errUser);
          entityReports.add(SyncEntityReport(
            entityName: 'Stock Details',
            direction: SyncDirection.download,
            status: SyncStatus.failed,
            errorCode: errCode,
            userMessage: errUser,
            technicalDetails: 'syncSalesInvoiceItemStockDetails: $e',
          ));
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
      final salesOrdersResp = results.length > 9 ? results[9] : null;
      final docSeqResp = results.length > 10 ? results[10] : null;

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

      // Ingest Price Lists (Direct Sync with ETag 304)
      if (priceListResp != null && priceListResp.statusCode != 304 && priceListResp.data is List) {
        final priceLists = priceListResp.data as List<dynamic>;
        await LocalDatabaseHelper.instance.refreshPriceLists(priceLists);
        debugPrint('Sync: Synced ${priceLists.length} Price Lists directly from Sage X3.');
      } else if (priceListResp?.statusCode == 304) {
        debugPrint('Sync: Price Lists unchanged (HTTP 304), preserved local SQLite cache.');
      }

      // Ingest Sales Reps
      if (repsResp != null && repsResp.data is List) {
        final rawReps = repsResp.data as List<dynamic>;
        final repsList = rawReps.map((item) => Map<String, dynamic>.from(item as Map)).toList();
        await LocalDatabaseHelper.instance.upsertSalesReps(repsList);
        debugPrint('Sync: Synced ${repsList.length} Sales Reps.');
      }

      // Ingest Open Invoices
      if (openInvResp != null && openInvResp.statusCode != 304 && openInvResp.data is List) {
        final rawOpenInvoices = openInvResp.data as List<dynamic>;
        await LocalDatabaseHelper.instance.refreshOpenInvoices(rawOpenInvoices);
        debugPrint('Sync: Synced ${rawOpenInvoices.length} Open Invoices & Credit Notes (Site: $siteCode, Cutoff: 90d).');
      } else if (openInvResp?.statusCode == 304) {
        debugPrint('Sync: Open Invoices unchanged (HTTP 304), preserved local SQLite cache.');
      }

      // Ingest 6-Month X3 History
      if (x3Resp != null && x3Resp.statusCode != 304 && x3Resp.data is List) {
        final rawX3Docs = x3Resp.data as List<dynamic>;
        if (rawX3Docs.isNotEmpty) {
          await LocalDatabaseHelper.instance.pruneX3HistoryOlderThan(months: 6);
          await LocalDatabaseHelper.instance.saveX3HistoryDocuments(rawX3Docs);
          debugPrint('Sync: Synced ${rawX3Docs.length} X3 History Documents (Site: $siteCode, 6 months).');
        }
      } else if (x3Resp?.statusCode == 304) {
        debugPrint('Sync: X3 History unchanged (HTTP 304), preserved local SQLite cache.');
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

      // Ingest Real Sales Orders & Details
      if (salesOrdersResp != null && salesOrdersResp.data is Map) {
        final pkg = salesOrdersResp.data as Map<String, dynamic>;
        final rawOrders = pkg['orders'] as List<dynamic>? ?? [];
        final rawDetails = pkg['details'] as List<dynamic>? ?? [];
        if (rawOrders.isNotEmpty || rawDetails.isNotEmpty) {
          await LocalDatabaseHelper.instance.refreshSalesOrdersAndDetails(
            orders: rawOrders,
            details: rawDetails,
          );
          debugPrint('Sync: Synced ${rawOrders.length} Sales Orders and ${rawDetails.length} Line Items for Site $siteCode.');
        }
      }

      // Ingest Document Sequence High-Water Marks
      if (docSeqResp != null && docSeqResp.data is List) {
        final rawDocSeqs = docSeqResp.data as List<dynamic>;
        if (rawDocSeqs.isNotEmpty) {
          await LocalDatabaseHelper.instance.syncDocumentSequencesHighWaterMark(rawDocSeqs);
          debugPrint('Sync: Synced ${rawDocSeqs.length} Document Sequences high-water marks.');
        }
      }
      } else {
        if (entityReports.isEmpty) {
          entityReports.add(SyncEntityReport(
            entityName: 'Sage X3 SOAP Export',
            direction: SyncDirection.upload,
            status: SyncStatus.success,
            count: 0,
            messages: ['No pending SOAP records to export. All local transactions are up to date.'],
          ));
        }
      }

      final duration = stopwatch.elapsedMilliseconds;
      debugPrint('${uploadOnly ? "Export to Sage X3" : "Sales Invoice Sync"} completed in ${duration}ms (Reports: ${entityReports.length}, Successes: ${successes.length}, Failures: ${failures.length})');
      
      String? finalError;
      if (failures.isNotEmpty) {
        final successfulDownloads = entityReports.where((r) => r.direction == SyncDirection.download && (r.status == SyncStatus.success || r.status == SyncStatus.cached304));
        if (successfulDownloads.isEmpty && successes.isEmpty) {
          finalError = failures.first;
        } else {
          finalError = '${uploadOnly ? "Export" : "Sync"} completed with ${failures.length} issue(s).';
        }
      }

      final result = SyncBatchResult(
        successes: successes,
        failures: failures,
        errorMessage: finalError,
        reports: entityReports,
      );

      try {
        final historyStatus = result.isCleanSuccess
            ? 'Success'
            : (result.hasFailures ? 'Partial' : 'Failed');
        final historyMsg = uploadOnly
            ? (result.isCleanSuccess
                ? 'Export to X3 completed (${result.successes.length} items)'
                : (result.failures.isNotEmpty
                    ? 'Export to X3 finished with ${result.failures.length} errors'
                    : 'Export to X3 completed'))
            : (result.isCleanSuccess
                ? 'Sales sync completed (${result.successes.length} items)'
                : (result.failures.isNotEmpty
                    ? 'Sales sync finished with ${result.failures.length} errors'
                    : 'Sales sync completed'));
        await LocalDatabaseHelper.instance.insertSyncHistory(
          status: historyStatus,
          message: historyMsg,
          site: siteCode,
          counts: {
            'successes': result.successes.length,
            'failures': result.failures.length,
          },
        );
        if (!uploadOnly) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('last_sync_timestamp', DateTime.now().toIso8601String());
        }
      } catch (histErr) {
        debugPrint('Failed to save local sync history: $histErr');
      }

      try {
        final devId = DeviceInfoService.instance.deviceId.isNotEmpty 
            ? DeviceInfoService.instance.deviceId 
            : DeviceInfoService.instance.deviceInfo;
        await _dio.post('Sync/log-event', data: {
          'deviceId': devId,
          'actionType': uploadOnly ? 'EXPORT_PENDING_X3' : (downloadOnly ? 'SYNC_SALES_CATALOG' : 'SYNC_SALES_FULL'),
          'site': siteCode,
          'payload': jsonEncode({
            'successCount': successes.length,
            'failureCount': failures.length,
            'isCleanSuccess': result.isCleanSuccess,
            'uploadOnly': uploadOnly,
            'downloadOnly': downloadOnly,
          }),
        });
      } catch (logErr) {
        debugPrint('DeviceSync log-event error: $logErr');
      }

      return result;
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

      try {
        await LocalDatabaseHelper.instance.insertSyncHistory(
          status: 'Failed',
          message: 'Sales sync error: $serverError',
          site: siteCode,
        );
      } catch (_) {}

      return SyncBatchResult(successes: successes, failures: failures, errorMessage: serverError, reports: entityReports);
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

      try {
        await LocalDatabaseHelper.instance.insertSyncHistory(
          status: 'Failed',
          message: 'Sales sync error: $serverError',
          site: siteCode,
        );
      } catch (_) {}

      return SyncBatchResult(successes: successes, failures: failures, errorMessage: serverError, reports: entityReports);
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

  /// Synchronizes all live information for ONLY the selected customer:
  /// - Live Balance & Credit Limits from Sage X3 (GACCDUDATE / BPCUSTOMER)
  /// - Master profile details (Terms, Tax Rule, Status)
  /// - Open Invoices & Credit Notes (90 Days)
  /// - 6-Month Invoiced X3 History & Line Pricing
  Future<CustomerSyncResult> syncSingleCustomerData({
    required String customerCode,
    String? siteCode,
  }) async {
    final code = customerCode.trim();
    if (code.isEmpty) {
      return const CustomerSyncResult(
        success: false,
        customerCode: '',
        errorMessage: 'Invalid customer code provided.',
      );
    }

    // Pre-flight session check
    final token = await SecureStorageService().getToken();
    if (token == null || token.isEmpty || token.startsWith('OFFLINE_SESSION_')) {
      const msg = 'Device is operating in Offline Mode. Connect to company network to synchronize this customer.';
      debugPrint('Sync: Cannot sync customer $code while in offline session ($token).');
      return CustomerSyncResult(
        success: false,
        customerCode: code,
        errorMessage: msg,
      );
    }

    try {
      debugPrint('Sync: Starting targeted sync for customer: $code (Site: ${siteCode ?? "DEFAULT"})');

      final effectiveSite = (siteCode != null && siteCode.isNotEmpty && siteCode != 'ALL') ? siteCode : '';

      final openInvParams = <String, dynamic>{
        'customerno': code,
        'daysCutoff': 0,
      };
      if (effectiveSite.isNotEmpty) openInvParams['sitecode'] = effectiveSite;

      final x3Params = <String, dynamic>{
        'customercode': code,
        'months': 6,
      };
      if (effectiveSite.isNotEmpty) x3Params['sitecode'] = effectiveSite;

      // 1. Parallel fetch of Customer Live Credit, Profile, Open Invoices, and 6-Month X3 History
      final responses = await Future.wait([
        // [0] Live Credit & Balance
        _dio.get(
          'SalesInvoice/customer/$code/live-credit',
          options: Options(receiveTimeout: const Duration(seconds: 15)),
        ).catchError((e) {
          debugPrint('Sync: live-credit error for $code: $e');
          return Response(requestOptions: RequestOptions(path: ''), statusCode: 500);
        }),
        // [1] Full Customer Profile
        _dio.get(
          'SalesInvoice/customer/$code',
          options: Options(receiveTimeout: const Duration(seconds: 15)),
        ).catchError((e) {
          debugPrint('Sync: customer profile error for $code: $e');
          return Response(requestOptions: RequestOptions(path: ''), statusCode: 500);
        }),
        // [2] Customer Open Invoices
        _dio.get(
          'SalesInvoice/open-invoices',
          queryParameters: openInvParams,
          options: Options(receiveTimeout: const Duration(seconds: 25)),
        ).catchError((e) {
          debugPrint('Sync: open-invoices error for $code: $e');
          return Response(requestOptions: RequestOptions(path: ''), statusCode: 500);
        }),
        // [3] Customer 6-Month X3 History
        _dio.get(
          'SalesInvoice/x3-history',
          queryParameters: x3Params,
          options: Options(receiveTimeout: const Duration(seconds: 35)),
        ).catchError((e) {
          debugPrint('Sync: x3-history error for $code: $e');
          return Response(requestOptions: RequestOptions(path: ''), statusCode: 500);
        }),
      ]);

      final liveCreditResp = responses[0];
      final profileResp = responses[1];
      final openInvResp = responses[2];
      final x3HistoryResp = responses[3];

      double liveBalance = 0.0;
      double creditLimit = 0.0;
      String statusFlag = '1';
      String? paymentTerm;
      String? taxRule;
      String? customerName;

      // Ingest Profile & Live Credit
      if (liveCreditResp.statusCode == 200 && liveCreditResp.data is Map) {
        final creditData = liveCreditResp.data as Map;
        liveBalance = (creditData['liveOutstandingBalance'] as num?)?.toDouble() ?? 0.0;
        creditLimit = (creditData['authorizedCreditLimit'] as num?)?.toDouble() ?? 0.0;
        statusFlag = (creditData['creditControlStatus'] ?? '1').toString().trim();
      }

      if (profileResp.statusCode == 200 && profileResp.data is Map) {
        final profData = profileResp.data as Map;
        paymentTerm = profData['paymentTerm']?.toString().trim();
        taxRule = profData['taxRule']?.toString().trim();
        customerName = profData['name']?.toString().trim();
        if (creditLimit == 0.0) {
          creditLimit = (profData['creditLimit'] as num?)?.toDouble() ?? 0.0;
        }
        if (statusFlag.isEmpty || statusFlag == '1') {
          statusFlag = (profData['statusFlag'] ?? '1').toString().trim();
        }
      }

      await LocalDatabaseHelper.instance.updateCustomerProfileAndFinancials(
        customerCode: code,
        outstandingBalance: liveBalance,
        creditLimit: creditLimit,
        statusFlag: statusFlag,
        paymentTerm: paymentTerm,
        taxRule: taxRule,
        name: customerName,
      );

      // Ingest Open Invoices
      int openCount = 0;
      if (openInvResp.statusCode == 200 && openInvResp.data is List) {
        final openInvoicesList = openInvResp.data as List<dynamic>;
        openCount = await LocalDatabaseHelper.instance.refreshOpenInvoicesForCustomer(code, openInvoicesList);
        debugPrint('Sync: Ingested ${openInvoicesList.length} open invoices ($openCount active) for $code.');
      }

      // Ingest X3 History
      int historyCount = 0;
      if (x3HistoryResp.statusCode == 200 && x3HistoryResp.data is List) {
        final historyList = x3HistoryResp.data as List<dynamic>;
        historyCount = await LocalDatabaseHelper.instance.refreshX3HistoryForCustomer(code, historyList);
        debugPrint('Sync: Ingested $historyCount X3 history invoices for $code.');
      }

      return CustomerSyncResult(
        success: true,
        customerCode: code,
        liveBalance: liveBalance,
        creditLimit: creditLimit,
        statusFlag: statusFlag,
        openInvoicesCount: openCount,
        x3HistoryInvoicesCount: historyCount,
      );
    } catch (e) {
      debugPrint('Sync: Failed to sync customer $code: $e');
      return CustomerSyncResult(
        success: false,
        customerCode: code,
        errorMessage: 'Failed to sync customer: $e',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getLatestBackendSyncResponses({String? siteCode, int limit = 20}) async {
    try {
      final resp = await _dio.get('SalesInvoice/sync-responses/latest', queryParameters: {
        if (siteCode != null && siteCode.isNotEmpty && siteCode != 'ALL') 'siteCode': siteCode,
        'limit': limit,
      });
      if (resp.statusCode == 200 && resp.data is List) {
        return (resp.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching backend sync responses: $e');
      return [];
    }
  }
}
