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
}
