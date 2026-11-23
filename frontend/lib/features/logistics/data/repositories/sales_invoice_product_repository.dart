import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../core/network_service.dart';
import '../../../../core/secure_storage_service.dart';
import '../../../../core/services/device_info_service.dart';
import '../local/local_database_helper.dart';
import '../models/sales_invoice_product_model.dart';
import '../models/sales_invoice_item_stock_model.dart';
import 'package:flutter/foundation.dart';

class AssignedLorryScope {
  final bool isAssigned;
  final String siteCode;
  final String lorryCode;
  final String warehouseCode;

  const AssignedLorryScope({
    required this.isAssigned,
    required this.siteCode,
    this.lorryCode = '',
    this.warehouseCode = '',
  });
}

class FocLorryStockMatch {
  final String itemName;
  final String salesUnit;
  final String lotNumber;
  final String warehouse;
  final String warehouseName;
  final String location;
  final String locationType;
  final double totalStock;

  const FocLorryStockMatch({
    required this.itemName,
    required this.salesUnit,
    required this.lotNumber,
    required this.warehouse,
    required this.warehouseName,
    required this.location,
    required this.locationType,
    required this.totalStock,
  });
}

class LorryLotAllocation {
  final String lotNumber;
  final String warehouse;
  final String warehouseName;
  final String location;
  final String locationType;
  final String salesUnit;
  final String itemName;
  final String taxLevel;
  final String stockStatus;
  final double allocatedQty;
  final double lotAvailableQty;

  const LorryLotAllocation({
    required this.lotNumber,
    required this.warehouse,
    required this.warehouseName,
    required this.location,
    required this.locationType,
    required this.salesUnit,
    required this.itemName,
    required this.taxLevel,
    required this.stockStatus,
    required this.allocatedQty,
    required this.lotAvailableQty,
  });
}

List<Map<String, dynamic>> _parseItemStockData(dynamic rawData) {
  final List<dynamic> list = rawData is List
      ? rawData
      : (rawData is String && rawData.trim().isNotEmpty
          ? (jsonDecode(rawData) as List<dynamic>)
          : const []);
  return list.map((item) {
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

  static Future<void> invalidateStockCache({bool clearLocalRows = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('etag_stock_') || k == 'si_product_warehouse').toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
      if (clearLocalRows) {
        await LocalDatabaseHelper.instance.clearSalesInvoiceItemStockDetails();
      }
    } catch (e) {
      debugPrint('SalesInvoiceProductRepository.invalidateStockCache warning: $e');
    }
  }

  Future<AssignedLorryScope> resolveAssignedLorryScope({String? siteCode}) async {
    final dev = DeviceInfoService.instance;
    var cleanSite = (siteCode ?? '').trim().toUpperCase();
    if (cleanSite.isEmpty) {
      cleanSite = (dev.assignedSite ?? '').trim().toUpperCase();
    }
    if (cleanSite.isEmpty) {
      cleanSite = (await SecureStorageService().getSiteCode() ?? '').trim().toUpperCase();
    }

    var loc = (dev.assignedLocation ?? '').trim().toUpperCase();
    var wrh = (dev.assignedWarehouse ?? '').trim().toUpperCase();

    if ((loc.isEmpty || wrh.isEmpty) && dev.deviceId.isNotEmpty) {
      final row = await LocalDatabaseHelper.instance.getDeviceLocation(dev.deviceId);
      if (row != null) {
        if (cleanSite.isEmpty) {
          cleanSite = (row['siteCode']?.toString() ?? '').trim().toUpperCase();
        }
        if (loc.isEmpty) {
          loc = (row['locationCode']?.toString() ?? '').trim().toUpperCase();
        }
        if (wrh.isEmpty) {
          wrh = (row['warehouseCode']?.toString() ?? '').trim().toUpperCase();
        }
      }
    }

    final bool hasConcreteLoc = loc.isNotEmpty && loc != cleanSite && loc != 'ALL';
    final bool hasConcreteWrh = wrh.isNotEmpty && wrh != cleanSite && wrh != 'ALL';

    if (!hasConcreteLoc && !hasConcreteWrh) {
      return AssignedLorryScope(isAssigned: false, siteCode: cleanSite);
    }

    final lorryCode = hasConcreteLoc ? loc : wrh;
    final warehouseCode = hasConcreteWrh ? wrh : lorryCode;
    return AssignedLorryScope(
      isAssigned: true,
      siteCode: cleanSite,
      lorryCode: lorryCode,
      warehouseCode: warehouseCode,
    );
  }

  void _appendLorryAndSiteConditions(
    List<String> conditions,
    List<dynamic> whereArgs,
    AssignedLorryScope scope, {
    String alias = '',
  }) {
    final p = alias.isNotEmpty ? '$alias.' : '';
    if (scope.siteCode.isNotEmpty && scope.siteCode != 'ALL') {
      conditions.add("(UPPER(TRIM(${p}siteCode)) = ? OR TRIM(COALESCE(${p}siteCode, '')) = '')");
      whereArgs.add(scope.siteCode);
    }
    conditions.add('(UPPER(TRIM(${p}location)) IN (?, ?) OR UPPER(TRIM(${p}warehouse)) IN (?, ?))');
    whereArgs.addAll([
      scope.lorryCode,
      scope.warehouseCode,
      scope.lorryCode,
      scope.warehouseCode,
    ]);
  }

  void _appendStatusCondition(
    List<String> conditions,
    List<dynamic> whereArgs,
    String? stockStatus, {
    String alias = '',
  }) {
    final cleanStatus = (stockStatus ?? 'ALL').trim().toUpperCase();
    if (cleanStatus.isEmpty || cleanStatus == 'ALL') return;
    final p = alias.isNotEmpty ? '$alias.' : '';
    conditions.add("UPPER(TRIM(COALESCE(NULLIF(TRIM(${p}stockStatus), ''), 'A'))) LIKE ?");
    whereArgs.add('$cleanStatus%');
  }

  static String _statusOrderSql({String alias = ''}) {
    final p = alias.isNotEmpty ? '$alias.' : '';
    return "CASE "
        "WHEN UPPER(TRIM(COALESCE(NULLIF(TRIM(${p}stockStatus), ''), 'A'))) LIKE 'A%' THEN 0 "
        "WHEN UPPER(TRIM(COALESCE(NULLIF(TRIM(${p}stockStatus), ''), 'A'))) LIKE 'Q%' THEN 1 "
        "WHEN UPPER(TRIM(COALESCE(NULLIF(TRIM(${p}stockStatus), ''), 'A'))) LIKE 'R%' THEN 2 "
        "ELSE 3 END";
  }

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
    String? stockStatus = 'ALL',
    int limit = 20,
    int offset = 0,
  }) async {
    final scope = await resolveAssignedLorryScope(siteCode: siteCode);
    if (!scope.isAssigned) {
      return [];
    }

    final db = await LocalDatabaseHelper.instance.database;

    List<String> conditions = [];
    List<dynamic> whereArgs = [];

    _appendLorryAndSiteConditions(conditions, whereArgs, scope, alias: 'S');
    _appendStatusCondition(conditions, whereArgs, stockStatus, alias: 'S');

    if (query.isNotEmpty) {
      conditions.add('(S.itemName LIKE ? OR S.itemCode LIKE ?)');
      whereArgs.add('%$query%');
      whereArgs.add('%$query%');
    }

    final whereClause = 'WHERE ${conditions.join(" AND ")}';

    String havingClause = '';
    if (stockFilter == 'in stock') {
      havingClause = 'HAVING SUM(S.totalQty) > 0';
    } else if (stockFilter == 'out of stock') {
      havingClause = 'HAVING SUM(S.totalQty) <= 0';
    }

    final statusOrder = _statusOrderSql(alias: 'S');
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
        UPPER(TRIM(COALESCE(NULLIF(TRIM(S.stockStatus), ''), 'A'))) AS stockStatus
      FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} S
      LEFT JOIN ${LocalDatabaseHelper.tableSalesInvoiceProducts} P ON S.itemCode = P.sku
      $whereClause
      GROUP BY S.itemCode, S.itemName, UPPER(TRIM(COALESCE(NULLIF(TRIM(S.stockStatus), ''), 'A')))
      $havingClause
      ORDER BY $statusOrder, S.itemName
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
    String? siteCode,
    String? stockStatus = 'ALL',
  }) async {
    final scope = await resolveAssignedLorryScope(siteCode: siteCode);
    if (!scope.isAssigned) {
      return null;
    }

    final db = await LocalDatabaseHelper.instance.database;

    final List<String> conditions = ['S.itemCode = ?'];
    final List<dynamic> args = [itemCode.trim()];
    _appendLorryAndSiteConditions(conditions, args, scope, alias: 'S');
    _appendStatusCondition(conditions, args, stockStatus, alias: 'S');

    final whereClause = 'WHERE ${conditions.join(' AND ')}';
    final statusOrder = _statusOrderSql(alias: 'S');

    final sql = '''
      SELECT
        S.itemCode AS sku, 
        S.itemName AS name, 
        SUM(S.totalQty) AS stockQty, 
        MAX(S.warehouse) AS warehouse,
        MAX(S.cce0) AS cce0,
        MAX(S.barcode) AS barcode,
        MAX(COALESCE(NULLIF(S.salesUnit, ''), NULLIF(P.salesUnit, ''), 'UN')) AS salesUnit,
        UPPER(TRIM(COALESCE(NULLIF(TRIM(S.stockStatus), ''), 'A'))) AS stockStatus
      FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} S
      LEFT JOIN ${LocalDatabaseHelper.tableSalesInvoiceProducts} P ON S.itemCode = P.sku
      $whereClause
      GROUP BY S.itemCode, S.itemName, UPPER(TRIM(COALESCE(NULLIF(TRIM(S.stockStatus), ''), 'A')))
      ORDER BY $statusOrder, SUM(S.totalQty) DESC
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
    final scope = await resolveAssignedLorryScope(siteCode: siteCode);
    if (!scope.isAssigned) {
      return [];
    }
    return [scope.lorryCode];
  }

  Future<List<String>> getDistinctSites() async {
    final db = await LocalDatabaseHelper.instance.database;
    final result = await db.rawQuery('SELECT DISTINCT code FROM ${LocalDatabaseHelper.tableSites} ORDER BY code');
    return result.map((e) => e['code'] as String).toList();
  }

  Future<void> syncSalesInvoiceItemStockDetails([String? siteCode, bool forceFullRefresh = false]) async {
    try {
      final cleanSite = siteCode?.trim().toUpperCase();
      final prefs = await SharedPreferences.getInstance();
      final etagKey = 'etag_stock_${cleanSite?.isNotEmpty == true ? cleanSite : "default"}';
      if (forceFullRefresh) {
        await prefs.remove(etagKey);
      }
      final cachedEtag = forceFullRefresh ? null : prefs.getString(etagKey);
      final headers = <String, dynamic>{};
      if (cachedEtag != null && cachedEtag.isNotEmpty) {
        headers['If-None-Match'] = cachedEtag;
      }

      final response = await _dio.get(
        'SalesInvoice/itemstockdetails',
        queryParameters: (cleanSite != null && cleanSite.isNotEmpty)
            ? {'sitecode': cleanSite}
            : null,
        options: Options(
          headers: headers.isNotEmpty ? headers : null,
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && ((status >= 200 && status < 300) || status == 304),
        ),
      );

      if (response.statusCode == 304) {
        debugPrint('Sync: Stock details up-to-date (HTTP 304 Not Modified). Bypassing re-index.');
        return;
      }

      final lorryRequiredHeader = (response.headers.value('x-lorry-required') ?? '').trim().toLowerCase();
      if (lorryRequiredHeader == 'true') {
        debugPrint('Sync: Server indicates tablet has no assigned lorry (X-Lorry-Required). Clearing stale stock.');
        await LocalDatabaseHelper.instance.clearSalesInvoiceItemStockDetails();
        await prefs.remove(etagKey);
        return;
      }

      final dynamic respData = response.data;
      if (respData == null || (respData is! List && respData is! String)) {
        debugPrint('Sync: Stock details response is empty or invalid.');
        return;
      }

      final dynamic rawData = respData;
      
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
        'Successfully synced ${parsedData.length} sales invoice item stock details.',
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

    // 2. Ensure missing lot/status rows exist for unsynced CREDIT_NOTES (A, R, Q),
    //    then replenish each returned line into its exact resolved stockStatus.
    final stockCols = (await txn.rawQuery(
      'PRAGMA table_info(${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails})',
    ))
        .map((r) => (r['name'] ?? '').toString())
        .toSet();
    final cnCols = (await txn.rawQuery(
      'PRAGMA table_info(${LocalDatabaseHelper.tableSiCreditNotes})',
    ))
        .map((r) => (r['name'] ?? '').toString())
        .toSet();
    final cnlCols = (await txn.rawQuery(
      'PRAGMA table_info(${LocalDatabaseHelper.tableSiCreditNoteLines})',
    ))
        .map((r) => (r['name'] ?? '').toString())
        .toSet();

    if (!stockCols.contains('stockStatus') ||
        !cnCols.contains('stockTransaction') ||
        !cnlCols.contains('standaloneSku')) {
      return;
    }

    const cnStatusSql = '''
      CASE
        WHEN UPPER(TRIM(COALESCE(CNL.stockStatus, ''))) LIKE 'R%' THEN 'R'
        WHEN UPPER(TRIM(COALESCE(CNL.stockStatus, ''))) LIKE 'Q%' THEN 'Q'
        WHEN UPPER(TRIM(COALESCE(CNL.stockStatus, ''))) LIKE 'A%' THEN 'A'
        WHEN UPPER(TRIM(COALESCE(CNL.returnCondition, ''))) IN ('DEF', 'DAMAGED', 'REJECTED') THEN 'R'
        WHEN UPPER(TRIM(COALESCE(CNL.returnCondition, ''))) IN ('EXP', 'EXPIRED', 'QUARANTINE') THEN 'Q'
        ELSE 'A'
      END
    ''';

    await txn.rawInsert('''
      INSERT OR IGNORE INTO ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}
        (itemCode, itemName, lotNumber, warehouse, warehouseName, location, locationType, totalQty, taxLevel, cce0, salesUnit, barcode, siteCode, stockStatus, isSynced, createdAt, updatedAt, deviceId)
      SELECT DISTINCT
        COALESCE(NULLIF(TRIM(CNL.standaloneSku), ''), OL.sku, ''),
        COALESCE(NULLIF(TRIM(CNL.standaloneName), ''), OL.name, COALESCE((SELECT itemName FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} WHERE itemCode = COALESCE(NULLIF(TRIM(CNL.standaloneSku), ''), OL.sku, '') LIMIT 1), '')),
        COALESCE(NULLIF(TRIM(CNL.standaloneLot), ''), OL.lotNumber, ''),
        COALESCE(NULLIF(TRIM(CNL.standaloneWarehouse), ''), OL.warehouse, ''),
        '',
        COALESCE(NULLIF(TRIM(CNL.location), ''), NULLIF(TRIM(OL.location), ''), ''),
        '',
        0.0,
        '',
        COALESCE(NULLIF(TRIM(CNL.standaloneCce0), ''), OL.cce0, ''),
        COALESCE(NULLIF(TRIM(CNL.standaloneSalesUnit), ''), OL.salesUnit, 'EA'),
        '',
        COALESCE((SELECT siteCode FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} WHERE itemCode = COALESCE(NULLIF(TRIM(CNL.standaloneSku), ''), OL.sku, '') AND COALESCE(siteCode, '') != '' LIMIT 1), ''),
        $cnStatusSql,
        1,
        datetime('now'),
        datetime('now'),
        ''
      FROM ${LocalDatabaseHelper.tableSiCreditNoteLines} CNL
      JOIN ${LocalDatabaseHelper.tableSiCreditNotes} CN ON CNL.creditNoteId = CN.creditNoteId
      LEFT JOIN ${LocalDatabaseHelper.tableSiInvoiceLines} OL
        ON CNL.originInvoiceId = OL.invoiceId AND CAST(CNL.originLineNo AS INTEGER) = OL.lineId
      LEFT JOIN ${LocalDatabaseHelper.tableSiInvoices} P ON CN.originInvoiceId = P.invoiceId
      WHERE (CN.isSynced = 0 OR CN.isSynced IS NULL)
        AND CN.stockTransaction = 1
        AND (P.invoiceId IS NULL OR P.isSynced = 1 OR COALESCE(P.isReversed, 0) = 0)
        AND COALESCE(NULLIF(TRIM(CNL.standaloneSku), ''), OL.sku, '') != ''
    ''');

    await txn.rawUpdate('''
      UPDATE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}
      SET totalQty = totalQty + (
        SELECT IFNULL(SUM(CNL.quantity), 0)
        FROM ${LocalDatabaseHelper.tableSiCreditNoteLines} CNL
        JOIN ${LocalDatabaseHelper.tableSiCreditNotes} CN ON CNL.creditNoteId = CN.creditNoteId
        LEFT JOIN ${LocalDatabaseHelper.tableSiInvoiceLines} OL
          ON CNL.originInvoiceId = OL.invoiceId AND CAST(CNL.originLineNo AS INTEGER) = OL.lineId
        LEFT JOIN ${LocalDatabaseHelper.tableSiInvoices} P ON CN.originInvoiceId = P.invoiceId
        WHERE (CN.isSynced = 0 OR CN.isSynced IS NULL)
          AND CN.stockTransaction = 1
          AND (P.invoiceId IS NULL OR P.isSynced = 1 OR COALESCE(P.isReversed, 0) = 0)
          AND COALESCE(NULLIF(TRIM(CNL.standaloneSku), ''), OL.sku, '') = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.itemCode
          AND COALESCE(NULLIF(TRIM(CNL.standaloneLot), ''), OL.lotNumber, '') = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.lotNumber
          AND COALESCE(NULLIF(TRIM(CNL.standaloneWarehouse), ''), OL.warehouse, '') = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.warehouse
          AND COALESCE(NULLIF(TRIM(CNL.location), ''), NULLIF(TRIM(OL.location), ''), '') = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.location
          AND ($cnStatusSql) = COALESCE(NULLIF(UPPER(TRIM(${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.stockStatus)), ''), 'A')
      )
      WHERE EXISTS (
        SELECT 1 FROM ${LocalDatabaseHelper.tableSiCreditNoteLines} CNL2
        JOIN ${LocalDatabaseHelper.tableSiCreditNotes} CN2 ON CNL2.creditNoteId = CN2.creditNoteId
        LEFT JOIN ${LocalDatabaseHelper.tableSiInvoiceLines} OL2
          ON CNL2.originInvoiceId = OL2.invoiceId AND CAST(CNL2.originLineNo AS INTEGER) = OL2.lineId
        LEFT JOIN ${LocalDatabaseHelper.tableSiInvoices} P2 ON CN2.originInvoiceId = P2.invoiceId
        WHERE (CN2.isSynced = 0 OR CN2.isSynced IS NULL)
          AND CN2.stockTransaction = 1
          AND (P2.invoiceId IS NULL OR P2.isSynced = 1 OR COALESCE(P2.isReversed, 0) = 0)
          AND COALESCE(NULLIF(TRIM(CNL2.standaloneSku), ''), OL2.sku, '') = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.itemCode
          AND COALESCE(NULLIF(TRIM(CNL2.standaloneLot), ''), OL2.lotNumber, '') = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.lotNumber
          AND COALESCE(NULLIF(TRIM(CNL2.standaloneWarehouse), ''), OL2.warehouse, '') = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.warehouse
          AND COALESCE(NULLIF(TRIM(CNL2.location), ''), NULLIF(TRIM(OL2.location), ''), '') = ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.location
          AND (
            CASE
              WHEN UPPER(TRIM(COALESCE(CNL2.stockStatus, ''))) LIKE 'R%' THEN 'R'
              WHEN UPPER(TRIM(COALESCE(CNL2.stockStatus, ''))) LIKE 'Q%' THEN 'Q'
              WHEN UPPER(TRIM(COALESCE(CNL2.stockStatus, ''))) LIKE 'A%' THEN 'A'
              WHEN UPPER(TRIM(COALESCE(CNL2.returnCondition, ''))) IN ('DEF', 'DAMAGED', 'REJECTED') THEN 'R'
              WHEN UPPER(TRIM(COALESCE(CNL2.returnCondition, ''))) IN ('EXP', 'EXPIRED', 'QUARANTINE') THEN 'Q'
              ELSE 'A'
            END
          ) = COALESCE(NULLIF(UPPER(TRIM(${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}.stockStatus)), ''), 'A')
      )
    ''');
  }

  Future<List<SalesInvoiceItemStockModel>> getSalesInvoiceItemStockDetails(
    String itemCode, {
    String? siteCode,
    String? stockStatus = 'ALL',
  }) async {
    final scope = await resolveAssignedLorryScope(siteCode: siteCode);
    if (!scope.isAssigned) {
      return [];
    }

    final db = await LocalDatabaseHelper.instance.database;
    final List<String> conditions = ['itemCode = ?'];
    final List<dynamic> args = [itemCode.trim()];
    _appendLorryAndSiteConditions(conditions, args, scope);
    _appendStatusCondition(conditions, args, stockStatus);

    final statusOrder = _statusOrderSql();
    final sql = '''
      SELECT * 
      FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails}
      WHERE ${conditions.join(' AND ')}
      ORDER BY $statusOrder, totalQty DESC
    ''';
    final result = await db.rawQuery(sql, args);

    return result.map((e) => SalesInvoiceItemStockModel.fromSqlMap(e)).toList();
  }

  /// Resolves sellable ('A' status) inventory for FOC free gifts strictly inside the tablet's assigned lorry.
  Future<FocLorryStockMatch> getFocLorryStockMatch(
    String targetFocSku, {
    String? preferredLot,
    String? siteCode,
  }) async {
    final cleanSku = targetFocSku.trim();
    final scope = await resolveAssignedLorryScope(siteCode: siteCode);
    if (!scope.isAssigned) {
      return const FocLorryStockMatch(
        itemName: '',
        salesUnit: 'EA',
        lotNumber: '',
        warehouse: '',
        warehouseName: '',
        location: '',
        locationType: '',
        totalStock: 0.0,
      );
    }

    final db = await LocalDatabaseHelper.instance.database;
    final baseConditions = <String>['itemCode = ?'];
    final baseArgs = <dynamic>[cleanSku];
    _appendLorryAndSiteConditions(baseConditions, baseArgs, scope);
    _appendStatusCondition(baseConditions, baseArgs, 'A');
    final baseWhere = baseConditions.join(' AND ');

    final sumResult = await db.rawQuery(
      'SELECT SUM(totalQty) as total FROM ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} WHERE $baseWhere',
      baseArgs,
    );
    final totalStock = (sumResult.isNotEmpty && sumResult.first['total'] != null)
        ? (sumResult.first['total'] as num).toDouble()
        : 0.0;

    if (totalStock <= 0.0001) {
      return FocLorryStockMatch(
        itemName: '',
        salesUnit: 'EA',
        lotNumber: '',
        warehouse: '',
        warehouseName: '',
        location: '',
        locationType: '',
        totalStock: totalStock,
      );
    }

    Map<String, dynamic>? picked;
    if (preferredLot != null && preferredLot.trim().isNotEmpty) {
      final sameLotMatches = await db.query(
        LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
        where: '$baseWhere AND lotNumber = ? AND totalQty > 0',
        whereArgs: [...baseArgs, preferredLot.trim()],
        limit: 1,
      );
      if (sameLotMatches.isNotEmpty) picked = sameLotMatches.first;
    }

    if (picked == null) {
      final anyStockedLot = await db.query(
        LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
        where: '$baseWhere AND totalQty > 0',
        whereArgs: baseArgs,
        orderBy: 'totalQty DESC',
        limit: 1,
      );
      if (anyStockedLot.isNotEmpty) picked = anyStockedLot.first;
    }

    if (picked == null) {
      final anyLot = await db.query(
        LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
        where: baseWhere,
        whereArgs: baseArgs,
        limit: 1,
      );
      if (anyLot.isNotEmpty) picked = anyLot.first;
    }

    final unit = (picked?['salesUnit'] as String?)?.trim();
    return FocLorryStockMatch(
      itemName: picked?['itemName']?.toString() ?? '',
      salesUnit: (unit != null && unit.isNotEmpty) ? unit : 'EA',
      lotNumber: picked?['lotNumber']?.toString() ?? '',
      warehouse: picked?['warehouse']?.toString() ?? '',
      warehouseName: picked?['warehouseName']?.toString() ?? '',
      location: picked?['location']?.toString() ?? '',
      locationType: picked?['locationType']?.toString() ?? '',
      totalStock: totalStock,
    );
  }

  static String lotAllocationKey(
    String lotNumber,
    String warehouse,
    String location,
  ) =>
      '${lotNumber.trim().toUpperCase()}|${warehouse.trim().toUpperCase()}|${location.trim().toUpperCase()}';

  static List<LorryLotAllocation> allocateAcrossLoadedLots(
    List<SalesInvoiceItemStockModel> lots, {
    required double requestedQty,
    String? preferredLot,
    Map<String, double>? reservedQtyByLotKey,
  }) {
    if (requestedQty <= 0.0001 || lots.isEmpty) return const [];

    final sellableLots = lots.where((s) {
      final rawStatus = s.stockStatus.trim().toUpperCase();
      return rawStatus.isEmpty || rawStatus.startsWith('A');
    }).toList();

    if (sellableLots.isEmpty) return const [];

    final cleanPreferred = (preferredLot ?? '').trim().toUpperCase();
    final orderedLots = <SalesInvoiceItemStockModel>[];
    if (cleanPreferred.isNotEmpty) {
      orderedLots.addAll(
        sellableLots.where(
          (s) => s.lotNumber.trim().toUpperCase() == cleanPreferred,
        ),
      );
      orderedLots.addAll(
        sellableLots.where(
          (s) => s.lotNumber.trim().toUpperCase() != cleanPreferred,
        ),
      );
    } else {
      orderedLots.addAll(sellableLots);
    }

    final allocations = <LorryLotAllocation>[];
    double remaining = requestedQty;

    for (final lot in orderedLots) {
      if (remaining <= 0.0001) break;
      final key = lotAllocationKey(lot.lotNumber, lot.warehouse, lot.location);
      final reserved = reservedQtyByLotKey?[key] ?? 0.0;
      final netAvailable = lot.totalQty - reserved;
      if (netAvailable <= 0.0001) continue;

      final take = netAvailable >= remaining ? remaining : netAvailable;
      final cleanTake = double.parse(take.toStringAsFixed(4));
      if (cleanTake <= 0.0001) continue;

      allocations.add(
        LorryLotAllocation(
          lotNumber: lot.lotNumber,
          warehouse: lot.warehouse,
          warehouseName: lot.warehouseName,
          location: lot.location,
          locationType: lot.locationType,
          salesUnit: lot.salesUnit.trim().isNotEmpty ? lot.salesUnit.trim() : 'EA',
          itemName: lot.itemName,
          taxLevel: lot.taxLevel,
          stockStatus: lot.stockStatus.trim().isNotEmpty ? lot.stockStatus : 'A',
          allocatedQty: cleanTake,
          lotAvailableQty: netAvailable,
        ),
      );
      remaining = double.parse((remaining - cleanTake).toStringAsFixed(4));
    }

    return allocations;
  }

  /// Allocates [requestedQty] of sellable ('A') stock across assigned lorry lots,
  /// consuming [preferredLot] first and automatically spilling over to remaining lots.
  Future<List<LorryLotAllocation>> allocateQuantityAcrossLorryLots(
    String itemCode, {
    required double requestedQty,
    String? preferredLot,
    String? siteCode,
    Map<String, double>? reservedQtyByLotKey,
  }) async {
    final lots = await getSalesInvoiceItemStockDetails(
      itemCode.trim(),
      siteCode: siteCode,
      stockStatus: 'A',
    );
    return allocateAcrossLoadedLots(
      lots,
      requestedQty: requestedQty,
      preferredLot: preferredLot,
      reservedQtyByLotKey: reservedQtyByLotKey,
    );
  }

  /// Allocates [requestedFocQty] across remaining sellable ('A') lots in the assigned lorry.
  Future<List<LorryLotAllocation>> allocateFocAcrossLorryLots(
    String targetFocSku, {
    required double requestedFocQty,
    String? preferredLot,
    String? siteCode,
    Map<String, double>? reservedQtyByLotKey,
  }) {
    return allocateQuantityAcrossLorryLots(
      targetFocSku,
      requestedQty: requestedFocQty,
      preferredLot: preferredLot,
      siteCode: siteCode,
      reservedQtyByLotKey: reservedQtyByLotKey,
    );
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
