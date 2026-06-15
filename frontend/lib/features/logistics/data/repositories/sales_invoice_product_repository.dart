import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../core/network_service.dart';
import '../local/local_database_helper.dart';
import '../models/sales_invoice_product_model.dart';
import '../models/sales_invoice_item_stock_model.dart';
import '../../../../core/config/api_config.dart';
import 'package:flutter/foundation.dart';

class SalesInvoiceProductRepository {
  final NetworkService _networkService;

  SalesInvoiceProductRepository(this._networkService);

  Dio get _dio => _networkService.dio;

  Future<void> syncSalesInvoiceProducts(String siteCode) async {
    // Deprecated: Product list is now derived dynamically from item stock details.
    debugPrint('syncSalesInvoiceProducts is deprecated. Product catalog is now derived from item stock details.');
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
      conditions.add('warehouse = ?');
      whereArgs.add(warehouse);
    }

    if (query.isNotEmpty) {
      conditions.add('(itemName LIKE ? OR itemCode LIKE ?)');
      whereArgs.add('%$query%');
      whereArgs.add('%$query%');
    }

    final whereClause = conditions.isEmpty ? '' : 'WHERE ${conditions.join(" AND ")}';

    String havingClause = '';
    if (stockFilter == 'in stock') {
      havingClause = 'HAVING SUM(totalQty) > 0';
    } else if (stockFilter == 'out of stock') {
      havingClause = 'HAVING SUM(totalQty) <= 0';
    }

    final sql = '''
      SELECT 
        itemCode AS sku, 
        itemName AS name, 
        SUM(totalQty) AS stockQty, 
        MAX(warehouse) AS warehouse
      FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}
      $whereClause
      GROUP BY itemCode, itemName
      $havingClause
      ORDER BY itemName
      LIMIT ? OFFSET ?
    ''';

    whereArgs.add(limit);
    whereArgs.add(offset);

    final result = await db.rawQuery(sql, whereArgs);

    return result.map((e) => SalesInvoiceProductModel(
      sku: e['sku'] as String,
      name: e['name'] as String,
      stockQty: (e['stockQty'] as num?)?.toDouble() ?? 0.0,
      warehouse: (e['warehouse'] as String?) ?? '',
      stockUnit: 'EA', // Defaulted as it is aggregated
    )).toList();
  }

  Future<List<String>> getDistinctWarehouses() async {
    final db = await LocalDatabaseHelper.instance.database;
    final result = await db.rawQuery(
      '''SELECT DISTINCT warehouse 
         FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} 
         WHERE warehouse IS NOT NULL 
           AND warehouse != "" 
         ORDER BY warehouse'''
    );
    
    return result.map((e) => e['warehouse'] as String).toList();
  }

  Future<void> syncSalesInvoiceItemStockDetails() async {
    try {
      final response = await _dio.get('SalesInvoice/itemstockdetails');
      final List<dynamic> rawData = response.data;
      final db = await LocalDatabaseHelper.instance.database;

      final batch = db.batch();
      batch.delete(LocalDatabaseHelper.tableSalesInvoiceItemStockDetails);

      for (var item in rawData) {
        final model = SalesInvoiceItemStockModel.fromJson(item as Map<String, dynamic>);
        batch.insert(
          LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
          model.toSqlMap(''), // Or pass device ID if needed, empty is fine here
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      debugPrint('Successfully synced ${rawData.length} sales invoice item stock details.');
    } catch (e) {
      debugPrint('Error syncing sales invoice item stock details: $e');
      rethrow;
    }
  }

  Future<List<SalesInvoiceItemStockModel>> getSalesInvoiceItemStockDetails(String itemCode) async {
    final db = await LocalDatabaseHelper.instance.database;
    final result = await db.query(
      LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
      where: 'itemCode = ?',
      whereArgs: [itemCode],
    );

    return result.map((e) => SalesInvoiceItemStockModel.fromSqlMap(e)).toList();
  }
}
