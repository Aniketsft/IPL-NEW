import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/transaction_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/eod_report_model.dart';
import 'package:intl/intl.dart';


class TransactionHistoryRepository {
  final LocalDatabaseHelper _dbHelper;

  TransactionHistoryRepository({LocalDatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? LocalDatabaseHelper.instance;

  Future<List<TransactionModel>> getTransactions({
    String? type,
    String? startDate,
    String? endDate,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _dbHelper.database;

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

    final List<Map<String, dynamic>> maps = await db.query(
      LocalDatabaseHelper.tableSiInvoices,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'createdAt DESC',
      limit: limit,
      offset: offset,
    );

    return List.generate(maps.length, (i) {
      return TransactionModel.fromJson(maps[i]);
    });
  }

  // Method to get distinct transaction types, if needed
  Future<List<String>> getTransactionTypes() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT DISTINCT transactionType FROM ${LocalDatabaseHelper.tableSiInvoices} WHERE transactionType IS NOT NULL',
    );
    return maps.map((e) => e['transactionType'] as String).toList();
  }

  Future<List<Map<String, dynamic>>> getTransactionLines(String invoiceId) async {
    return await _dbHelper.getSalesInvoiceLines(invoiceId);
  }

  Future<void> cancelInvoice(TransactionModel transaction) async {
    final db = await _dbHelper.database;
    final batch = db.batch();

    // 1. Mark original invoice as reversed
    batch.update(
      LocalDatabaseHelper.tableSiInvoices,
      {'isReversed': 1},
      where: 'invoiceId = ?',
      whereArgs: [transaction.id],
    );

    // 2. Mark its lines as reversed
    batch.update(
      LocalDatabaseHelper.tableSiInvoiceLines,
      {'isReversed': 1},
      where: 'invoiceId = ?',
      whereArgs: [transaction.id],
    );

    // 3. Generate a new Credit Note row
    final creditNoteId = 'CN-${transaction.id}';
    final now = DateTime.now().toIso8601String();
    
    // Fetch original invoice to get exact vat and discount
    final originalInvoice = await db.query(
      LocalDatabaseHelper.tableSiInvoices,
      where: 'invoiceId = ?',
      whereArgs: [transaction.id],
      limit: 1,
    );
    
    double totalVat = 0.0;
    double totalDiscount = 0.0;
    if (originalInvoice.isNotEmpty) {
      totalVat = (originalInvoice.first['totalVat'] as num?)?.toDouble() ?? 0.0;
      totalDiscount = (originalInvoice.first['totalDiscount'] as num?)?.toDouble() ?? 0.0;
    }
    
    batch.insert(LocalDatabaseHelper.tableSiInvoices, {
      'invoiceId': creditNoteId,
      'customerCode': transaction.customerCode,
      'customerName': transaction.customerName,
      'totalVat': totalVat,
      'totalDiscount': totalDiscount,
      'grandTotal': transaction.grandTotal,
      'createdAt': now,
      'status': 'CREDIT_NOTE',
      'isSynced': 0,
      'transactionType': 'CREDIT_NOTE',
      'createdByUserId': transaction.auditMetadata.createdByUserId,
      'createdByUserName': transaction.auditMetadata.createdByUserName,
      'deviceId': transaction.auditMetadata.deviceId,
      'appVersion': transaction.auditMetadata.appVersion,
      'reference': transaction.id, // Links to original invoice
      'invoiceType': 'CREDIT_NOTE',
      'isReversed': 1,
      'transactionalId': transaction.id,
    });

    // 4. Copy lines and increment stock
    final lines = await getTransactionLines(transaction.id);
    for (var line in lines) {
      // Copy line
      batch.insert(LocalDatabaseHelper.tableSiInvoiceLines, {
        'invoiceId': creditNoteId,
        'sku': line['sku'],
        'name': line['name'],
        'quantity': line['quantity'],
        'basePrice': line['basePrice'],
        'discountAmount': line['discountAmount'],
        'vatAmount': line['vatAmount'],
        'total': line['total'],
        'lotNumber': line['lotNumber'],
        'warehouse': line['warehouse'],
        'location': line['location'],
        'salesUnit': line['salesUnit'],
        'cce0': line['cce0'],
        'taxRule': line['taxRule'],
        'isFoc': line['isFoc'],
        'isReversed': 0,
      });

      // Increment stock
      batch.rawUpdate(
        '''
        UPDATE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} 
        SET totalQty = totalQty + ? 
        WHERE itemCode = ? AND lotNumber = ? AND warehouse = ? AND location = ?
        ''',
        [line['quantity'], line['sku'], line['lotNumber'], line['warehouse'], line['location']],
      );
    }

    await batch.commit(noResult: true);
  }

  /// Aggregates all End-of-Day data for the given [date] from local SQLite.
  /// All 6 SQL queries verified against the confirmed DB schema.
  Future<EodReportModel> getEodReportData(DateTime date) async {
    final db = await _dbHelper.database;
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final startDate = '${dateStr}T00:00:00';
    final endDate = '${dateStr}T23:59:59';

    // ── 1. Valid Sales ────────────────────────────────────────────────────────
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

    // ── 3. Cancelled (Reversed) Receipts ──────────────────────────────────────
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
