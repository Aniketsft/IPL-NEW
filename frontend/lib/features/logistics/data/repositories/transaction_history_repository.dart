import 'package:sqflite/sqflite.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/transaction_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/eod_report_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/credit_note_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/credit_note_service.dart';
import 'package:flutter/foundation.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';
import 'package:intl/intl.dart';


class TransactionHistoryRepository {
  final LocalDatabaseHelper _dbHelper;
  final Future<Database> Function()? _dbProvider;
  final NetworkService? _networkService;

  TransactionHistoryRepository({
    LocalDatabaseHelper? dbHelper,
    Future<Database> Function()? dbProvider,
    NetworkService? networkService,
  })  : _dbHelper = dbHelper ?? LocalDatabaseHelper.instance,
        _dbProvider = dbProvider,
        _networkService = networkService;

  Future<Database> get _database async =>
      _dbProvider != null ? await _dbProvider() : await _dbHelper.database;

  Future<List<TransactionModel>> getTransactions({
    String? type,
    String? startDate,
    String? endDate,
    String? documentId,
    String? customerCode,
    String? productSku,
    int limit = 100,
    int offset = 0,
    bool isForReversal = false,
  }) async {
    final db = await _database;
    final Map<String, TransactionModel> uniqueMap = {};

    final cleanDocId = documentId?.trim();
    final cleanCustCode = customerCode?.trim();
    final cleanSku = productSku?.trim();

    // 1. Fetch Invoices
    if (type == null || type.isEmpty || type == 'ALL' || type == 'INVOICE' || type == 'RETURN') {
      String whereClause = '1 = 1';
      List<dynamic> whereArgs = [];

      if (isForReversal) {
        whereClause += ' AND (isReversed = 0 OR isReversed IS NULL)';
      }

      if (type != null && type.isNotEmpty && type != 'ALL') {
        whereClause += ' AND transactionType = ?';
        whereArgs.add(type);
      }

      if (startDate != null && startDate.isNotEmpty) {
        whereClause += ' AND createdAt >= ?';
        whereArgs.add(startDate);
      }

      if (endDate != null && endDate.isNotEmpty) {
        whereClause += ' AND createdAt <= ?';
        whereArgs.add(endDate);
      }

      if (cleanDocId != null && cleanDocId.isNotEmpty) {
        whereClause += ' AND invoiceId LIKE ?';
        whereArgs.add('%$cleanDocId%');
      }

      if (cleanCustCode != null && cleanCustCode.isNotEmpty) {
        whereClause += ' AND customerCode = ?';
        whereArgs.add(cleanCustCode);
      }

      if (cleanSku != null && cleanSku.isNotEmpty) {
        whereClause += ' AND invoiceId IN (SELECT invoiceId FROM ${LocalDatabaseHelper.tableSiInvoiceLines} WHERE sku = ?)';
        whereArgs.add(cleanSku);
      }

      final List<Map<String, dynamic>> maps = await db.query(
        LocalDatabaseHelper.tableSiInvoices,
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'createdAt DESC',
        limit: limit,
        offset: offset,
      );

      for (final m in maps) {
        final Map<String, dynamic> mutableMap = Map<String, dynamic>.from(m);
        final invId = mutableMap['invoiceId']?.toString() ?? '';
        final invTotal = (mutableMap['grandTotal'] as num?)?.toDouble() ?? 0.0;

        // Check if there are linked credit notes for this invoice
        final cnRows = await db.rawQuery(
          'SELECT creditNoteId, grandTotal FROM ${LocalDatabaseHelper.tableSiCreditNotes} WHERE originalInvoiceId = ? ORDER BY createdAt DESC',
          [invId],
        );

        if (cnRows.isNotEmpty) {
          final totalReversedAmt = cnRows.fold<double>(
            0.0,
            (sum, row) => sum + ((row['grandTotal'] as num?)?.toDouble() ?? 0.0),
          );
          mutableMap['reversalCreditNoteId'] = cnRows.first['creditNoteId'];
          mutableMap['remainingAmount'] = (invTotal - totalReversedAmt).clamp(0.0, invTotal);

          // If fully covered by credit notes, ensure marked reversed in model
          if (totalReversedAmt >= (invTotal - 0.01)) {
            mutableMap['isReversed'] = 1;
            mutableMap['isPartiallyReversed'] = 0;
          } else if (totalReversedAmt > 0) {
            mutableMap['isPartiallyReversed'] = 1;
          }
        } else {
          mutableMap['remainingAmount'] = invTotal;
        }

        // If isForReversal is true and invoice is computed as fully reversed, skip it
        if (isForReversal && (mutableMap['isReversed'] == 1)) {
          continue;
        }

        final tx = TransactionModel.fromJson(mutableMap);
        uniqueMap[tx.id] = tx;
      }
    }

    // 2. Fetch Dedicated Credit Notes
    if (type == null || type.isEmpty || type == 'ALL' || type == 'CREDIT_NOTE') {
      String cnWhere = '1 = 1';
      List<dynamic> cnArgs = [];

      if (startDate != null && startDate.isNotEmpty) {
        cnWhere += ' AND createdAt >= ?';
        cnArgs.add(startDate);
      }

      if (endDate != null && endDate.isNotEmpty) {
        cnWhere += ' AND createdAt <= ?';
        cnArgs.add(endDate);
      }

      if (cleanDocId != null && cleanDocId.isNotEmpty) {
        cnWhere += ' AND creditNoteId LIKE ?';
        cnArgs.add('%$cleanDocId%');
      }

      if (cleanCustCode != null && cleanCustCode.isNotEmpty) {
        cnWhere += ' AND customerCode = ?';
        cnArgs.add(cleanCustCode);
      }

      if (cleanSku != null && cleanSku.isNotEmpty) {
        cnWhere += ''' AND creditNoteId IN (
          SELECT cnl.creditNoteId 
          FROM ${LocalDatabaseHelper.tableSiCreditNoteLines} cnl
          LEFT JOIN ${LocalDatabaseHelper.tableSiInvoiceLines} il 
            ON cnl.originInvoiceId = il.invoiceId AND cnl.originLineNo = il.lineId
          WHERE cnl.standaloneSku = ? OR il.sku = ?
        )''';
        cnArgs.add(cleanSku);
        cnArgs.add(cleanSku);
      }

      final List<Map<String, dynamic>> cnMaps = await db.query(
        LocalDatabaseHelper.tableSiCreditNotes,
        where: cnWhere,
        whereArgs: cnArgs,
        orderBy: 'createdAt DESC',
        limit: limit,
        offset: offset,
      );

      for (final cn in cnMaps) {
        final id = cn['creditNoteId'] as String;
        uniqueMap[id] = TransactionModel(
          id: id,
          type: 'CREDIT_NOTE',
          customerCode: (cn['customerCode'] as String?) ?? '',
          customerName: (cn['customerName'] as String?) ?? '',
          grandTotal: (cn['grandTotal'] as num?)?.toDouble() ?? 0.0,
          createdAt: (cn['createdAt'] as String?) ?? '',
          status: 'CONFIRMED',
          isSynced: (cn['isSynced'] as int?) ?? 0,
          isReversed: 0,
          auditMetadata: AuditMetadata(
            createdByUserName: cn['createdBy'] as String?,
            deviceId: cn['deviceId'] as String?,
          ),
        );
      }
    }

    final results = uniqueMap.values.toList();
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (results.length > limit) {
      return results.sublist(0, limit);
    }
    return results;
  }

  /// Returns distinct customers that have at least one invoice or credit note
  Future<List<Map<String, String>>> getCustomersWithTransactions() async {
    final db = await _database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT DISTINCT customerCode, customerName FROM (
        SELECT customerCode, customerName FROM ${LocalDatabaseHelper.tableSiInvoices}
        WHERE customerCode IS NOT NULL AND customerCode != ''
        UNION
        SELECT customerCode, customerName FROM ${LocalDatabaseHelper.tableSiCreditNotes}
        WHERE customerCode IS NOT NULL AND customerCode != ''
      )
      ORDER BY customerName COLLATE NOCASE ASC
    ''');
    return maps.map((m) => {
      'code': (m['customerCode'] ?? '').toString(),
      'name': (m['customerName'] ?? '').toString(),
    }).toList();
  }

  /// Returns distinct products that have actually been sold/transacted to [customerCode]
  Future<List<Map<String, String>>> getProductsSoldToCustomer(String customerCode) async {
    if (customerCode.trim().isEmpty) return [];
    final db = await _database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT DISTINCT sku, name FROM (
        SELECT il.sku, il.name
        FROM ${LocalDatabaseHelper.tableSiInvoiceLines} il
        JOIN ${LocalDatabaseHelper.tableSiInvoices} i ON il.invoiceId = i.invoiceId
        WHERE i.customerCode = ?
        UNION
        SELECT 
          COALESCE(cnl.standaloneSku, il2.sku) AS sku,
          COALESCE(cnl.standaloneName, il2.name) AS name
        FROM ${LocalDatabaseHelper.tableSiCreditNoteLines} cnl
        JOIN ${LocalDatabaseHelper.tableSiCreditNotes} cn ON cnl.creditNoteId = cn.creditNoteId
        LEFT JOIN ${LocalDatabaseHelper.tableSiInvoiceLines} il2 
          ON cnl.originInvoiceId = il2.invoiceId AND cnl.originLineNo = il2.lineId
        WHERE cn.customerCode = ?
      )
      WHERE sku IS NOT NULL AND sku != ''
      ORDER BY name COLLATE NOCASE ASC
    ''', [customerCode.trim(), customerCode.trim()]);

    return maps.map((m) => {
      'sku': (m['sku'] ?? '').toString(),
      'name': (m['name'] ?? '').toString(),
    }).toList();
  }

  // Method to get distinct transaction types, if needed
  Future<List<String>> getTransactionTypes() async {
    final db = await _database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT DISTINCT transactionType FROM ${LocalDatabaseHelper.tableSiInvoices} WHERE transactionType IS NOT NULL',
    );
    return maps.map((e) => e['transactionType'] as String).toList();
  }

  Future<List<Map<String, dynamic>>> getTransactionLines(String invoiceId) async {
    final db = await _database;
    if (invoiceId.startsWith('CN-')) {
      final query = '''
        SELECT 
          cnl.lineId,
          cnl.creditNoteId,
          cnl.lineNo,
          cnl.quantity,
          COALESCE(cnl.standaloneSku, il.sku) AS sku,
          COALESCE(cnl.standaloneName, il.name) AS name,
          COALESCE(cnl.standaloneSalesUnit, il.salesUnit, 'EA') AS salesUnit,
          COALESCE(cnl.standalonePrice, il.basePrice, 0.0) AS basePrice,
          COALESCE(cnl.standaloneTaxRule, il.taxRule, '') AS taxRule,
          COALESCE(cnl.standaloneLot, il.lotNumber, '') AS lotNumber,
          COALESCE(cnl.standaloneWarehouse, il.warehouse, '') AS warehouse,
          COALESCE(cnl.standaloneCce0, il.cce0, '') AS cce0
        FROM ${LocalDatabaseHelper.tableSiCreditNoteLines} cnl
        LEFT JOIN ${LocalDatabaseHelper.tableSiInvoiceLines} il
          ON cnl.originInvoiceId = il.invoiceId AND cnl.originLineNo = il.lineId
        WHERE cnl.creditNoteId = ?
        ORDER BY cnl.lineNo ASC
      ''';
      final cnLines = await db.rawQuery(query, [invoiceId]);
      if (cnLines.isNotEmpty) return cnLines;
    }
    final lines = await db.rawQuery('''
      SELECT
        il.*,
        COALESCE(SUM(rev.reversedQty), 0.0) AS reversedQty
      FROM ${LocalDatabaseHelper.tableSiInvoiceLines} il
      LEFT JOIN ${LocalDatabaseHelper.tableSiInvoiceLineReversals} rev
        ON CAST(rev.lineId AS INTEGER) = il.lineId AND rev.invoiceId = il.invoiceId
      WHERE il.invoiceId = ?
      GROUP BY il.lineId
    ''', [invoiceId]);
    if (lines.isEmpty) {
      final query = '''
        SELECT 
          cnl.lineId,
          cnl.creditNoteId,
          cnl.lineNo,
          cnl.quantity,
          0.0 AS reversedQty,
          COALESCE(cnl.standaloneSku, il.sku) AS sku,
          COALESCE(cnl.standaloneName, il.name) AS name,
          COALESCE(cnl.standaloneSalesUnit, il.salesUnit, 'EA') AS salesUnit,
          COALESCE(cnl.standalonePrice, il.basePrice, 0.0) AS basePrice,
          COALESCE(cnl.standaloneTaxRule, il.taxRule, '') AS taxRule,
          COALESCE(cnl.standaloneLot, il.lotNumber, '') AS lotNumber,
          COALESCE(cnl.standaloneWarehouse, il.warehouse, '') AS warehouse,
          COALESCE(cnl.standaloneCce0, il.cce0, '') AS cce0
        FROM ${LocalDatabaseHelper.tableSiCreditNoteLines} cnl
        LEFT JOIN ${LocalDatabaseHelper.tableSiInvoiceLines} il
          ON cnl.originInvoiceId = il.invoiceId AND cnl.originLineNo = il.lineId
        WHERE cnl.creditNoteId = ?
        ORDER BY cnl.lineNo ASC
      ''';
      final cnLines = await db.rawQuery(query, [invoiceId]);
      if (cnLines.isNotEmpty) return cnLines;
    }
    if (lines.isEmpty) {
      final x3Lines = await getX3TransactionLines(invoiceId);
      if (x3Lines.isNotEmpty) return x3Lines;
    }
    return lines;
  }

  Future<List<TransactionModel>> getX3HistoryTransactions({
    required String customerCode,
    String? type,
    String? startDate,
    String? endDate,
    String? searchQuery,
    String? siteCode,
    bool forceRefresh = false,
  }) async {
    // 1. Check local SQLite first for instant 0ms offline presentation
    final localRows = await _dbHelper.getX3HistoryHeaders(
      customerCode: customerCode,
      type: type,
      searchQuery: searchQuery,
      startDate: startDate,
      endDate: endDate,
    );

    // If local records already exist and forceRefresh is false, return immediately
    if (localRows.isNotEmpty && !forceRefresh) {
      return _mapX3RowsToTransactions(localRows, customerCode);
    }

    // 2. Try remote fetch if networkService is available (when local is empty or refresh forced)
    if (_networkService != null) {
      try {
        final queryParams = <String, dynamic>{
          'customercode': customerCode.trim(),
          'months': 6,
        };
        if (siteCode != null && siteCode.isNotEmpty && siteCode != 'ALL') {
          queryParams['sitecode'] = siteCode.trim();
        }

        final response = await _networkService.dio.get(
          'SalesInvoice/x3-history',
          queryParameters: queryParams,
        );

        if (response.statusCode == 200 && response.data is List) {
          await _dbHelper.saveX3HistoryDocuments(response.data as List<dynamic>);
        }
      } catch (e) {
        debugPrint('getX3HistoryTransactions: Remote sync failed: $e (Falling back to local SQLite)');
      }
    }

    // 3. Query from local SQLite again to include newly downloaded records
    final rows = await _dbHelper.getX3HistoryHeaders(
      customerCode: customerCode,
      type: type,
      searchQuery: searchQuery,
      startDate: startDate,
      endDate: endDate,
    );

    return _mapX3RowsToTransactions(rows, customerCode);
  }

  List<TransactionModel> _mapX3RowsToTransactions(List<Map<String, dynamic>> rows, String customerCode) {
    return rows.map((r) {
      final flag = (r['invoiceTypeFlag'] as num?)?.toInt() ?? 1;
      final docType = flag == 2 ? 'CREDIT_NOTE' : 'INVOICE';
      final total = (r['totalAmountIncTax'] as num?)?.toDouble() ?? 0.0;
      final invNum = r['invoiceNumber']?.toString() ?? '';
      final docDate = r['invoiceDate']?.toString() ?? '';
      final cust = (r['customerCode'] != null && (r['customerCode'] as String).isNotEmpty)
          ? r['customerCode'].toString()
          : (r['billToCustomer']?.toString() ?? customerCode);
      final custName = (r['customerName'] != null && (r['customerName'] as String).isNotEmpty)
          ? r['customerName'].toString()
          : cust;
      final user = r['creationUser']?.toString() ?? 'X3';

      return TransactionModel(
        id: invNum,
        type: docType,
        customerCode: cust,
        customerName: custName,
        grandTotal: total,
        createdAt: docDate,
        status: 'POSTED',
        isSynced: 1,
        isReversed: 0,
        isPartiallyReversed: 0,
        auditMetadata: AuditMetadata(
          createdByUserName: user,
        ),
      );
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getX3TransactionLines(String invoiceNumber) async {
    final rows = await _dbHelper.getX3HistoryLines(invoiceNumber);
    return rows.map((line) {
      final qty = (line['quantity'] as num?)?.toDouble() ?? 0.0;
      final netPrice = (line['netPrice'] as num?)?.toDouble() ?? 0.0;
      final grossPrice = (line['grossPrice'] as num?)?.toDouble() ?? 0.0;
      final amtNot = (line['lineAmountNotTax'] as num?)?.toDouble() ?? 0.0;
      final amtInc = (line['lineAmountIncTax'] as num?)?.toDouble() ?? 0.0;

      // Exact invoiced net price per unit paid by customer:
      final unitNetPrice = netPrice > 0.0001
          ? netPrice
          : ((amtNot > 0.0001 && qty > 0.0001)
              ? (amtNot / qty)
              : ((amtInc > 0.0001 && qty > 0.0001) ? (amtInc / qty) : grossPrice));

      // Calculate effective VAT percentage from historical line amounts
      final effectiveVatRate = (amtNot > 0.001 && amtInc > amtNot)
          ? (((amtInc - amtNot) / amtNot) * 100).roundToDouble()
          : 0.0;

      return {
        'lineId': line['lineNumber']?.toString() ?? '0',
        'id': line['lineNumber']?.toString() ?? '0',
        'lineNumber': (line['lineNumber'] as num?)?.toInt() ?? 0,
        'sku': line['productCode'] ?? '',
        'name': line['productDescription'] ?? '',
        'quantity': qty,
        'salesUnit': line['salesUOM'] ?? 'EA',
        'basePrice': unitNetPrice,
        'grossPrice': grossPrice,
        // Net price is already net of discounts; do not double-deduct flat discount
        'discountAmountFlat': 0.0,
        'discountPercent': 0.0,
        'total': amtInc > 0 ? amtInc : (amtNot > 0 ? amtNot : unitNetPrice * qty),
        'taxRule': effectiveVatRate > 0.1 ? 'VAT15' : 'ZERO',
        'vatRatePercent': effectiveVatRate,
        'pricingSource': 'X3_HISTORIC',
        'priceListCode': 'X3_INVOICE',
        'lotNumber': '',
        'warehouse': '',
        'lineAmountNotTax': amtNot,
        'lineAmountIncTax': amtInc,
      };
    }).toList();
  }

  Future<CreditNoteModel> cancelInvoice(
    TransactionModel transaction, {
    String? reason,
    String? salesRep,
  }) async {
    final creditNoteService = CreditNoteService(dbProvider: () => _database);
    return await creditNoteService.createReversalCreditNote(
      invoiceId: transaction.id,
      createdBy: transaction.auditMetadata.createdByUserName ?? 'SYSTEM',
      reason: reason,
      salesRep: salesRep,
      deviceId: transaction.auditMetadata.deviceId,
    );
  }

  /// Returns a map of lineId → totalReversedQty for all already-reversed lines of [invoiceId].
  Future<Map<String, double>> getReversedLineIds(String invoiceId) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT lineId, COALESCE(SUM(reversedQty), 0) as total FROM ${LocalDatabaseHelper.tableSiInvoiceLineReversals} WHERE invoiceId = ? GROUP BY lineId',
      [invoiceId],
    );
    return {for (final r in rows) r['lineId'] as String: (r['total'] as num).toDouble()};
  }

  /// Partially reverses [selectedLines] on [transaction], creating a partial Credit Note.
  Future<CreditNoteModel> partialReverseInvoice(
    TransactionModel transaction,
    List<Map<String, dynamic>> selectedLines, {
    String? reason,
    String? salesRep,
  }) async {
    final creditNoteService = CreditNoteService(dbProvider: () => _database);
    return await creditNoteService.createPartialReversalCreditNote(
      invoiceId: transaction.id,
      selectedLines: selectedLines,
      createdBy: transaction.auditMetadata.createdByUserName ?? 'SYSTEM',
      reason: reason,
      salesRep: salesRep,
      deviceId: transaction.auditMetadata.deviceId,
    );
  }

  /// Aggregates all End-of-Day data for the given [date] from local SQLite.
  /// Queries verified against confirmed DB schema including tbl_si_open_invoice_payments.
  Future<EodReportModel> getEodReportData(DateTime date) async {
    final db = await _dbHelper.database;
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final startDate = '${dateStr}T00:00:00';
    final endDate = '${dateStr}T23:59:59';

    // ── 1. Valid Sales Totals ─────────────────────────────────────────────────
    // Only count fully clean invoices: isReversed = 0 AND isPartiallyReversed = 0
    final salesRows = await db.rawQuery('''
      SELECT COUNT(*) as cnt,
             COALESCE(SUM(grandTotal), 0) as grossTotal,
             COALESCE(SUM(totalVat), 0) as vatTotal,
             COALESCE(SUM(totalDiscount), 0) as discountTotal,
             createdByUserName,
             deviceId
      FROM ${LocalDatabaseHelper.tableSiInvoices}
      WHERE transactionType = 'INVOICE'
        AND isReversed = 0
        AND COALESCE(isPartiallyReversed, 0) = 0
        AND createdAt >= ? AND createdAt <= ?
    ''', [startDate, endDate]);

    final int salesCount = (salesRows.first['cnt'] as int?) ?? 0;
    final double salesGross = (salesRows.first['grossTotal'] as num?)?.toDouble() ?? 0.0;
    final double totalVat = (salesRows.first['vatTotal'] as num?)?.toDouble() ?? 0.0;
    final double totalDiscount = (salesRows.first['discountTotal'] as num?)?.toDouble() ?? 0.0;
    final String operatorName = (salesRows.first['createdByUserName'] as String?) ?? 'N/A';
    final String registerId = (salesRows.first['deviceId'] as String?) ?? 'REG-01';

    // ── 2. Credit Notes / Returns ─────────────────────────────────────────────
    final returnsRows = await db.rawQuery('''
      SELECT COUNT(*) as cnt,
             COALESCE(SUM(grandTotal), 0) as grossTotal
      FROM ${LocalDatabaseHelper.tableSiInvoices}
      WHERE transactionType = 'CREDIT_NOTE'
        AND createdAt >= ? AND createdAt <= ?
    ''', [startDate, endDate]);

    final int returnsCount = (returnsRows.first['cnt'] as int?) ?? 0;
    final double returnsGross = (returnsRows.first['grossTotal'] as num?)?.toDouble() ?? 0.0;

    // ── 3. Cancelled (Fully Reversed & Partially Reversed) Receipts ───────────
    final cancelledRows = await db.rawQuery('''
      SELECT invoiceId, customerName,
             grandTotal,
             COALESCE(grandTotal - totalVat, 0) as net
      FROM ${LocalDatabaseHelper.tableSiInvoices}
      WHERE isReversed = 1
        AND createdAt >= ? AND createdAt <= ?
      ORDER BY createdAt DESC
    ''', [startDate, endDate]);

    final cancelledReceipts = cancelledRows.map((row) {
      final id = (row['invoiceId'] as String?) ?? '';
      final shortId = id.length > 8 ? id.substring(id.length - 8) : id;
      return EodCancelledReceipt(
        invoiceId: shortId,
        reason: (row['customerName'] as String?) ?? 'Return',
        net: (row['net'] as num?)?.toDouble() ?? 0.0,
        gross: (row['grandTotal'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();

    // ── 4. Itemized Invoices & Classification (Cash Invoices vs Credit Invoices)
    final invoiceRows = await db.rawQuery('''
      SELECT invoiceId, customerCode, customerName, grandTotal, totalVat,
             paymentTerm, status, createdAt
      FROM ${LocalDatabaseHelper.tableSiInvoices}
      WHERE transactionType = 'INVOICE'
        AND isReversed = 0
        AND createdAt >= ? AND createdAt <= ?
      ORDER BY createdAt ASC
    ''', [startDate, endDate]);

    final List<EodInvoiceItem> cashInvoices = [];
    final List<EodInvoiceItem> creditInvoices = [];
    final List<EodChequeDetail> chequeList = [];

    for (final inv in invoiceRows) {
      final invId = (inv['invoiceId'] as String?) ?? '';
      final custCode = (inv['customerCode'] as String?) ?? '';
      final custName = (inv['customerName'] as String?) ?? '';
      final grandTotal = (inv['grandTotal'] as num?)?.toDouble() ?? 0.0;
      final paymentTerm = (inv['paymentTerm'] as String?) ?? 'CSH';
      final status = (inv['status'] as String?) ?? 'PAID';
      final createdAt = (inv['createdAt'] as String?) ?? '';

      // Query payments associated with this invoice
      final paymentRows = await db.rawQuery('''
        SELECT method, amount, bankCode, bankName, chequeNumber, chequeDate, qrTransactionRef
        FROM ${LocalDatabaseHelper.tableSiPayments}
        WHERE invoiceId = ?
      ''', [invId]);

      double cashAmt = 0.0;
      double chequeAmt = 0.0;
      double digitalAmt = 0.0;
      double creditAmt = 0.0;
      final List<String> methodsUsed = [];

      for (final p in paymentRows) {
        final m = ((p['method'] as String?) ?? '').toUpperCase();
        final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;

        if (m == 'CASH') {
          cashAmt += amt;
          if (!methodsUsed.contains('CASH')) methodsUsed.add('CASH');
        } else if (m == 'CHEQUE') {
          chequeAmt += amt;
          final chqNo = (p['chequeNumber'] as String?) ?? '';
          final bank = (p['bankName'] as String?) ?? (p['bankCode'] as String?) ?? 'BANK';
          final label = chqNo.isNotEmpty ? 'CHQ #$chqNo ($bank)' : 'CHEQUE ($bank)';
          methodsUsed.add(label);

          chequeList.add(EodChequeDetail(
            chequeNumber: chqNo,
            bankName: bank,
            customerName: custName,
            source: 'INV: ${invId.length > 8 ? invId.substring(invId.length - 8) : invId}',
            amount: amt,
            date: (p['chequeDate'] as String?) ?? '',
          ));
        } else if (['JUICE', 'BLINK', 'MYT MONEY', 'CARD', 'BANK_TRANSFER', 'ONLINE'].contains(m)) {
          digitalAmt += amt;
          final ref = (p['qrTransactionRef'] as String?) ?? '';
          methodsUsed.add(ref.isNotEmpty ? '$m ($ref)' : m);
        } else if (m == 'CREDIT') {
          creditAmt += amt;
          if (!methodsUsed.contains('CREDIT')) methodsUsed.add('CREDIT');
        } else {
          methodsUsed.add(m);
        }
      }

      final isCredit = (creditAmt > 0) ||
          status.toUpperCase() == 'CREDIT' ||
          (paymentTerm.isNotEmpty &&
              paymentTerm.toUpperCase() != 'CSH' &&
              paymentTerm.toUpperCase() != 'CASH' &&
              (cashAmt + chequeAmt + digitalAmt) < grandTotal - 0.01);

      final summaryMethod = methodsUsed.isNotEmpty
          ? methodsUsed.join(' + ')
          : (isCredit ? 'CREDIT' : 'CASH');

      final item = EodInvoiceItem(
        invoiceId: invId,
        customerCode: custCode,
        customerName: custName,
        grandTotal: grandTotal,
        paymentTerm: paymentTerm,
        tenderSummary: summaryMethod,
        cashAmount: cashAmt,
        chequeAmount: chequeAmt,
        digitalAmount: digitalAmt,
        creditAmount: isCredit ? (creditAmt > 0 ? creditAmt : grandTotal) : 0.0,
        createdAt: createdAt,
        isCredit: isCredit,
      );

      if (isCredit) {
        creditInvoices.add(item);
      } else {
        cashInvoices.add(item);
      }
    }

    // ── 5. Open Invoices Collections (AR Debt Recovery) ───────────────────────
    final openCollRows = await db.rawQuery('''
      SELECT P.paymentId, P.documentNo, P.customerNo,
             COALESCE(C.name, P.customerNo) as customerName,
             P.amount, P.paymentMethod, P.bankCode, P.bankName,
             P.chequeNumber, P.chequeDate, P.qrTransactionRef,
             P.createdAt, P.isSynced
      FROM ${LocalDatabaseHelper.tableSiOpenInvoicePayments} P
      LEFT JOIN ${LocalDatabaseHelper.tableSalesInvoiceCustomers} C ON P.customerNo = C.code
      WHERE P.createdAt >= ? AND P.createdAt <= ?
      ORDER BY P.createdAt ASC
    ''', [startDate, endDate]);

    final List<EodOpenInvoiceCollectionItem> openInvoiceCollections = [];
    for (final row in openCollRows) {
      final amt = (row['amount'] as num?)?.toDouble() ?? 0.0;
      final method = ((row['paymentMethod'] as String?) ?? 'CASH').toUpperCase();
      final chqNo = (row['chequeNumber'] as String?) ?? '';
      final bank = (row['bankName'] as String?) ?? (row['bankCode'] as String?) ?? '';
      final cust = (row['customerName'] as String?) ?? (row['customerNo'] as String?) ?? '';
      final doc = (row['documentNo'] as String?) ?? '';

      if (method == 'CHEQUE') {
        chequeList.add(EodChequeDetail(
          chequeNumber: chqNo,
          bankName: bank.isNotEmpty ? bank : 'BANK',
          customerName: cust,
          source: 'OPEN: $doc',
          amount: amt,
          date: (row['chequeDate'] as String?) ?? '',
        ));
      }

      openInvoiceCollections.add(EodOpenInvoiceCollectionItem(
        paymentId: (row['paymentId'] as String?) ?? '',
        documentNo: doc,
        customerNo: (row['customerNo'] as String?) ?? '',
        customerName: cust,
        amount: amt,
        paymentMethod: method,
        bankCode: (row['bankCode'] as String?) ?? '',
        bankName: bank,
        chequeNumber: chqNo,
        chequeDate: (row['chequeDate'] as String?) ?? '',
        qrTransactionRef: (row['qrTransactionRef'] as String?) ?? '',
        createdAt: (row['createdAt'] as String?) ?? '',
        isSynced: ((row['isSynced'] as int?) ?? 0) == 1,
      ));
    }

    // ── 6. Cash Refunded on Returns / Credit Notes ────────────────────────────
    final refundRows = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as totalCashRefund
      FROM ${LocalDatabaseHelper.tableSiCreditNoteRefunds}
      WHERE UPPER(method) = 'CASH'
        AND createdAt >= ? AND createdAt <= ?
    ''', [startDate, endDate]);
    final double cashRefunded = (refundRows.first['totalCashRefund'] as num?)?.toDouble() ?? 0.0;

    // ── 7. Overall Payment Method Summary (Invoices + Open Collections) ────────
    final paymentRows = await db.rawQuery('''
      SELECT P.method, COALESCE(SUM(P.amount), 0) as total
      FROM ${LocalDatabaseHelper.tableSiPayments} P
      INNER JOIN ${LocalDatabaseHelper.tableSiInvoices} I ON P.invoiceId = I.invoiceId
      WHERE I.transactionType = 'INVOICE'
        AND I.isReversed = 0
        AND I.createdAt >= ? AND I.createdAt <= ?
      GROUP BY P.method
      ORDER BY total DESC
    ''', [startDate, endDate]);

    final Map<String, double> combinedPaymentMap = {};
    for (final r in paymentRows) {
      final m = ((r['method'] as String?) ?? 'OTHER').toUpperCase();
      final a = (r['total'] as num?)?.toDouble() ?? 0.0;
      combinedPaymentMap[m] = (combinedPaymentMap[m] ?? 0.0) + a;
    }
    // Also include open invoice payments into combined payment breakdown
    for (final c in openInvoiceCollections) {
      final m = c.paymentMethod.toUpperCase();
      combinedPaymentMap[m] = (combinedPaymentMap[m] ?? 0.0) + c.amount;
    }

    final paymentSummaries = combinedPaymentMap.entries
        .map((e) => EodPaymentSummary(method: e.key, amount: e.value))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    // ── 8. VAT Breakdown per tax rate ─────────────────────────────────────────
    final vatRows = await db.rawQuery('''
      SELECT L.taxRule,
             COALESCE(TR.taxRatePercent, 0) as taxRatePercent,
             COALESCE(SUM(CASE WHEN L.isFoc = 0 THEN L.total ELSE 0 END), 0) as net,
             COALESCE(SUM(CASE WHEN L.isFoc = 0 THEN L.vatAmount ELSE 0 END), 0) as tax
      FROM ${LocalDatabaseHelper.tableSiInvoiceLines} L
      INNER JOIN ${LocalDatabaseHelper.tableSiInvoices} I ON L.invoiceId = I.invoiceId
      LEFT JOIN ${LocalDatabaseHelper.tableTaxRates} TR ON L.taxRule = TR.taxCode
      WHERE I.transactionType = 'INVOICE'
        AND I.isReversed = 0
        AND I.createdAt >= ? AND I.createdAt <= ?
      GROUP BY L.taxRule, TR.taxRatePercent
      ORDER BY TR.taxRatePercent ASC
    ''', [startDate, endDate]);

    final vatSummaries = vatRows.map((row) => EodVatSummary(
          taxCode: (row['taxRule'] as String?) ?? '0%',
          taxRatePercent: (row['taxRatePercent'] as num?)?.toDouble() ?? 0.0,
          net: (row['net'] as num?)?.toDouble() ?? 0.0,
          tax: (row['tax'] as num?)?.toDouble() ?? 0.0,
        )).toList();

    // ── 9. Cash Balance Model ─────────────────────────────────────────────────
    final totalCashInHand = cashInvoices.fold(0.0, (s, i) => s + i.cashAmount) +
        openInvoiceCollections
            .where((c) => c.paymentMethod == 'CASH')
            .fold(0.0, (s, c) => s + c.amount) -
        cashRefunded;

    final cashBalance = EodCashBalance(
      cashGrossSales: totalCashInHand.clamp(0.0, double.infinity),
      withdrawals: cashRefunded,
    );

    return EodReportModel(
      reportDate: DateFormat('dd.MM.yyyy').format(date),
      reportTime: DateFormat('HH:mm').format(DateTime.now()),
      operatorName: operatorName,
      registerId: registerId,
      salesCount: salesCount,
      salesGross: salesGross,
      totalVat: totalVat,
      totalDiscount: totalDiscount,
      returnsCount: returnsCount,
      returnsGross: returnsGross,
      cancelledReceipts: cancelledReceipts,
      cashBalance: cashBalance,
      vatSummaries: vatSummaries,
      paymentSummaries: paymentSummaries,
      cashInvoices: cashInvoices,
      creditInvoices: creditInvoices,
      openInvoiceCollections: openInvoiceCollections,
      chequeList: chequeList,
      cashRefundedOnReturns: cashRefunded,
    );
  }
}
