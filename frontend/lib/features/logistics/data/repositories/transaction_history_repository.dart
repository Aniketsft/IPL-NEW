import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/transaction_model.dart';

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
}
