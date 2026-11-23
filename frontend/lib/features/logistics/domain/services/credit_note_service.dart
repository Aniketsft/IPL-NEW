import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/credit_note_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/models/stock_status.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/document_sequence_service.dart';
import 'package:enterprise_auth_mobile/core/services/device_info_service.dart';

typedef DbProvider = Future<Database> Function();

class CreditNoteService {
  final DbProvider _dbProvider;

  CreditNoteService({DbProvider? dbProvider})
      : _dbProvider = dbProvider ?? (() => LocalDatabaseHelper.instance.database);

  Future<Set<String>> _getTableColumns(Transaction txn, String tableName) async {
    final rows = await txn.rawQuery('PRAGMA table_info($tableName)');
    return rows
        .map((r) => (r['name'] ?? '').toString())
        .where((n) => n.isNotEmpty)
        .toSet();
  }

  Future<void> _insertCreditNoteLine(
    Transaction txn,
    Map<String, Object?> row,
  ) async {
    final cols = await _getTableColumns(
      txn,
      LocalDatabaseHelper.tableSiCreditNoteLines,
    );
    final filtered = cols.isEmpty
        ? row
        : Map<String, Object?>.fromEntries(
            row.entries.where((e) => cols.contains(e.key)),
          );
    await txn.insert(LocalDatabaseHelper.tableSiCreditNoteLines, filtered);
  }

  String _resolveReturnStockStatus({
    String? explicitStockStatus,
    String? reason,
    int stockTransaction = 0,
  }) {
    final trimmed = (explicitStockStatus ?? '').trim();
    if (trimmed.isNotEmpty) {
      final explicit = StockStatus.fromCode(trimmed).code;
      if (explicit != StockStatus.codeApproved) {
        return explicit;
      }
    }
    final upperReason = (reason ?? '').trim().toUpperCase();
    if (upperReason.contains('DEF') ||
        upperReason.contains('DAM') ||
        upperReason.contains('REJ')) {
      return StockStatus.codeRejected;
    }
    if (upperReason.contains('EXP') || upperReason.contains('QUAR')) {
      return StockStatus.codeQuarantine;
    }
    if (trimmed.isNotEmpty) {
      return StockStatus.fromCode(trimmed).code;
    }
    if (stockTransaction == 1) {
      return StockStatus.fromReturnReason(reason).code;
    }
    return StockStatus.codeQuarantine;
  }

  Future<void> _replenishLocalStock(
    Transaction txn, {
    required String sku,
    required String itemName,
    required String lotNumber,
    required String warehouse,
    required String location,
    required double quantity,
    required String stockStatus,
    required String now,
    String taxLevel = '',
    String cce0 = '',
    String salesUnit = '',
  }) async {
    if (sku.isEmpty || lotNumber.isEmpty || warehouse.isEmpty || location.isEmpty) {
      return;
    }
    final stockCols = await _getTableColumns(
      txn,
      LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
    );
    final hasStatusCol = stockCols.isEmpty || stockCols.contains('stockStatus');
    final normalizedStatus = StockStatus.fromCode(stockStatus).code;
    final updated = await txn.rawUpdate(
      hasStatusCol
          ? '''
      UPDATE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} 
      SET totalQty = totalQty + ? 
      WHERE itemCode = ? AND lotNumber = ? AND warehouse = ? AND location = ?
        AND COALESCE(NULLIF(UPPER(TRIM(stockStatus)), ''), 'A') = ?
      '''
          : '''
      UPDATE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} 
      SET totalQty = totalQty + ? 
      WHERE itemCode = ? AND lotNumber = ? AND warehouse = ? AND location = ?
      ''',
      hasStatusCol
          ? [quantity, sku, lotNumber, warehouse, location, normalizedStatus]
          : [quantity, sku, lotNumber, warehouse, location],
    );

    if (updated == 0) {
      final assignedSite = (DeviceInfoService.instance.assignedSite ?? '').trim().toUpperCase();
      final row = <String, Object?>{
        'itemCode': sku,
        'itemName': itemName,
        'lotNumber': lotNumber,
        'warehouse': warehouse,
        'location': location,
        'totalQty': quantity,
        'taxLevel': taxLevel,
        'cce0': cce0,
        'salesUnit': salesUnit,
        'siteCode': assignedSite,
        'stockStatus': normalizedStatus,
        'isSynced': 1,
        'createdAt': now,
      };
      final filtered = stockCols.isEmpty
          ? row
          : Map<String, Object?>.fromEntries(
              row.entries.where((e) => stockCols.contains(e.key)),
            );
      await txn.insert(
        LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
        filtered,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> _ensureRefundTrackingColumns(DatabaseExecutor db) async {
    try {
      final info = await db.rawQuery(
        'PRAGMA table_info(${LocalDatabaseHelper.tableSiCreditNoteRefunds})',
      );
      final existing = info
          .map((r) => (r['name'] as String?)?.toLowerCase() ?? '')
          .toSet();
      if (!existing.contains('cashInHandBefore'.toLowerCase())) {
        await db.execute(
          'ALTER TABLE ${LocalDatabaseHelper.tableSiCreditNoteRefunds} ADD COLUMN cashInHandBefore REAL DEFAULT 0.0',
        );
      }
      if (!existing.contains('cashShortfallAmount'.toLowerCase())) {
        await db.execute(
          'ALTER TABLE ${LocalDatabaseHelper.tableSiCreditNoteRefunds} ADD COLUMN cashShortfallAmount REAL DEFAULT 0.0',
        );
      }
    } catch (_) {}
  }

  /// Records a refund row in `tbl_si_credit_note_refunds` and silently tracks
  /// negative physical cash / shortfall when a CASH refund exceeds cash in hand.
  Future<void> _insertRefundWithShortfallTracking(
    Transaction txn, {
    required String creditNoteId,
    required String method,
    required double amount,
    String? bankCode,
    String? bankName,
    String? chequeNumber,
    String? chequeDate,
    required String createdAt,
    String? deviceId,
    required String userName,
    required String salesSite,
    required String customerCode,
  }) async {
    await _ensureRefundTrackingColumns(txn);

    final methodUpper = method.trim().toUpperCase();
    double cashInHandBefore = 0.0;
    double cashShortfallAmount = 0.0;

    if (methodUpper == CreditNoteRefundMethod.cash) {
      final txDate = DateTime.tryParse(createdAt) ?? DateTime.now();
      cashInHandBefore =
          await LocalDatabaseHelper.computePhysicalCashInHandForDate(txn, txDate);
      final cashAfter = cashInHandBefore - amount;
      if (cashAfter < -0.0001) {
        cashShortfallAmount = cashInHandBefore >= 0 ? -cashAfter : amount;
      }
    }

    await txn.insert(LocalDatabaseHelper.tableSiCreditNoteRefunds, {
      'creditNoteId': creditNoteId,
      'method': methodUpper,
      'amount': amount,
      'bankCode': bankCode ?? '',
      'bankName': bankName ?? '',
      'chequeNumber': chequeNumber,
      'chequeDate': chequeDate,
      'isSynced': 0,
      'x3PaymentId': null,
      'syncError': null,
      'createdAt': createdAt,
      'deviceId': deviceId,
      'userName': userName,
      'salesSite': salesSite,
      'customerCode': customerCode,
      'cashInHandBefore': cashInHandBefore,
      'cashShortfallAmount': cashShortfallAmount,
    });

    if (cashShortfallAmount > 0.005) {
      try {
        await txn.insert(LocalDatabaseHelper.tableOfflineAuditLogs, {
          'entity': 'CASH_REFUND',
          'action': 'CASH_REFUND_SHORTFALL',
          'payload': jsonEncode({
            'creditNoteId': creditNoteId,
            'customerCode': customerCode,
            'refundAmount': amount,
            'cashInHandBefore': cashInHandBefore,
            'cashInHandAfter': cashInHandBefore - amount,
            'cashShortfallAmount': cashShortfallAmount,
            'salesSite': salesSite,
            'userName': userName,
          }),
          'timestamp': createdAt,
          'deviceId': deviceId ?? '',
          'isSynced': 0,
        });
      } catch (_) {}
    }
  }

  Future<CreditNoteModel> createReversalCreditNote({
    required String invoiceId,
    required String createdBy,
    String? reason,
    String? reference,
    String? salesRep,
    String? deviceId,
    int stockTransaction = 0,
    String? stockStatus,
    String? refundMethod,
  }) async {
    final db = await _dbProvider();

    // 1. Fetch origin invoice
    final invRows = await db.query(
      LocalDatabaseHelper.tableSiInvoices,
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );

    if (invRows.isEmpty) {
      throw StateError('Original invoice $invoiceId not found.');
    }

    final invoice = invRows.first;
    if ((invoice['isReversed'] as int? ?? 0) == 1) {
      throw StateError('Invoice $invoiceId has already been reversed.');
    }
    if ((invoice['isPartiallyReversed'] as int? ?? 0) == 1) {
      throw StateError('Invoice $invoiceId has already been partially reversed. Please use partial reversal to reverse remaining items.');
    }

    // 2. Fetch original payments to mirror settlement method
    final payments = await db.query(
      LocalDatabaseHelper.tableSiPayments,
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
    );

    String settlementType = CreditNoteRefundMethod.cash;
    Map<String, dynamic>? primaryPayment;
    if (payments.isNotEmpty) {
      primaryPayment = payments.first;
      settlementType = (primaryPayment['method'] as String? ?? 'CASH').toUpperCase();
    }
    if (refundMethod != null && refundMethod.trim().isNotEmpty) {
      settlementType = refundMethod.trim().toUpperCase();
    }

    // 3. Fetch invoice lines
    final lines = await db.query(
      LocalDatabaseHelper.tableSiInvoiceLines,
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
      orderBy: 'lineId ASC',
    );

    final salesSite = (invoice['salesSite'] as String?) ?? 'POD';
    final customerCode = (invoice['customerCode'] as String?) ?? '';
    final customerName = (invoice['customerName'] as String?) ?? '';
    final docType = (stockTransaction == 1) ? 'RTN' : 'CRN';
    final creditNoteId = await DocumentSequenceService().generateDocumentNumber(
      docType: docType,
      salesSite: salesSite,
      lorryCode: DeviceInfoService.instance.assignedLocation,
      deviceId: deviceId,
    );
    final now = DateTime.now().toIso8601String();
    final grandTotal = (invoice['grandTotal'] as num?)?.toDouble() ?? 0.0;
    if (grandTotal <= 0) {
      throw StateError('Cannot reverse invoice: amount must be greater than zero.');
    }

    final originX3Id = (invoice['x3DocumentId'] as String?)?.trim();
    final resolvedOriginInvoiceId = (originX3Id != null && originX3Id.isNotEmpty)
        ? originX3Id
        : invoiceId;

    final creditNote = CreditNoteModel(
      creditNoteId: creditNoteId,
      creditNoteType: stockTransaction == 1 ? 'RETURN' : CreditNoteType.reversal,
      x3CreditNoteType: stockTransaction == 1 ? 'RTN' : 'CRN',
      salesSite: salesSite,
      customerCode: customerCode,
      customerName: customerName,
      currency: 'MUR',
      grandTotal: grandTotal,
      originalInvoiceId: resolvedOriginInvoiceId,
      settlementType: settlementType,
      reference: reference ?? '',
      isSynced: 0,
      createdAt: now,
      createdBy: createdBy,
      deviceId: deviceId,
      reason: reason,
      salesRep: salesRep ?? (invoice['salesRep'] as String?),
      transactionMode: '4',
      stockTransaction: stockTransaction,
    );

    // Fetch default bank outside transaction to prevent sqflite lock contention
    final defaultBank = await LocalDatabaseHelper.instance.getDefaultBank(salesSite);
    final resolvedBankCode = (primaryPayment?['bankCode'] != null && (primaryPayment!['bankCode'] as String).trim().isNotEmpty)
        ? primaryPayment['bankCode'].toString().trim()
        : (defaultBank['bankCode'] ?? '');
    final resolvedBankName = (primaryPayment?['bankName'] != null && (primaryPayment!['bankName'] as String).trim().isNotEmpty)
        ? primaryPayment['bankName'].toString().trim()
        : (defaultBank['bankName'] ?? '');

    await db.transaction((txn) async {
      // A. Insert credit note header
      await txn.insert(LocalDatabaseHelper.tableSiCreditNotes, creditNote.toMap());

      // B. Insert lean credit note lines & replenish stock
      int lineNo = 1000;
      for (final line in lines) {
        final originLineId = line['lineId'] as int;
        final qty = (line['quantity'] as num?)?.toDouble() ?? 0.0;

        // Replenish stock as approved sellable (A), rejected/damaged (R), or quarantine/expired (Q)
        final sku = (line['sku'] as String? ?? '').trim();
        final lotNumber = (line['lotNumber'] as String? ?? '').trim();
        final warehouse = (line['warehouse'] as String? ?? '').trim();
        final location = (line['location'] as String? ?? '').trim();
        final returnStatus = _resolveReturnStockStatus(
          explicitStockStatus: stockStatus,
          reason: reason,
          stockTransaction: stockTransaction,
        );

        await _insertCreditNoteLine(txn, {
          'creditNoteId': creditNoteId,
          'lineNo': lineNo,
          'quantity': qty,
          'originInvoiceId': invoiceId,
          'originLineNo': originLineId,
          'stockStatus': returnStatus,
          'returnCondition': reason,
          'expiryDate': line['expiryDate'],
          'location': location,
        });

        await _replenishLocalStock(
          txn,
          sku: sku,
          itemName: (line['name'] ?? '').toString(),
          lotNumber: lotNumber,
          warehouse: warehouse,
          location: location,
          quantity: qty,
          stockStatus: returnStatus,
          now: now,
          taxLevel: (line['taxRule'] ?? '').toString(),
          cce0: (line['cce0'] ?? '').toString(),
          salesUnit: (line['salesUnit'] ?? '').toString(),
        );

        final lineId = line['lineId'].toString();
        await txn.insert(LocalDatabaseHelper.tableSiInvoiceLineReversals, {
          'invoiceId': invoiceId,
          'lineId': lineId,
          'reversedQty': qty,
          'reversalCreditNoteId': creditNoteId,
          'createdAt': now,
        });

        lineNo += 1000;
      }

      // C. Insert refund record (tracks negative cash / shortfall silently)
      await _insertRefundWithShortfallTracking(
        txn,
        creditNoteId: creditNoteId,
        method: settlementType,
        amount: grandTotal,
        bankCode: resolvedBankCode,
        bankName: resolvedBankName,
        chequeNumber: primaryPayment?['chequeNumber']?.toString(),
        chequeDate: primaryPayment?['chequeDate']?.toString(),
        createdAt: now,
        deviceId: deviceId,
        userName: createdBy,
        salesSite: salesSite,
        customerCode: customerCode,
      );

      // D. Mark origin invoice and lines as reversed
      await txn.update(
        LocalDatabaseHelper.tableSiInvoices,
        {'isReversed': 1, 'isPartiallyReversed': 0, 'status': 'REVERSED'},
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );

      await txn.update(
        LocalDatabaseHelper.tableSiInvoiceLines,
        {'isReversed': 1},
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );
    });

    return creditNote;
  }

  /// Creates a credit note for a **partial** invoice reversal.
  ///
  /// [selectedLines] is a list of maps, each containing:
  ///   - 'lineId' (String): the original invoice line ID
  ///   - 'reversedQty' (double): how much quantity to reverse
  Future<CreditNoteModel> createPartialReversalCreditNote({
    required String invoiceId,
    required List<Map<String, dynamic>> selectedLines,
    required String createdBy,
    String? reason,
    String? reference,
    String? salesRep,
    String? deviceId,
    int stockTransaction = 0,
    String? stockStatus,
    String? refundMethod,
  }) async {
    if (selectedLines.isEmpty) {
      throw ArgumentError('At least one line must be selected for partial reversal.');
    }

    final db = await _dbProvider();

    // 1. Fetch origin invoice header
    final invRows = await db.query(
      LocalDatabaseHelper.tableSiInvoices,
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (invRows.isEmpty) throw StateError('Original invoice $invoiceId not found.');
    final invoice = invRows.first;
    if ((invoice['isReversed'] as int? ?? 0) == 1) {
      throw StateError('Invoice $invoiceId has already been fully reversed.');
    }

    // 2. Fetch original payments to mirror settlement method (unless explicitly overridden)
    final payments = await db.query(
      LocalDatabaseHelper.tableSiPayments,
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
    );
    String settlementType = CreditNoteRefundMethod.cash;
    Map<String, dynamic>? primaryPayment;
    if (payments.isNotEmpty) {
      primaryPayment = payments.first;
      settlementType = (primaryPayment['method'] as String? ?? 'CASH').toUpperCase();
    }
    if (refundMethod != null && refundMethod.trim().isNotEmpty) {
      settlementType = refundMethod.trim().toUpperCase();
    }

    // 3. Fetch all original invoice lines
    final allLines = await db.query(
      LocalDatabaseHelper.tableSiInvoiceLines,
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
    );
    final allLinesMap = {for (final l in allLines) l['lineId'].toString(): l};

    // 4. Pre-flight guard: check already-reversed quantities per line
    for (final sel in selectedLines) {
      final lineId = sel['lineId'].toString();
      final requestedQty = (sel['reversedQty'] as num).toDouble();
      final originalLine = allLinesMap[lineId];
      if (originalLine == null) throw StateError('Line $lineId not found in invoice $invoiceId.');
      final originalQty = (originalLine['quantity'] as num?)?.toDouble() ?? 0.0;

      final alreadyReversed = await db.rawQuery(
        'SELECT COALESCE(SUM(reversedQty), 0) as total FROM ${LocalDatabaseHelper.tableSiInvoiceLineReversals} WHERE invoiceId = ? AND lineId = ?',
        [invoiceId, lineId],
      );
      final alreadyQty = (alreadyReversed.first['total'] as num?)?.toDouble() ?? 0.0;
      final remaining = originalQty - alreadyQty;

      if (requestedQty <= 0) throw ArgumentError('Reversed quantity for line $lineId must be positive.');
      if (requestedQty > remaining) {
        throw ArgumentError('Cannot reverse $requestedQty of line $lineId — only $remaining remaining of ordered quantity $originalQty.');
      }
    }

    // 5. Compute grand total from selected lines with pro-rated VAT and discount
    double grandTotal = 0.0;
    final creditNoteLineItems = <Map<String, dynamic>>[];
    for (final sel in selectedLines) {
      final lineId = sel['lineId'].toString();
      final reversedQty = (sel['reversedQty'] as num).toDouble();
      final originalLine = allLinesMap[lineId]!;
      final originalQty = (originalLine['quantity'] as num?)?.toDouble() ?? 1.0;
      final ratio = reversedQty / originalQty;

      final basePrice = (originalLine['basePrice'] as num?)?.toDouble() ?? 0.0;
      final discountAmount = ((originalLine['discountAmountFlat'] ?? originalLine['discountAmount']) as num?)?.toDouble() ?? 0.0;
      final vatAmount = (originalLine['vatAmount'] as num?)?.toDouble() ?? 0.0;

      final lineTotal = basePrice * reversedQty;
      final lineDisc = discountAmount * ratio;
      final lineVat = vatAmount * ratio;
      final lineNet = lineTotal - lineDisc + lineVat;
      grandTotal += lineNet;

      creditNoteLineItems.add({
        'lineId': lineId,
        'reversedQty': reversedQty,
        'originalLine': originalLine,
        'lineNet': lineNet,
      });
    }

    if (grandTotal <= 0) {
      throw StateError('Cannot create partial reversal credit note: total amount must be greater than zero.');
    }

    final salesSite = (invoice['salesSite'] as String?) ?? 'POD';
    final customerCode = (invoice['customerCode'] as String?) ?? '';
    final customerName = (invoice['customerName'] as String?) ?? '';
    final docType = (stockTransaction == 1) ? 'RTN' : 'CRN';
    final creditNoteId = await DocumentSequenceService().generateDocumentNumber(
      docType: docType,
      salesSite: salesSite,
      lorryCode: DeviceInfoService.instance.assignedLocation,
      deviceId: deviceId,
    );
    final now = DateTime.now().toIso8601String();

    final originX3Id = (invoice['x3DocumentId'] as String?)?.trim();
    final resolvedOriginInvoiceId = (originX3Id != null && originX3Id.isNotEmpty)
        ? originX3Id
        : invoiceId;

    final creditNote = CreditNoteModel(
      creditNoteId: creditNoteId,
      creditNoteType: stockTransaction == 1 ? 'RETURN' : CreditNoteType.reversal,
      x3CreditNoteType: stockTransaction == 1 ? 'RTN' : 'CRN',
      salesSite: salesSite,
      customerCode: customerCode,
      customerName: customerName,
      currency: 'MUR',
      grandTotal: grandTotal,
      originalInvoiceId: resolvedOriginInvoiceId,
      settlementType: settlementType,
      reference: reference ?? '',
      isSynced: 0,
      createdAt: now,
      createdBy: createdBy,
      deviceId: deviceId,
      reason: reason,
      salesRep: salesRep ?? (invoice['salesRep'] as String?),
      transactionMode: '4',
      stockTransaction: stockTransaction,
    );

    // Fetch default bank outside transaction to prevent sqflite lock contention
    final defaultBank = await LocalDatabaseHelper.instance.getDefaultBank(salesSite);
    final resolvedBankCode = (primaryPayment?['bankCode'] != null && (primaryPayment!['bankCode'] as String).trim().isNotEmpty)
        ? primaryPayment['bankCode'].toString().trim()
        : (defaultBank['bankCode'] ?? '');
    final resolvedBankName = (primaryPayment?['bankName'] != null && (primaryPayment!['bankName'] as String).trim().isNotEmpty)
        ? primaryPayment['bankName'].toString().trim()
        : (defaultBank['bankName'] ?? '');

    await db.transaction((txn) async {
      // A. Insert credit note header
      await txn.insert(LocalDatabaseHelper.tableSiCreditNotes, creditNote.toMap());

      int lineNo = 1000;
      for (final item in creditNoteLineItems) {
        final lineId = item['lineId'] as String;
        final reversedQty = item['reversedQty'] as double;
        final originalLine = item['originalLine'] as Map<String, dynamic>;

        final sku = (originalLine['sku'] as String? ?? '').trim();
        final lotNumber = (originalLine['lotNumber'] as String? ?? '').trim();
        final warehouse = (originalLine['warehouse'] as String? ?? '').trim();
        final location = (originalLine['location'] as String? ?? '').trim();
        final returnStatus = _resolveReturnStockStatus(
          explicitStockStatus: stockStatus,
          reason: reason,
          stockTransaction: stockTransaction,
        );

        // B. Insert credit note line
        await _insertCreditNoteLine(txn, {
          'creditNoteId': creditNoteId,
          'lineNo': lineNo,
          'quantity': reversedQty,
          'originInvoiceId': invoiceId,
          'originLineNo': lineId,
          'stockStatus': returnStatus,
          'returnCondition': reason,
          'expiryDate': originalLine['expiryDate'],
          'location': location,
        });

        // C. Record this reversal in tbl_si_invoice_line_reversals
        await txn.insert(LocalDatabaseHelper.tableSiInvoiceLineReversals, {
          'invoiceId': invoiceId,
          'lineId': lineId,
          'reversedQty': reversedQty,
          'reversalCreditNoteId': creditNoteId,
          'createdAt': now,
        });

        // D. Replenish stock (partial quantity into A, R, or Q)
        await _replenishLocalStock(
          txn,
          sku: sku,
          itemName: (originalLine['name'] ?? '').toString(),
          lotNumber: lotNumber,
          warehouse: warehouse,
          location: location,
          quantity: reversedQty,
          stockStatus: returnStatus,
          now: now,
          taxLevel: (originalLine['taxRule'] ?? '').toString(),
          cce0: (originalLine['cce0'] ?? '').toString(),
          salesUnit: (originalLine['salesUnit'] ?? '').toString(),
        );

        lineNo += 1000;
      }

      // E. Insert refund record (tracks negative cash / shortfall silently)
      await _insertRefundWithShortfallTracking(
        txn,
        creditNoteId: creditNoteId,
        method: settlementType,
        amount: grandTotal,
        bankCode: resolvedBankCode,
        bankName: resolvedBankName,
        chequeNumber: primaryPayment?['chequeNumber']?.toString(),
        chequeDate: primaryPayment?['chequeDate']?.toString(),
        createdAt: now,
        deviceId: deviceId,
        userName: createdBy,
        salesSite: salesSite,
        customerCode: customerCode,
      );

      // F. Check if ALL lines are now fully reversed → flip isReversed = 1, else isPartiallyReversed = 1
      bool allFullyReversed = true;
      for (final originalLine in allLines) {
        final lineId = originalLine['lineId'].toString();
        final originalQty = (originalLine['quantity'] as num?)?.toDouble() ?? 0.0;
        final reversalRows = await txn.rawQuery(
          'SELECT COALESCE(SUM(reversedQty), 0) as total FROM ${LocalDatabaseHelper.tableSiInvoiceLineReversals} WHERE invoiceId = ? AND lineId = ?',
          [invoiceId, lineId],
        );
        final totalReversed = (reversalRows.first['total'] as num?)?.toDouble() ?? 0.0;
        if (totalReversed < originalQty) {
          allFullyReversed = false;
          break;
        }
      }

      await txn.update(
        LocalDatabaseHelper.tableSiInvoices,
        allFullyReversed
            ? {'isReversed': 1, 'isPartiallyReversed': 0}
            : {'isPartiallyReversed': 1},
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );
    });

    return creditNote;
  }

  Future<CreditNoteModel> createStandaloneCreditNote({
    required String salesSite,
    required String customerCode,
    required String customerName,
    required String refundMethod,
    required double refundAmount,
    required List<CreditNoteLineModel> items,
    required String createdBy,
    String? deviceId,
    String? reference,
    String? reason,
    String? salesRep,
    String? originInvoiceId,
    int stockTransaction = 0,
    String? stockStatus,
  }) async {
    final methodUpper = refundMethod.toUpperCase();
    if (methodUpper == 'QR' || methodUpper.contains('QR')) {
      throw ArgumentError('QR Code refund is strictly disabled for Credit Notes.');
    }

    if (refundAmount <= 0) {
      throw ArgumentError('Credit note refund amount must be greater than zero.');
    }

    if (items.isEmpty) {
      throw ArgumentError('Standalone credit note must contain at least one product.');
    }

    final db = await _dbProvider();
    final docType = (stockTransaction == 1) ? 'RTN' : 'CRN';
    final creditNoteId = await DocumentSequenceService().generateDocumentNumber(
      docType: docType,
      salesSite: salesSite,
      lorryCode: DeviceInfoService.instance.assignedLocation,
      deviceId: deviceId,
    );
    final now = DateTime.now().toIso8601String();

    final creditNote = CreditNoteModel(
      creditNoteId: creditNoteId,
      creditNoteType: stockTransaction == 1
          ? 'RETURN'
          : ((originInvoiceId != null && originInvoiceId.isNotEmpty)
              ? CreditNoteType.reversal
              : CreditNoteType.standalone),
      x3CreditNoteType: stockTransaction == 1 ? 'RTN' : 'CRN',
      salesSite: salesSite,
      customerCode: customerCode,
      customerName: customerName,
      currency: 'MUR',
      grandTotal: refundAmount,
      originalInvoiceId: originInvoiceId,
      settlementType: methodUpper,
      reference: reference,
      isSynced: 0,
      createdAt: now,
      createdBy: createdBy,
      deviceId: deviceId,
      reason: reason,
      salesRep: salesRep,
      transactionMode: (originInvoiceId != null && originInvoiceId.isNotEmpty) ? '4' : '1',
      stockTransaction: stockTransaction,
    );

    // Fetch default bank and device lorry location outside transaction to prevent sqflite lock contention
    final defaultBank = await LocalDatabaseHelper.instance.getDefaultBank(salesSite);
    final defaultBankCode = defaultBank['bankCode'] ?? '';
    final defaultBankName = defaultBank['bankName'] ?? '';
    String deviceLorry = (DeviceInfoService.instance.assignedLocation ?? '').trim();
    if (deviceLorry.isEmpty) {
      try {
        final lookupDevId = (deviceId != null && deviceId.trim().isNotEmpty)
            ? deviceId.trim()
            : DeviceInfoService.instance.deviceId;
        if (lookupDevId.isNotEmpty) {
          final devLoc = await LocalDatabaseHelper.instance.getDeviceLocation(lookupDevId);
          deviceLorry = devLoc?['locationCode']?.toString().trim() ?? '';
        }
      } catch (_) {}
    }

    await db.transaction((txn) async {
      await txn.insert(LocalDatabaseHelper.tableSiCreditNotes, creditNote.toMap());

      final hasOriginInvoice = originInvoiceId != null && originInvoiceId.isNotEmpty;
      List<Map<String, dynamic>> originalInvoiceLines = [];
      List<Map<String, dynamic>> x3HistoryLines = [];
      if (hasOriginInvoice) {
        originalInvoiceLines = await txn.query(
          LocalDatabaseHelper.tableSiInvoiceLines,
          where: 'invoiceId = ?',
          whereArgs: [originInvoiceId],
        );
        if (originalInvoiceLines.isEmpty) {
          x3HistoryLines = await txn.query(
            LocalDatabaseHelper.tableX3HistoryLines,
            where: 'invoiceNumber = ?',
            whereArgs: [originInvoiceId],
          );
        }
      }

      int lineNo = 1000;
      for (final item in items) {
        final sku = item.standaloneSku ?? item.sku;
        final lot = item.standaloneLot ?? item.lot;

        String? matchedLineId = (item.originLineNo != null && item.originLineNo! > 0)
            ? item.originLineNo.toString()
            : null;
        if (hasOriginInvoice && matchedLineId == null) {
          if (originalInvoiceLines.isNotEmpty) {
            final match = originalInvoiceLines.firstWhere(
              (ol) => ol['sku'] == sku && (lot.isEmpty || ol['lotNumber'] == lot),
              orElse: () => originalInvoiceLines.firstWhere(
                (ol) => ol['sku'] == sku,
                orElse: () => <String, dynamic>{},
              ),
            );
            if (match.isNotEmpty && match['lineId'] != null) {
              matchedLineId = match['lineId'].toString();
            }
          } else if (x3HistoryLines.isNotEmpty) {
            final match = x3HistoryLines.firstWhere(
              (xl) => xl['productCode'] == sku,
              orElse: () => <String, dynamic>{},
            );
            if (match.isNotEmpty && match['lineNumber'] != null) {
              matchedLineId = match['lineNumber'].toString();
            }
          }
        }

        final lineStockStatus = _resolveReturnStockStatus(
          explicitStockStatus: (item.stockStatus.isNotEmpty && item.stockStatus != 'A')
              ? item.stockStatus
              : ((stockStatus != null && stockStatus.isNotEmpty)
                  ? stockStatus
                  : (item.stockStatus.isNotEmpty ? item.stockStatus : 'A')),
          reason: reason,
          stockTransaction: stockTransaction,
        );
        final lineCondition = item.returnCondition ?? reason;
        final rawItemLoc = (item.location ?? '').trim();
        final bool hasValidItemLoc = rawItemLoc.isNotEmpty &&
            rawItemLoc.toUpperCase() != 'LOC1' &&
            rawItemLoc.toUpperCase() != salesSite.toUpperCase();
        final lineLocation = deviceLorry.isNotEmpty
            ? deviceLorry
            : (hasValidItemLoc ? rawItemLoc : (salesSite == 'IPL' ? 'IPLCH' : 'LOC1'));

        await _insertCreditNoteLine(txn, {
          'creditNoteId': creditNoteId,
          'lineNo': lineNo,
          'quantity': item.quantity,
          'originInvoiceId': originInvoiceId,
          'originLineNo': matchedLineId,
          'standaloneSku': sku,
          'standaloneName': item.standaloneName ?? item.name,
          'standaloneSalesUnit': item.standaloneSalesUnit ?? item.salesUnit,
          'standalonePrice': item.standalonePrice ?? item.price,
          'standaloneTaxRule': item.standaloneTaxRule ?? item.taxRule,
          'standaloneLot': lot,
          'standaloneWarehouse': item.standaloneWarehouse ?? item.warehouse,
          'standaloneCce0': item.standaloneCce0 ?? item.cce0,
          'stockStatus': lineStockStatus,
          'returnCondition': lineCondition,
          'expiryDate': item.expiryDate,
          'location': lineLocation,
        });

        if (hasOriginInvoice && matchedLineId != null) {
          await txn.insert(LocalDatabaseHelper.tableSiInvoiceLineReversals, {
            'invoiceId': originInvoiceId,
            'lineId': matchedLineId,
            'reversedQty': item.quantity,
            'reversalCreditNoteId': creditNoteId,
            'createdAt': now,
          });
        }

        // Replenish stock when physical goods are returned (stockTransaction == 1)
        if (stockTransaction == 1) {
          final wh = (item.standaloneWarehouse ?? item.warehouse).isNotEmpty
              ? (item.standaloneWarehouse ?? item.warehouse)
              : salesSite;
          final resolvedLot = lot.isNotEmpty ? lot : 'RETURN';

          await _replenishLocalStock(
            txn,
            sku: sku,
            itemName: (item.standaloneName ?? item.name).toString(),
            lotNumber: resolvedLot,
            warehouse: wh,
            location: lineLocation,
            quantity: item.quantity,
            stockStatus: lineStockStatus,
            now: now,
            taxLevel: (item.standaloneTaxRule ?? item.taxRule).toString(),
            cce0: (item.standaloneCce0 ?? item.cce0).toString(),
            salesUnit: (item.standaloneSalesUnit ?? item.salesUnit).toString(),
          );
        }

        lineNo += 1000;
      }

      await _insertRefundWithShortfallTracking(
        txn,
        creditNoteId: creditNoteId,
        method: methodUpper,
        amount: refundAmount,
        bankCode: defaultBankCode,
        bankName: defaultBankName,
        createdAt: now,
        deviceId: deviceId,
        userName: createdBy,
        salesSite: salesSite,
        customerCode: customerCode,
      );

      if (hasOriginInvoice) {
        bool allFullyReversed = true;
        if (originalInvoiceLines.isNotEmpty) {
          for (final origLine in originalInvoiceLines) {
            final lId = origLine['lineId'].toString();
            final origQty = (origLine['quantity'] as num?)?.toDouble() ?? 0.0;
            final reversalRows = await txn.rawQuery(
              'SELECT COALESCE(SUM(reversedQty), 0) as total FROM ${LocalDatabaseHelper.tableSiInvoiceLineReversals} WHERE invoiceId = ? AND lineId = ?',
              [originInvoiceId, lId],
            );
            final totalReversed = (reversalRows.first['total'] as num?)?.toDouble() ?? 0.0;
            if (totalReversed < origQty) {
              allFullyReversed = false;
              break;
            }
          }
        }

        final invRows = await txn.query(
          LocalDatabaseHelper.tableSiInvoices,
          columns: ['grandTotal'],
          where: 'invoiceId = ?',
          whereArgs: [originInvoiceId],
          limit: 1,
        );
        final invGrandTotal = invRows.isNotEmpty ? (invRows.first['grandTotal'] as num?)?.toDouble() ?? 0.0 : 0.0;
        final totalCnRows = await txn.rawQuery(
          'SELECT COALESCE(SUM(grandTotal), 0) as total FROM ${LocalDatabaseHelper.tableSiCreditNotes} WHERE originalInvoiceId = ?',
          [originInvoiceId],
        );
        final totalCnAmount = (totalCnRows.first['total'] as num?)?.toDouble() ?? 0.0;
        if (invGrandTotal > 0 && totalCnAmount >= (invGrandTotal - 0.01)) {
          allFullyReversed = true;
        }

        await txn.update(
          LocalDatabaseHelper.tableSiInvoices,
          allFullyReversed
              ? {'isReversed': 1, 'isPartiallyReversed': 0, 'status': 'REVERSED'}
              : {'isPartiallyReversed': 1},
          where: 'invoiceId = ?',
          whereArgs: [originInvoiceId],
        );

        if (allFullyReversed) {
          await txn.update(
            LocalDatabaseHelper.tableSiInvoiceLines,
            {'isReversed': 1},
            where: 'invoiceId = ?',
            whereArgs: [originInvoiceId],
          );
        }
      }
    });

    return creditNote;
  }

  Future<CreditNoteModel> createAmountOnlyCreditNote({
    required String salesSite,
    required String customerCode,
    required String customerName,
    required double refundAmount,
    required List<String> linkedInvoiceIds,
    List<CreditNoteLineModel> returnedItems = const [],
    required String createdBy,
    String? deviceId,
    String? reference,
    String? reason,
    String? salesRep,
    String refundMethod = CreditNoteRefundMethod.cash,
  }) async {
    if (linkedInvoiceIds.isEmpty) {
      throw ArgumentError('Amount-only credit note requires at least 1 linked invoice.');
    }

    if (refundAmount <= 0) {
      throw ArgumentError('Refund amount must be greater than zero.');
    }

    final db = await _dbProvider();

    // Check available balance across linked invoices (supporting local invoices and synced open invoices)
    final placeholders = List.filled(linkedInvoiceIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT invoiceId, grandTotal 
      FROM ${LocalDatabaseHelper.tableSiInvoices} 
      WHERE invoiceId IN ($placeholders)
      UNION ALL
      SELECT documentNo AS invoiceId, remainingAmtLCY AS grandTotal
      FROM ${LocalDatabaseHelper.tableSiOpenInvoices}
      WHERE documentNo IN ($placeholders)
      ''',
      [...linkedInvoiceIds, ...linkedInvoiceIds],
    );

    double totalBalance = 0.0;
    final Set<String> counted = {};
    for (final r in rows) {
      final id = (r['invoiceId'] ?? '').toString();
      if (!counted.contains(id)) {
        counted.add(id);
        totalBalance += (r['grandTotal'] as num?)?.toDouble() ?? 0.0;
      }
    }

    if (refundAmount > totalBalance) {
      throw ArgumentError(
        'Refund amount ($refundAmount) exceeds linked invoice total balance ($totalBalance).',
      );
    }

    final creditNoteId = await DocumentSequenceService().generateDocumentNumber(
      docType: 'CRN',
      salesSite: salesSite,
      lorryCode: DeviceInfoService.instance.assignedLocation,
      deviceId: deviceId,
    );
    final now = DateTime.now().toIso8601String();

    final resolvedMethod = refundMethod.trim().toUpperCase() == CreditNoteRefundMethod.credit
        ? CreditNoteRefundMethod.credit
        : CreditNoteRefundMethod.cash;

    final creditNote = CreditNoteModel(
      creditNoteId: creditNoteId,
      creditNoteType: CreditNoteType.amountOnly,
      x3CreditNoteType: 'CRN',
      salesSite: salesSite,
      customerCode: customerCode,
      customerName: customerName,
      currency: 'MUR',
      grandTotal: refundAmount,
      originalInvoiceId: linkedInvoiceIds.isNotEmpty ? linkedInvoiceIds.first : null,
      linkedInvoiceIds: linkedInvoiceIds,
      settlementType: resolvedMethod,
      reference: reference ?? linkedInvoiceIds.join(','),
      isSynced: 0,
      createdAt: now,
      createdBy: createdBy,
      deviceId: deviceId,
      reason: reason,
      salesRep: salesRep,
    );

    await db.transaction((txn) async {
      await txn.insert(LocalDatabaseHelper.tableSiCreditNotes, creditNote.toMap());

      await _insertRefundWithShortfallTracking(
        txn,
        creditNoteId: creditNoteId,
        method: resolvedMethod,
        amount: refundAmount,
        createdAt: now,
        deviceId: deviceId,
        userName: createdBy,
        salesSite: salesSite,
        customerCode: customerCode,
      );

      int lineNo = 1000;
      for (final item in returnedItems) {
        final returnStatus = _resolveReturnStockStatus(
          explicitStockStatus: item.stockStatus.isNotEmpty ? item.stockStatus : null,
          reason: item.returnCondition ?? reason,
        );
        await txn.insert(LocalDatabaseHelper.tableSiCreditNoteLines, {
          'creditNoteId': creditNoteId,
          'lineNo': lineNo,
          'quantity': item.quantity,
          'originInvoiceId': item.originInvoiceId,
          'originLineNo': item.originLineNo,
          'standaloneSku': item.standaloneSku ?? item.sku,
          'standaloneName': item.standaloneName ?? item.name,
          'standaloneSalesUnit': item.standaloneSalesUnit ?? item.salesUnit,
          'standalonePrice': item.standalonePrice ?? item.price,
          'standaloneTaxRule': item.standaloneTaxRule ?? item.taxRule,
          'standaloneLot': item.standaloneLot ?? item.lot,
          'standaloneWarehouse': item.standaloneWarehouse ?? item.warehouse,
          'standaloneCce0': item.standaloneCce0 ?? item.cce0,
          'stockStatus': returnStatus,
          'returnCondition': item.returnCondition ?? reason,
          'location': item.location,
        });

        // Add back to stock
        final sku = (item.standaloneSku ?? item.sku).trim();
        final lot = (item.standaloneLot ?? item.lot).trim();
        final wh = (item.standaloneWarehouse ?? item.warehouse).trim();
        final loc = (item.location ?? '').trim();
        if (sku.isNotEmpty && lot.isNotEmpty && wh.isNotEmpty) {
          if (loc.isNotEmpty) {
            await _replenishLocalStock(
              txn,
              sku: sku,
              itemName: (item.standaloneName ?? item.name).toString(),
              lotNumber: lot,
              warehouse: wh,
              location: loc,
              quantity: item.quantity,
              stockStatus: returnStatus,
              now: now,
              taxLevel: (item.standaloneTaxRule ?? item.taxRule).toString(),
              cce0: (item.standaloneCce0 ?? item.cce0).toString(),
              salesUnit: (item.standaloneSalesUnit ?? item.salesUnit).toString(),
            );
          } else {
            await txn.rawUpdate(
              '''
              UPDATE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} 
              SET totalQty = totalQty + ? 
              WHERE itemCode = ? AND lotNumber = ? AND warehouse = ? AND stockStatus = ?
              ''',
              [item.quantity, sku, lot, wh, returnStatus],
            );
          }
        }

        lineNo += 1000;
      }
    });

    return creditNote;
  }

  /// Backward-compatible alias for createAmountOnlyCreditNote
  Future<CreditNoteModel> createCashOnlyCreditNote({
    required String salesSite,
    required String customerCode,
    required String customerName,
    required double refundAmount,
    required List<String> linkedInvoiceIds,
    List<CreditNoteLineModel> returnedItems = const [],
    required String createdBy,
    String? deviceId,
    String? reference,
    String refundMethod = CreditNoteRefundMethod.cash,
  }) => createAmountOnlyCreditNote(
    salesSite: salesSite,
    customerCode: customerCode,
    customerName: customerName,
    refundAmount: refundAmount,
    linkedInvoiceIds: linkedInvoiceIds,
    returnedItems: returnedItems,
    createdBy: createdBy,
    deviceId: deviceId,
    reference: reference,
    refundMethod: refundMethod,
  );
}
