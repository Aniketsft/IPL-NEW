import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../core/network_service.dart';
import '../local/local_database_helper.dart';
import '../models/sales_invoice_product_model.dart';
import '../models/sales_invoice_item_stock_model.dart';
import '../../../../core/config/api_config.dart';
import 'package:flutter/foundation.dart';

List<Map<String, dynamic>> _parseItemStockData(List<dynamic> rawData) {
  return rawData.map((item) {
    final model = SalesInvoiceItemStockModel.fromJson(
      item as Map<String, dynamic>,
    );
    return model.toSqlMap('');
  }).toList();
}

class SalesInvoiceProductRepository {
  final NetworkService _networkService;

  SalesInvoiceProductRepository(this._networkService);

  Dio get _dio => _networkService.dio;

  Future<void> syncSalesInvoiceProducts(String siteCode) async {
    // Deprecated: Product list is now derived dynamically from item stock details.
    debugPrint(
      'syncSalesInvoiceProducts is deprecated. Product catalog is now derived from item stock details.',
    );
    return;
  }

  Future<List<SalesInvoiceProductModel>> getSalesInvoiceProducts({
    String? warehouse,
    String query = '',
    String stockFilter = 'all',
    int limit = 20,
    int offset = 0,
  }) async {
    final db = await LocalDatabaseHelper.instance.database;

    List<String> conditions = [];
    List<dynamic> whereArgs = [];

    if (warehouse != null && warehouse.isNotEmpty && warehouse != 'ALL') {
      conditions.add('S.warehouse = ?');
      whereArgs.add(warehouse);
    }

    if (query.isNotEmpty) {
      conditions.add('(S.itemName LIKE ? OR S.itemCode LIKE ?)');
      whereArgs.add('%$query%');
      whereArgs.add('%$query%');
    }

    final whereClause = conditions.isEmpty
        ? ''
        : 'WHERE ${conditions.join(" AND ")}';

    String havingClause = '';
    if (stockFilter == 'in stock') {
      havingClause = 'HAVING stockQty > 0';
    } else if (stockFilter == 'out of stock') {
      havingClause = 'HAVING stockQty <= 0';
    }

    final sql =
        '''
      SELECT
        S.itemCode AS sku, 
        S.itemName AS name, 
        SUM(S.totalQty) AS stockQty, 
        MAX(S.warehouse) AS warehouse
      FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} S
      $whereClause
      GROUP BY S.itemCode, S.itemName
      $havingClause
      ORDER BY S.itemName
      LIMIT ? OFFSET ?
    ''';

    whereArgs.add(limit);
    whereArgs.add(offset);

    final result = await db.rawQuery(sql, whereArgs);

    return result
        .map(
          (e) => SalesInvoiceProductModel(
            sku: e['sku'] as String,
            name: e['name'] as String,
            stockQty: (e['stockQty'] as num?)?.toDouble() ?? 0.0,
            warehouse: (e['warehouse'] as String?) ?? '',
            salesUnit: 'EA', // Defaulted as it is aggregated
            cce0:
                '', // Since this is a GROUP BY query on stock details and cce0 is in tbl_si_products, we might not have it here if not joined.
          ),
        )
        .toList();
  }

  Future<List<String>> getDistinctWarehouses() async {
    final db = await LocalDatabaseHelper.instance.database;
    final result = await db.rawQuery('''SELECT DISTINCT warehouse 
         FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} 
         WHERE warehouse IS NOT NULL 
           AND warehouse != "" 
         ORDER BY warehouse''');

    return result.map((e) => e['warehouse'] as String).toList();
  }

  Future<List<String>> getDistinctSites() async {
    final db = await LocalDatabaseHelper.instance.database;
    final result = await db.rawQuery('SELECT DISTINCT code FROM ${LocalDatabaseHelper.tableSites} ORDER BY code');
    return result.map((e) => e['code'] as String).toList();
  }

  Future<void> syncSalesInvoiceItemStockDetails() async {
    try {
      final response = await _dio.get('SalesInvoice/itemstockdetails');
      final List<dynamic> rawData = response.data;
      
      // Parse in background to prevent UI freeze
      final List<Map<String, dynamic>> parsedData = await compute(_parseItemStockData, rawData);
      
      final db = await LocalDatabaseHelper.instance.database;

      await db.transaction((txn) async {
        await txn.delete(LocalDatabaseHelper.tableSalesInvoiceItemStockDetails);
        
        const chunkSize = 1000;
        for (int i = 0; i < parsedData.length; i += chunkSize) {
          final batch = txn.batch();
          final end = (i + chunkSize < parsedData.length) ? i + chunkSize : parsedData.length;
          final chunk = parsedData.sublist(i, end);
          
          for (var map in chunk) {
            batch.insert(
              LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
              map,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await batch.commit(noResult: true);
          await Future.delayed(Duration.zero); // let UI breathe
        }

        // Apply Unsynced Ledger after fully overwriting from X3
        await _applyUnsyncedLedgerToStock(txn);
      });

      debugPrint(
        'Successfully synced ${rawData.length} sales invoice item stock details.',
      );
    } catch (e) {
      debugPrint('Error syncing sales invoice item stock details: $e');
      rethrow;
    }
  }

  Future<void> _applyUnsyncedLedgerToStock(Transaction txn) async {
    // 1. Deduct unsynced active INVOICES
    await txn.rawUpdate('''
      UPDATE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}
      SET totalQty = totalQty - (
        SELECT IFNULL(SUM(L.quantity), 0)
        FROM ${LocalDatabaseHelper.tableSiInvoiceLines} L
        JOIN ${LocalDatabaseHelper.tableSiInvoices} I ON L.invoiceId = I.invoiceId
        WHERE (I.isSynced = 0 OR I.isSynced IS NULL) AND I.transactionType = 'INVOICE' AND I.isReversed = 0
          AND L.sku = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.itemCode
          AND L.lotNumber = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.lotNumber
          AND L.warehouse = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.warehouse
          AND L.location = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.location
      )
      WHERE EXISTS (
        SELECT 1 FROM ${LocalDatabaseHelper.tableSiInvoiceLines} L2
        JOIN ${LocalDatabaseHelper.tableSiInvoices} I2 ON L2.invoiceId = I2.invoiceId
        WHERE (I2.isSynced = 0 OR I2.isSynced IS NULL) AND I2.transactionType = 'INVOICE' AND I2.isReversed = 0
          AND L2.sku = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.itemCode
          AND L2.lotNumber = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.lotNumber
          AND L2.warehouse = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.warehouse
          AND L2.location = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.location
      )
    ''');

    // 2. Add back unsynced CREDIT_NOTES
    await txn.rawUpdate('''
      UPDATE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}
      SET totalQty = totalQty + (
        SELECT IFNULL(SUM(L.quantity), 0)
        FROM ${LocalDatabaseHelper.tableSiInvoiceLines} L
        JOIN ${LocalDatabaseHelper.tableSiInvoices} I ON L.invoiceId = I.invoiceId
        LEFT JOIN ${LocalDatabaseHelper.tableSiInvoices} P ON I.reference = P.invoiceId
        WHERE (I.isSynced = 0 OR I.isSynced IS NULL) AND I.transactionType = 'CREDIT_NOTE'
          AND (P.invoiceId IS NULL OR P.isSynced = 1)
          AND L.sku = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.itemCode
          AND L.lotNumber = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.lotNumber
          AND L.warehouse = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.warehouse
          AND L.location = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.location
      )
      WHERE EXISTS (
        SELECT 1 FROM ${LocalDatabaseHelper.tableSiInvoiceLines} L2
        JOIN ${LocalDatabaseHelper.tableSiInvoices} I2 ON L2.invoiceId = I2.invoiceId
        LEFT JOIN ${LocalDatabaseHelper.tableSiInvoices} P2 ON I2.reference = P2.invoiceId
        WHERE (I2.isSynced = 0 OR I2.isSynced IS NULL) AND I2.transactionType = 'CREDIT_NOTE'
          AND (P2.invoiceId IS NULL OR P2.isSynced = 1)
          AND L2.sku = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.itemCode
          AND L2.lotNumber = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.lotNumber
          AND L2.warehouse = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.warehouse
          AND L2.location = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.location
      )
    ''');
  }

  Future<List<SalesInvoiceItemStockModel>> getSalesInvoiceItemStockDetails(
    String itemCode,
  ) async {
    final db = await LocalDatabaseHelper.instance.database;
    final sql =
        '''
      SELECT * 
      FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}
      WHERE itemCode = ?
    ''';
    final result = await db.rawQuery(sql, [itemCode]);

    return result.map((e) => SalesInvoiceItemStockModel.fromSqlMap(e)).toList();
  }
}
