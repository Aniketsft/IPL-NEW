import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../core/network_service.dart';
import '../local/local_database_helper.dart';
import '../models/sales_invoice_product_model.dart';
import '../models/sales_invoice_item_stock_model.dart';
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
    String? siteCode,
    String query = '',
    String stockFilter = 'all',
    String? stockStatus = 'A',
    int limit = 20,
    int offset = 0,
  }) async {
    final db = await LocalDatabaseHelper.instance.database;

    List<String> conditions = [];
    List<dynamic> whereArgs = [];

    if (stockStatus != null && stockStatus != 'ALL') {
      conditions.add('(S.stockStatus = ? OR (S.stockStatus IS NULL AND ? = "A"))');
      whereArgs.add(stockStatus);
      whereArgs.add(stockStatus);
    }

    if (siteCode != null && siteCode.isNotEmpty && siteCode != 'ALL') {
      conditions.add('(S.siteCode = ? OR S.warehouse = ?)');
      whereArgs.add(siteCode);
      whereArgs.add(siteCode);
    }

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
      havingClause = 'HAVING SUM(S.totalQty) > 0';
    } else if (stockFilter == 'out of stock') {
      havingClause = 'HAVING SUM(S.totalQty) <= 0';
    }

    final sql =
        '''
      SELECT
        S.itemCode AS sku, 
        S.itemName AS name, 
        SUM(S.totalQty) AS stockQty, 
        MAX(S.warehouse) AS warehouse,
        MAX(S.cce0) AS cce0,
        MAX(S.barcode) AS barcode,
        MAX(COALESCE(NULLIF(S.salesUnit, ''), NULLIF(P.salesUnit, ''), 'UN')) AS salesUnit,
        COALESCE(S.stockStatus, 'A') AS stockStatus
      FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} S
      LEFT JOIN ${LocalDatabaseHelper.tableSalesInvoiceProducts} P ON S.itemCode = P.sku
      $whereClause
      GROUP BY S.itemCode, S.itemName, COALESCE(S.stockStatus, 'A')
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
            salesUnit: ((e['salesUnit'] as String?)?.trim().isNotEmpty == true)
                ? (e['salesUnit'] as String).trim()
                : 'UN',
            cce0: (e['cce0'] as String?) ?? '',
            barcode: (e['barcode'] as String?) ?? '',
            stockStatus: (e['stockStatus'] as String?) ?? 'A',
          ),
        )
        .toList();
  }

  Future<SalesInvoiceProductModel?> getProductByItemCode(
    String itemCode, {
    String? stockStatus = 'A',
  }) async {
    final db = await LocalDatabaseHelper.instance.database;

    final String statusClause = (stockStatus != null && stockStatus != 'ALL')
        ? 'AND (S.stockStatus = ? OR (S.stockStatus IS NULL AND ? = "A"))'
        : '';
    final List<dynamic> args = (stockStatus != null && stockStatus != 'ALL')
        ? [itemCode, stockStatus, stockStatus]
        : [itemCode];

    final sql = '''
      SELECT
        S.itemCode AS sku, 
        S.itemName AS name, 
        SUM(S.totalQty) AS stockQty, 
        MAX(S.warehouse) AS warehouse,
        MAX(S.cce0) AS cce0,
        MAX(S.barcode) AS barcode,
        MAX(COALESCE(NULLIF(S.salesUnit, ''), NULLIF(P.salesUnit, ''), 'UN')) AS salesUnit,
        COALESCE(S.stockStatus, 'A') AS stockStatus
      FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} S
      LEFT JOIN ${LocalDatabaseHelper.tableSalesInvoiceProducts} P ON S.itemCode = P.sku
      WHERE S.itemCode = ? $statusClause
      GROUP BY S.itemCode, S.itemName, COALESCE(S.stockStatus, 'A')
      LIMIT 1
    ''';

    final result = await db.rawQuery(sql, args);

    if (result.isNotEmpty) {
      final e = result.first;
      return SalesInvoiceProductModel(
        sku: e['sku'] as String,
        name: e['name'] as String,
        stockQty: (e['stockQty'] as num?)?.toDouble() ?? 0.0,
        warehouse: (e['warehouse'] as String?) ?? '',
        salesUnit: ((e['salesUnit'] as String?)?.trim().isNotEmpty == true)
            ? (e['salesUnit'] as String).trim()
            : 'UN',
        cce0: (e['cce0'] as String?) ?? '',
        barcode: (e['barcode'] as String?) ?? '',
        stockStatus: (e['stockStatus'] as String?) ?? 'A',
      );
    }
    return null;
  }

  Future<List<String>> getDistinctWarehouses([String? siteCode]) async {
    final db = await LocalDatabaseHelper.instance.database;
    final String whereClause = (siteCode != null && siteCode.isNotEmpty && siteCode != 'ALL')
        ? 'WHERE (siteCode = ? OR warehouse = ?) AND warehouse IS NOT NULL AND warehouse != ""'
        : 'WHERE warehouse IS NOT NULL AND warehouse != ""';
    final List<dynamic> whereArgs = (siteCode != null && siteCode.isNotEmpty && siteCode != 'ALL')
        ? [siteCode, siteCode]
        : [];

    final result = await db.rawQuery('''SELECT DISTINCT warehouse 
         FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} 
         $whereClause
         ORDER BY warehouse''', whereArgs);

    return result.map((e) => e['warehouse'] as String).toList();
  }

  Future<List<String>> getDistinctSites() async {
    final db = await LocalDatabaseHelper.instance.database;
    final result = await db.rawQuery('SELECT DISTINCT code FROM ${LocalDatabaseHelper.tableSites} ORDER BY code');
    return result.map((e) => e['code'] as String).toList();
  }

  Future<void> syncSalesInvoiceItemStockDetails([String? siteCode]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final etagKey = 'etag_stock_${siteCode?.isNotEmpty == true ? siteCode : "default"}';
      final cachedEtag = prefs.getString(etagKey);
      final headers = <String, dynamic>{};
      if (cachedEtag != null && cachedEtag.isNotEmpty) {
        headers['If-None-Match'] = cachedEtag;
      }

      final response = await _dio.get(
        'SalesInvoice/itemstockdetails',
        queryParameters: (siteCode != null && siteCode.isNotEmpty)
            ? {'sitecode': siteCode}
            : null,
        options: Options(
          headers: headers.isNotEmpty ? headers : null,
          validateStatus: (status) => status != null && ((status >= 200 && status < 300) || status == 304),
        ),
      );

      if (response.statusCode == 304) {
        debugPrint('Sync: Stock details up-to-date (HTTP 304 Not Modified). Bypassing re-index.');
        return;
      }

      final dynamic respData = response.data;
      if (respData == null || respData is! List) {
        debugPrint('Sync: Stock details response is empty or invalid.');
        return;
      }

      final List<dynamic> rawData = respData;
      
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

      // Update stored ETag on successful ingestion
      final newEtag = response.headers.value('etag');
      if (newEtag != null && newEtag.isNotEmpty) {
        await prefs.setString(etagKey, newEtag);
      }

      debugPrint(
        'Successfully synced ${rawData.length} sales invoice item stock details.',
      );
    } catch (e) {
      debugPrint('Error syncing sales invoice item stock details: $e');
      rethrow;
    }
  }

  Future<void> _applyUnsyncedLedgerToStock(Transaction txn) async {
    // 0. Ensure all unsynced lots exist in stock details (with 0 initial qty) so we can deduct/add from them.
    await txn.rawInsert('''
      INSERT OR IGNORE INTO ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} 
        (itemCode, itemName, lotNumber, warehouse, warehouseName, location, locationType, totalQty, taxLevel, cce0, salesUnit, barcode, siteCode, stockStatus, isSynced, createdAt, updatedAt, deviceId)
      SELECT DISTINCT 
        L.sku, 
        COALESCE((SELECT itemName FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} WHERE itemCode = L.sku LIMIT 1), ''),
        L.lotNumber, 
        L.warehouse, 
        '', 
        L.location, 
        '', 
        0.0, 
        '', 
        '', 
        '',
        '',
        '',
        'A',
        1, 
        datetime('now'), 
        datetime('now'), 
        ''
      FROM ${LocalDatabaseHelper.tableSiInvoiceLines} L
      JOIN ${LocalDatabaseHelper.tableSiInvoices} I ON L.invoiceId = I.invoiceId
      WHERE I.isSynced = 0 OR I.isSynced IS NULL
    ''');

    // 1. Deduct unsynced active INVOICES exclusively from sellable (A) stock
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
      WHERE (${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.stockStatus = 'A' OR ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.stockStatus IS NULL OR ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.stockStatus = '')
        AND EXISTS (
          SELECT 1 FROM ${LocalDatabaseHelper.tableSiInvoiceLines} L2
          JOIN ${LocalDatabaseHelper.tableSiInvoices} I2 ON L2.invoiceId = I2.invoiceId
          WHERE (I2.isSynced = 0 OR I2.isSynced IS NULL) AND I2.transactionType = 'INVOICE' AND I2.isReversed = 0
            AND L2.sku = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.itemCode
            AND L2.lotNumber = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.lotNumber
            AND L2.warehouse = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.warehouse
            AND L2.location = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.location
        )
    ''');

    // 2. Add back unsynced CREDIT_NOTES into quarantine (Q) stock
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
      WHERE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.stockStatus = 'Q'
        AND EXISTS (
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
    String itemCode, {
    String? stockStatus = 'A',
  }) async {
    final db = await LocalDatabaseHelper.instance.database;
    final String statusClause = (stockStatus != null && stockStatus != 'ALL')
        ? 'AND (stockStatus = ? OR (stockStatus IS NULL AND ? = "A"))'
        : '';
    final List<dynamic> args = (stockStatus != null && stockStatus != 'ALL')
        ? [itemCode, stockStatus, stockStatus]
        : [itemCode];

    final sql = '''
      SELECT * 
      FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}
      WHERE itemCode = ? $statusClause
    ''';
    final result = await db.rawQuery(sql, args);

    return result.map((e) => SalesInvoiceItemStockModel.fromSqlMap(e)).toList();
  }

  /// Fetches live real-time stock directly from Sage X3 factoring physical inventory and active allocations (ITMMVT).
  Future<Map<String, dynamic>?> fetchLiveProductStock(String productCode, [String? siteCode]) async {
    try {
      final response = await _dio.get(
        'SalesInvoice/product/$productCode/live-stock',
        queryParameters: (siteCode != null && siteCode.isNotEmpty) ? {'sitecode': siteCode} : null,
        options: Options(
          sendTimeout: const Duration(milliseconds: 1500),
          receiveTimeout: const Duration(milliseconds: 1500),
        ),
      );
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return null;
    } catch (e) {
      debugPrint('Sync: Live product stock unreachable ($productCode), falling back to local SQLite.');
      return null;
    }
  }

  /// Fetches live customer credit limit and live outstanding balance directly from Sage X3.
  Future<Map<String, dynamic>?> fetchLiveCustomerCredit(String customerNo) async {
    try {
      final response = await _dio.get(
        'SalesInvoice/customer/$customerNo/live-credit',
        options: Options(
          sendTimeout: const Duration(milliseconds: 1500),
          receiveTimeout: const Duration(milliseconds: 1500),
        ),
      );
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return null;
    } catch (e) {
      debugPrint('Sync: Live credit unreachable for customer $customerNo, using local snapshot.');
      return null;
    }
  }
}
