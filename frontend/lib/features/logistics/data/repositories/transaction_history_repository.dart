import 'package:sqflite/sqflite.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/transaction_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/eod_report_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/credit_note_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/credit_note_service.dart';
import 'package:intl/intl.dart';


class TransactionHistoryRepository {
  final LocalDatabaseHelper _dbHelper;
  final Future<Database> Function()? _dbProvider;

  TransactionHistoryRepository({
    LocalDatabaseHelper? dbHelper,
    Future<Database> Function()? dbProvider,
  })  : _dbHelper = dbHelper ?? LocalDatabaseHelper.instance,
        _dbProvider = dbProvider;

  Future<Database> get _database async =>
      _dbProvider != null ? await _dbProvider!() : await _dbHelper.database;

  Future<List<TransactionModel>> getTransactions({
    String? type,
    String? startDate,
    String? endDate,
    String? documentId,
    String? customerCode,
    String? productSku,
    int limit = 100,
    int offset = 0,
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
        final tx = TransactionModel.fromJson(m);
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
    return lines;
  }

  Future<CreditNoteModel> cancelInvoice(TransactionModel transaction) async {
    final creditNoteService = CreditNoteService(dbProvider: () => _database);
    return await creditNoteService.createReversalCreditNote(
      invoiceId: transaction.id,
      createdBy: transaction.auditMetadata.createdByUserName ?? 'SYSTEM',
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
    List<Map<String, dynamic>> selectedLines,
  ) async {
    final creditNoteService = CreditNoteService(dbProvider: () => _database);
    return await creditNoteService.createPartialReversalCreditNote(
      invoiceId: transaction.id,
      selectedLines: selectedLines,
      createdBy: transaction.auditMetadata.createdByUserName ?? 'SYSTEM',
      deviceId: transaction.auditMetadata.deviceId,
    );
  }

  /// Aggregates all End-of-Day data for the given [date] from local SQLite.
  /// All 6 SQL queries verified against the confirmed DB schema.
  Future<EodReportModel> getEodReportData(DateTime date) async {
    final db = await _dbHelper.database;
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final startDate = '${dateStr}T00:00:00';
    final endDate = '${dateStr}T23:59:59';

    // ── 1. Valid Sales ────────────────────────────────────────────────────────
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

    // ── 3. Cancelled (Fully Reversed) Receipts ─────────────────────────────────
    final cancelledRows = await db.rawQuery('''
      SELECT invoiceId, customerName,
             grandTotal,
             COALESCE(grandTotal - totalVat, 0) as net
      FROM ${LocalDatabaseHelper.tableSiInvoices}
      WHERE isReversed = 1
        AND createdAt >= ? AND createdAt <= ?
      ORDER BY createdAt DESC
    ''', [startDate, endDate]);

    // Partially reversed invoices also appear in the cancelled section with a note
    final partialRows = await db.rawQuery('''
      SELECT I.invoiceId, I.customerName, I.grandTotal,
             COALESCE(SUM(R.reversedQty * L.basePrice), 0) as reversedAmount
      FROM ${LocalDatabaseHelper.tableSiInvoices} I
      LEFT JOIN ${LocalDatabaseHelper.tableSiInvoiceLineReversals} R ON R.invoiceId = I.invoiceId
      LEFT JOIN ${LocalDatabaseHelper.tableSiInvoiceLines} L ON L.lineId = CAST(R.lineId AS INTEGER) AND L.invoiceId = I.invoiceId
      WHERE COALESCE(I.isPartiallyReversed, 0) = 1
        AND I.isReversed = 0
        AND I.createdAt >= ? AND I.createdAt <= ?
      GROUP BY I.invoiceId
      ORDER BY I.createdAt DESC
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

    // ── 4. Payment Method Summary ─────────────────────────────────────────────
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

    final paymentSummaries = paymentRows.map((row) => EodPaymentSummary(
          method: (row['method'] as String?) ?? 'OTHER',
          amount: (row['total'] as num?)?.toDouble() ?? 0.0,
        )).toList();

    // ── 5. VAT Breakdown per tax rate ─────────────────────────────────────────
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

    // ── 6. Cash Balance ───────────────────────────────────────────────────────
    final cashTotal = paymentSummaries
        .where((p) => p.method.toUpperCase() == 'CASH')
        .fold(0.0, (sum, p) => sum + p.amount);

    final cashBalance = EodCashBalance(cashGrossSales: cashTotal);

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
    );
  }
}
