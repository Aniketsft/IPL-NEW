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
    try {
      final response = await _dio.get(
        'SalesInvoice/Products',
        queryParameters: {'sitecode': siteCode},
      );

      final List<dynamic> rawData = response.data;
      final db = await LocalDatabaseHelper.instance.database;

      final batch = db.batch();
      
      // We clear the table first or upsert. Let's clear the specific site's products if we want, 
      // but the data might not have siteCode column locally. We use warehouse locally.
      // So let's just clear all to replace with fresh sync or we can upsert.
      // Since it's a full sync, clear table is safer to avoid stale products.
      batch.delete(LocalDatabaseHelper.tableSalesInvoiceProducts);

      for (var item in rawData) {
        batch.insert(
          LocalDatabaseHelper.tableSalesInvoiceProducts,
          {
            LocalDatabaseHelper.colSiProdSku: item['sku'] ?? '',
            LocalDatabaseHelper.colSiProdName: item['name'] ?? '',
            LocalDatabaseHelper.colSiProdStockQty: item['stockQty'] ?? 0.0,
            LocalDatabaseHelper.colSiProdWarehouse: item['warehouse'] ?? '',
            LocalDatabaseHelper.colSiProdStockUnit: item['stockUnit'] ?? '',
            LocalDatabaseHelper.colSiProdIsSynced: 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      debugPrint('Successfully synced ${rawData.length} sales invoice products.');
    } catch (e) {
      debugPrint('Error syncing sales invoice products: $e');
      rethrow;
    }
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
      conditions.add('${LocalDatabaseHelper.colSiProdWarehouse} = ?');
      whereArgs.add(warehouse);
    }

    if (query.isNotEmpty) {
      conditions.add('(${LocalDatabaseHelper.colSiProdName} LIKE ? OR ${LocalDatabaseHelper.colSiProdSku} LIKE ?)');
      whereArgs.add('%$query%');
      whereArgs.add('%$query%');
    }

    if (stockFilter == 'in stock') {
      conditions.add('${LocalDatabaseHelper.colSiProdStockQty} > 0');
    } else if (stockFilter == 'out of stock') {
      conditions.add('${LocalDatabaseHelper.colSiProdStockQty} <= 0');
    }

    final whereClause = conditions.isEmpty ? null : conditions.join(' AND ');

    final result = await db.query(
      LocalDatabaseHelper.tableSalesInvoiceProducts,
      where: whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: LocalDatabaseHelper.colSiProdName,
      limit: limit,
      offset: offset,
    );

    return result.map((e) => SalesInvoiceProductModel(
      sku: e[LocalDatabaseHelper.colSiProdSku] as String,
      name: e[LocalDatabaseHelper.colSiProdName] as String,
      stockQty: (e[LocalDatabaseHelper.colSiProdStockQty] as num).toDouble(),
      warehouse: e[LocalDatabaseHelper.colSiProdWarehouse] as String,
      stockUnit: e[LocalDatabaseHelper.colSiProdStockUnit] as String? ?? '',
    )).toList();
  }

  Future<List<String>> getDistinctWarehouses() async {
    final db = await LocalDatabaseHelper.instance.database;
    final result = await db.rawQuery(
      '''SELECT DISTINCT ${LocalDatabaseHelper.colSiProdWarehouse} 
         FROM ${LocalDatabaseHelper.tableSalesInvoiceProducts} 
         WHERE ${LocalDatabaseHelper.colSiProdWarehouse} IS NOT NULL 
           AND ${LocalDatabaseHelper.colSiProdWarehouse} != "" 
         ORDER BY ${LocalDatabaseHelper.colSiProdWarehouse}'''
    );
    
    return result.map((e) => e[LocalDatabaseHelper.colSiProdWarehouse] as String).toList();
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
