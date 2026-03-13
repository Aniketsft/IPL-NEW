import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/sales_order.dart';
import '../../domain/entities/sales_order_detail.dart';
import '../../domain/repositories/ilogistics_repository.dart';
import '../models/sales_order_dto.dart';
import '../models/sales_order_detail_dto.dart';
import '../models/location_lookup_dto.dart';
import '../models/lookup_dto.dart';
import '../models/product_master_dto.dart';
import 'package:sqflite/sqflite.dart';
import '../../domain/entities/location_lookup.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';
import '../local/local_database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/sync_progress.dart';
import 'dart:async';

class DeliveryRepository implements ILogisticsRepository {
  final Dio _dio;

  DeliveryRepository({required NetworkService networkService})
    : _dio = networkService.dio;

  @override
  Future<List<SalesOrderDetail>> getSalesOrderDetails(String soNumber) async {
    try {
      final maps = await LocalDatabaseHelper.instance.getReconciledDetails(
        soNumber,
      );

      return maps.map((map) {
        return SalesOrderDetail(
          soNumber: map[LocalDatabaseHelper.colDetSoNum] as String,
          itemCode: map[LocalDatabaseHelper.colDetItemCode] as String,
          description: map[LocalDatabaseHelper.colDetDescription] as String,
          barcodeType: map[LocalDatabaseHelper.colDetBarcodeType] as String,
          quantity: (map[LocalDatabaseHelper.colDetQuantity] as num).toDouble(),
          remaining: (map['reconciledRemaining'] as num).toDouble(),
          manufacturedQuantity: (map['reconciledProduced'] as num).toDouble(),
        );
      }).toList();
    } catch (e) {
      throw 'Failed to fetch reconciled sales order details: $e';
    }
  }

  @override
  Future<List<SalesOrderDetail>> getProductionTracking() async {
    try {
      final db = await LocalDatabaseHelper.instance.database;
      final maps = await db.rawQuery('''
        SELECT 
          det.*,
          (COALESCE(det.manufactured, 0) + COALESCE(SUM(scn.${LocalDatabaseHelper.columnQuantity}), 0)) as reconciledProduced,
          (COALESCE(det.quantity, 0) - (COALESCE(det.manufactured, 0) + COALESCE(SUM(scn.${LocalDatabaseHelper.columnQuantity}), 0))) as reconciledRemaining
        FROM ${LocalDatabaseHelper.tableDetails} det
        LEFT JOIN ${LocalDatabaseHelper.tableScans} scn 
          ON det.${LocalDatabaseHelper.colDetSoNum} = scn.${LocalDatabaseHelper.columnSoNumber} 
          AND det.${LocalDatabaseHelper.colDetItemCode} = scn.${LocalDatabaseHelper.columnProductCode}
          AND scn.${LocalDatabaseHelper.columnIsReflected} = 0
        GROUP BY det.${LocalDatabaseHelper.colDetSoNum}, det.${LocalDatabaseHelper.colDetItemCode}
      ''');

      return maps.map((map) {
        return SalesOrderDetail(
          soNumber: map[LocalDatabaseHelper.colDetSoNum] as String,
          itemCode: map[LocalDatabaseHelper.colDetItemCode] as String,
          description: map[LocalDatabaseHelper.colDetDescription] as String,
          barcodeType: map[LocalDatabaseHelper.colDetBarcodeType] as String,
          quantity: (map[LocalDatabaseHelper.colDetQuantity] as num).toDouble(),
          remaining: (map['reconciledRemaining'] as num).toDouble(),
          manufacturedQuantity: (map['reconciledProduced'] as num).toDouble(),
        );
      }).toList();
    } catch (e) {
      throw 'Failed to fetch production tracking: $e';
    }
  }

  @override
  Future<List<SalesOrder>> fetchSalesOrders({DateTime? date}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (date != null) {
        queryParams['deliveryDate'] = DateFormat('yyyy-MM-dd').format(date);
      }

      final response = await _dio.get(
        'Logistics/consolidated-orders',
        queryParameters: queryParams,
      );
      final data = response.data as List;
      return data.map((json) {
        final dto = SalesOrderDto.fromJson(json);
        return SalesOrder(
          id: dto.soNumber,
          orderNumber: dto.soNumber,
          customerCode: dto.customerCode,
          customerName: dto.customerName,
          deliveryDate: dto.deliveryDate,
          date: DateTime.tryParse(dto.deliveryDate) ?? DateTime.now(),
          purchaseOrderNumber: dto.poNo,
          salesManCode1: dto.rep0 ?? '',
          salesManCode2: dto.rep1 ?? '',
          deliveryNo: null, // Placeholder for delivery specific logic
          deliveryFrom: null,
          deliveryLorry: null,
          deliverySalesman: null,
          soLorry: null,
          originalSoLorry: null,
          site: dto.site,
        );
      }).toList();
    } catch (e) {
      throw 'Failed to fetch sales orders: $e';
    }
  }

  /// Fetches order-header level data for ViewSalesOrderScreen.
  /// Calls GET /api/Logistics/sales-order-headers with optional filters.
  Future<List<SalesOrder>> fetchSalesOrderHeaders({
    String status = 'all',
    DateTime? date,
    String? customerCode,
    String? rep0,
    String? rep1,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final db = await LocalDatabaseHelper.instance.database;
      String whereClause = '1=1';
      List<dynamic> whereArgs = [];

      if (status == 'open') {
        whereClause += ' AND ${LocalDatabaseHelper.colStatus} = ?';
        whereArgs.add(1);
      } else if (status == 'closed') {
        whereClause += ' AND ${LocalDatabaseHelper.colStatus} = ?';
        whereArgs.add(2);
      }

      if (date != null) {
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        whereClause += ' AND ${LocalDatabaseHelper.colDeliveryDate} LIKE ?';
        whereArgs.add('$dateStr%');
      }

      if (customerCode != null && customerCode.isNotEmpty) {
        whereClause += ' AND ${LocalDatabaseHelper.colCustomerCode} = ?';
        whereArgs.add(customerCode);
      }

      final maps = await db.query(
        LocalDatabaseHelper.tableOrders,
        where: whereClause,
        whereArgs: whereArgs,
        groupBy: LocalDatabaseHelper.colOrderNum,
        orderBy: '${LocalDatabaseHelper.colOrderDate} DESC',
        limit: limit,
        offset: offset,
      );

      return maps.map((m) => _mapLocalHeaderToEntity(m)).toList();
    } catch (e) {
      throw 'Failed to fetch sales order headers from local DB: $e';
    }
  }

  @override
  Future<void> closeOrder(String soNumber, String closedBy) async {
    try {
      await _dio.post(
        'Logistics/close-order/$soNumber',
        queryParameters: {'closedBy': closedBy},
      );
    } catch (e) {
      throw 'Failed to close order: $e';
    }
  }

  Future<List<Map<String, String>>> getCustomers() async {
    try {
      final db = await LocalDatabaseHelper.instance.database;
      final maps = await db.query(
        LocalDatabaseHelper.tableCustomers,
        orderBy: LocalDatabaseHelper.colName,
      );
      return maps
          .map(
            (m) => {
              'code': (m[LocalDatabaseHelper.colCode] ?? '').toString(),
              'name': (m[LocalDatabaseHelper.colName] ?? '').toString(),
            },
          )
          .toList();
    } catch (e) {
      throw 'Failed to fetch customers from local DB: $e';
    }
  }

  Future<List<Map<String, String>>> getSalesReps() async {
    try {
      final db = await LocalDatabaseHelper.instance.database;
      final maps = await db.query(
        LocalDatabaseHelper.tableReps,
        orderBy: LocalDatabaseHelper.colName,
      );
      return maps
          .map(
            (m) => {
              'code': (m[LocalDatabaseHelper.colCode] ?? '').toString(),
              'name': (m[LocalDatabaseHelper.colName] ?? '').toString(),
            },
          )
          .toList();
    } catch (e) {
      throw 'Failed to fetch sales representatives from local DB: $e';
    }
  }

  Future<List<SalesOrderDetail>> fetchSalesOrderDetails(String soNumber) async {
    return getSalesOrderDetails(soNumber);
  }

  Future<SalesOrderDetail?> fetchProductionTrackingInfo(
    String soNumber,
    String productCode,
  ) async {
    try {
      final db = await LocalDatabaseHelper.instance.database;
      final maps = await db.query(
        LocalDatabaseHelper.tableDetails,
        where:
            '${LocalDatabaseHelper.colDetSoNum} = ? AND ${LocalDatabaseHelper.colDetItemCode} = ?',
        whereArgs: [soNumber, productCode],
      );
      if (maps.isEmpty) return null;
      return _mapLocalDetailToEntity(maps.first);
    } catch (e) {
      throw 'Failed to fetch tracking info from local DB: $e';
    }
  }

  // --- PRODUCT & SO LOOKUP ---

  Future<List<Map<String, String>>> getProducts() async {
    try {
      final db = await LocalDatabaseHelper.instance.database;
      final rows = await db.query(LocalDatabaseHelper.tableProducts);
      return rows.map((r) => {
        'code': r[LocalDatabaseHelper.colProdCode]?.toString() ?? '',
        'name': r[LocalDatabaseHelper.colProdDesc]?.toString() ?? '',
      }).toList();
    } catch (e) {
      throw 'Failed to fetch products from local DB: $e';
    }
  }

  Future<List<Map<String, String>>> getExistingCutBulkSOs() async {
    try {
      final db = await LocalDatabaseHelper.instance.database;
      final rows = await db.query(
        LocalDatabaseHelper.tableOrders,
        where: "${LocalDatabaseHelper.colOrderNum} LIKE 'CB-%'",
        orderBy: '${LocalDatabaseHelper.colOrderNum} DESC',
      );
      return rows.map((r) => {
        'code': r[LocalDatabaseHelper.colOrderNum]?.toString() ?? '',
        'name': '${r[LocalDatabaseHelper.colCustomerName] ?? ''} (${r[LocalDatabaseHelper.colOrderDate]?.toString().substring(0, 10) ?? ''})',
      }).toList();
    } catch (e) {
      throw 'Failed to fetch existing Cut/Bulk SOs: $e';
    }
  }

  // --- CUT/BULK SAVE ---

  Future<String> saveCutBulkEntry(Map<String, dynamic> entry) async {
    final db = await LocalDatabaseHelper.instance.database;
    final today = DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(today);

    try {
      final String entryNo;
      final existingSo = entry['existingSoNumber'] as String?;

      if (existingSo != null && existingSo.isNotEmpty) {
        // Reuse existing SO — only add a new detail line
        entryNo = existingSo;
      } else {
        // Generate new SO number
        final existingCount =
            Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM ${LocalDatabaseHelper.tableOrders} WHERE ${LocalDatabaseHelper.colOrderNum} LIKE ?',
                ['CB-$dateStr%'],
              ),
            ) ??
            0;
        entryNo =
            'CB-$dateStr-${(existingCount + 1).toString().padLeft(4, '0')}';

        // Insert header for new SO
        await db.insert(LocalDatabaseHelper.tableOrders, {
          LocalDatabaseHelper.colOrderNum: entryNo,
          LocalDatabaseHelper.colOrderDate: entry['date'],
          LocalDatabaseHelper.colDeliveryDate: entry['date'],
          LocalDatabaseHelper.colCustomerCode: entry['customerCode'],
          LocalDatabaseHelper.colCustomerName: entry['customerName'],
          LocalDatabaseHelper.colRep0: entry['salesman1Code'],
          LocalDatabaseHelper.colRep1: entry['salesman2Code'],
          LocalDatabaseHelper.colSite: 'INTERNAL',
          LocalDatabaseHelper.colStatus: 1,
          LocalDatabaseHelper.colSource: 'Internal',
          LocalDatabaseHelper.colStatusLabel: 'Open',
          LocalDatabaseHelper.columnIsSynced: 0,
        });
      }

      // Always add a detail line with the selected product
      await db.insert(LocalDatabaseHelper.tableDetails, {
        LocalDatabaseHelper.colDetSoNum: entryNo,
        LocalDatabaseHelper.colDetItemCode: entry['productCode'] ?? (entry['type'] == 'Cuts' ? 'PROD-CUT' : 'PROD-BLK'),
        LocalDatabaseHelper.colDetDescription: entry['productName'] ?? (entry['type'] == 'Cuts' ? 'Internal - Cuts' : 'Internal - Bulk'),
        LocalDatabaseHelper.colDetBarcodeType: 'Variable Weight',
        LocalDatabaseHelper.colDetQuantity: entry['amountKg'] ?? 0, // Amount from entry
      });

      // Mark order as unsynced if it was previously synced (adding new detail)
      if (existingSo != null && existingSo.isNotEmpty) {
        await db.update(
          LocalDatabaseHelper.tableOrders,
          {LocalDatabaseHelper.columnIsSynced: 0},
          where: '${LocalDatabaseHelper.colOrderNum} = ?',
          whereArgs: [entryNo],
        );
      }

      // Attempt to push to API (Stealth Background Sync)
      try {
        await _dio.post('Logistics/cut-bulk', data: {
          ...entry,
          'entryNumber': entryNo,
          'amountKg': entry['amountKg'] ?? 0,
        });
        print(
          "Offline-First: Cut/Bulk entry $entryNo successfully synced to API.",
        );
      } on DioException catch (e) {
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          print(
            "Offline-First: Connection issue saving Cut/Bulk $entryNo. Kept local (unsynced).",
          );
        } else {
          rethrow;
        }
      }

      return entryNo;
    } catch (e) {
      throw 'Failed to save Cut/Bulk entry locally: $e';
    }
  }

  // --- SYNC ORCHESTRATION ---

  Future<void> synchronize() async {
    final stopwatch = Stopwatch()..start();
    Map<String, int> counts = {};

    try {
      // 1. Push Unsynced Work (Scans + Cut/Bulk)
      final unsyncedScans = await LocalDatabaseHelper.instance
          .getUnsyncedScans();
      final unsyncedOrders = await LocalDatabaseHelper.instance
          .getUnsyncedInternalOrders();

      if (unsyncedScans.isNotEmpty || unsyncedOrders.isNotEmpty) {
        final payload = {
          'scans': unsyncedScans
              .map(
                (s) => {
                  'soNumber': s['soNumber'],
                  'itemCode': s['productCode'],
                  'scanAmountKg': s['quantity'],
                  'itemStatus': s['itemStatus'] ?? 'Q',
                  'location': s['location'],
                },
              )
              .toList(),
          'cutBulkEntries': (await Future.wait(
            unsyncedOrders.map((o) async {
              final soNum = o[LocalDatabaseHelper.colOrderNum] as String;
              // Fetch details for item code and amount
              final details = await LocalDatabaseHelper.instance
                  .getSalesOrderDetails(soNum);
              double amount = 0;
              String? itemCode;
              String? productName;
              if (details.isNotEmpty) {
                amount = (details.first['quantity'] as num).toDouble();
                itemCode = details.first['itemCode']?.toString();
                productName = details.first['description']?.toString();
              }

              return {
                'entryNumber': soNum,
                'type': soNum.toUpperCase().contains('CUT')
                    ? 'Cuts'
                    : 'Bulks',
                'customerCode': o[LocalDatabaseHelper.colCustomerCode],
                'customerName': o[LocalDatabaseHelper.colCustomerName],
                'date': o[LocalDatabaseHelper.colOrderDate],
                'poNumber': o[LocalDatabaseHelper.colPoNum],
                'salesman1Code': o[LocalDatabaseHelper.colRep0],
                'salesman2Code': o[LocalDatabaseHelper.colRep1],
                'amountKg': amount,
                'itemCode': itemCode,
                'productName': productName,
              };
            }),
          )),
          'deviceId': 'mobile-terminal',
        };

        // Note: We might need to refine the cutBulk mapping to get the amountKg from details table
        // For now, let's just implement the skeleton to fix the sync crash context.
        await _dio.post('Sync/push', data: payload);

        // Mark everything as synced locally
        if (unsyncedScans.isNotEmpty) {
          final ids = unsyncedScans.map((s) => s['id'] as int).toList();
          await LocalDatabaseHelper.instance.markAsSynced(ids);
        }
        if (unsyncedOrders.isNotEmpty) {
          final soNums = unsyncedOrders
              .map((o) => o[LocalDatabaseHelper.colOrderNum] as String)
              .toList();
          await LocalDatabaseHelper.instance.markOrdersAsSynced(soNums);
        }
      }

      // 2. Refresh Mirror Data
      final response = await _dio.get(
        'Sync/refresh',
        queryParameters: {'site': 'IPL'},
      );
      final rawData = response.data;

      // PERFORMANCE: Move heavy mapping to an Isolate (Background Worker)
      final processedData = await compute(_parseAndSanitizeData, rawData);

      final orders = processedData['orders'] as List<Map<String, dynamic>>;
      final details = processedData['details'] as List<Map<String, dynamic>>;
      final customers =
          processedData['customers'] as List<Map<String, dynamic>>;
      final reps = processedData['reps'] as List<Map<String, dynamic>>;
      final locations =
          processedData['locations'] as List<Map<String, dynamic>>;
      final products = processedData['products'] as List<Map<String, dynamic>>;

      counts = {
        'orders': orders.length,
        'details': details.length,
        'customers': customers.length,
        'reps': reps.length,
        'locations': locations.length,
        'products': products.length,
      };

      await LocalDatabaseHelper.instance.refreshLogisticsData(
        orders: orders,
        details: details,
        customers: customers,
        reps: reps,
        locations: locations,
        products: products,
      );

      // REFLECTION SYSTEM: Mark all synced scans as reflected now that we have a fresh mirror
      final syncedScans = await LocalDatabaseHelper.instance.database.then(
        (db) => db.query(
          LocalDatabaseHelper.tableScans,
          where:
              '${LocalDatabaseHelper.columnIsSynced} = 1 AND ${LocalDatabaseHelper.columnIsReflected} = 0',
        ),
      );
      if (syncedScans.isNotEmpty) {
        final ids = syncedScans.map((s) => s['id'] as int).toList();
        await LocalDatabaseHelper.instance.marksReflected(ids);
        print('Reflection System: Marked ${ids.length} scans as reflected.');
      }

      // Log Success
      final duration = stopwatch.elapsedMilliseconds;
      await LocalDatabaseHelper.instance.insertSyncHistory(
        status: 'Success',
        message: 'Sync completed in ${duration}ms',
        counts: counts,
      );
    } catch (e) {
      // Log Failure
      await LocalDatabaseHelper.instance.insertSyncHistory(
        status: 'Failed',
        message: 'Sync error: $e',
        counts: counts.isNotEmpty ? counts : null,
      );
      throw 'Sync failed: $e';
    }
  }

  @override
  Stream<SyncProgress> synchronizeWithProgress() async* {
    final stopwatch = Stopwatch()..start();
    Map<String, int> counts = {};

    try {
      yield SyncProgress(status: 'Initializing sync...', progress: 0.05);

      // 1. Push Unsynced Work
      yield SyncProgress(status: 'Pushing local changes...', progress: 0.1);
      final unsyncedScans = await LocalDatabaseHelper.instance.getUnsyncedScans();
      final unsyncedOrders = await LocalDatabaseHelper.instance.getUnsyncedInternalOrders();

      if (unsyncedScans.isNotEmpty || unsyncedOrders.isNotEmpty) {
        final payload = {
          'scans': unsyncedScans.map((s) => {
            'soNumber': s['soNumber'],
            'itemCode': s['productCode'],
            'scanAmountKg': s['quantity'],
            'itemStatus': s['itemStatus'] ?? 'Q',
            'location': s['location'],
          }).toList(),
          'cutBulkEntries': (await Future.wait(unsyncedOrders.map((o) async {
            final soNum = o[LocalDatabaseHelper.colOrderNum] as String;
            final details = await LocalDatabaseHelper.instance.getSalesOrderDetails(soNum);
            double amount = details.isNotEmpty ? (details.first['quantity'] as num).toDouble() : 0;
            return {
              'entryNumber': soNum,
              'type': soNum.toUpperCase().contains('CUT') ? 'Cuts' : 'Bulks',
              'customerCode': o[LocalDatabaseHelper.colCustomerCode],
              'customerName': o[LocalDatabaseHelper.colCustomerName],
              'date': o[LocalDatabaseHelper.colOrderDate],
              'poNumber': o[LocalDatabaseHelper.colPoNum],
              'salesman1Code': o[LocalDatabaseHelper.colRep0],
              'salesman2Code': o[LocalDatabaseHelper.colRep1],
              'amountKg': amount,
            };
          }))),
          'deviceId': 'mobile-terminal',
        };

        await _dio.post('Sync/push', data: payload);
        
        if (unsyncedScans.isNotEmpty) {
          await LocalDatabaseHelper.instance.markAsSynced(unsyncedScans.map((s) => s['id'] as int).toList());
        }
        if (unsyncedOrders.isNotEmpty) {
          await LocalDatabaseHelper.instance.markOrdersAsSynced(unsyncedOrders.map((o) => o[LocalDatabaseHelper.colOrderNum] as String).toList());
        }
      }

      yield SyncProgress(status: 'Fetching updates...', progress: 0.3);
      
      // 2. Refresh Mirror Data (Incremental)
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getString('last_sync_timestamp');

      final response = await _dio.get(
        'Sync/refresh',
        queryParameters: {
          'site': 'IPL',
          if (lastSync != null) 'since': lastSync,
        },
      );
      
      final rawData = response.data;
      final serverTimestamp = rawData['timestamp'] as String?;

      yield SyncProgress(status: 'Processing data...', progress: 0.6);
      final processedData = await compute(_parseAndSanitizeData, rawData);

      final tables = ['orders', 'details', 'customers', 'reps', 'locations', 'products'];
      for (var i = 0; i < tables.length; i++) {
        final table = tables[i];
        final data = processedData[table] as List<Map<String, dynamic>>;
        counts[table] = data.length;
        yield SyncProgress(
          status: 'Updating $table (${data.length} items)...',
          progress: 0.6 + (0.3 * (i / tables.length)),
        );
      }

      await LocalDatabaseHelper.instance.refreshLogisticsData(
        orders: processedData['orders'] as List<Map<String, dynamic>>,
        details: processedData['details'] as List<Map<String, dynamic>>,
        customers: processedData['customers'] as List<Map<String, dynamic>>,
        reps: processedData['reps'] as List<Map<String, dynamic>>,
        locations: processedData['locations'] as List<Map<String, dynamic>>,
        products: processedData['products'] as List<Map<String, dynamic>>,
      );

      // Save new timestamp
      if (serverTimestamp != null) {
        await prefs.setString('last_sync_timestamp', serverTimestamp);
      }

      // Reflection
      final syncedScans = await LocalDatabaseHelper.instance.database.then(
        (db) => db.query(
          LocalDatabaseHelper.tableScans,
          where: '${LocalDatabaseHelper.columnIsSynced} = 1 AND ${LocalDatabaseHelper.columnIsReflected} = 0',
        ),
      );
      if (syncedScans.isNotEmpty) {
        await LocalDatabaseHelper.instance.marksReflected(syncedScans.map((s) => s['id'] as int).toList());
      }

      final duration = stopwatch.elapsedMilliseconds;
      await LocalDatabaseHelper.instance.insertSyncHistory(
        status: 'Success',
        message: 'Sync completed in ${duration}ms',
        counts: counts,
      );

      yield SyncProgress.completed();
    } catch (e) {
      await LocalDatabaseHelper.instance.insertSyncHistory(
        status: 'Failed',
        message: 'Sync error: $e',
        counts: counts.isNotEmpty ? counts : null,
      );
      yield SyncProgress.error(e.toString());
    }
  }

  // --- PRIVATE MAPPERS ---

  SalesOrder _mapLocalHeaderToEntity(Map<String, dynamic> row) {
    return SalesOrder(
      id: row[LocalDatabaseHelper.colOrderNum] ?? '',
      orderNumber: row[LocalDatabaseHelper.colOrderNum] ?? '',
      customerCode: row[LocalDatabaseHelper.colCustomerCode] ?? '',
      customerName: row[LocalDatabaseHelper.colCustomerName] ?? '',
      deliveryDate: row[LocalDatabaseHelper.colDeliveryDate] ?? '',
      date:
          DateTime.tryParse(row[LocalDatabaseHelper.colDeliveryDate] ?? '') ??
          DateTime.now(),
      purchaseOrderNumber: row[LocalDatabaseHelper.colPoNum],
      salesManCode1: row[LocalDatabaseHelper.colRep0] ?? '',
      salesManCode2: row[LocalDatabaseHelper.colRep1] ?? '',
      site: row[LocalDatabaseHelper.colSite],
      isClosed: row[LocalDatabaseHelper.colStatus] == 2,
      isEditable: true,
    );
  }

  SalesOrderDetail _mapLocalDetailToEntity(Map<String, dynamic> row) {
    final qty = (row[LocalDatabaseHelper.colDetQuantity] as num).toDouble();
    final manufactured = (row['manufactured'] as num?)?.toDouble() ?? 0.0;
    final remaining =
        (row['remaining'] as num?)?.toDouble() ?? (qty - manufactured);

    return SalesOrderDetail(
      soNumber: row[LocalDatabaseHelper.colDetSoNum] ?? '',
      itemCode: row[LocalDatabaseHelper.colDetItemCode] ?? '',
      description: row[LocalDatabaseHelper.colDetDescription] ?? '',
      barcodeType:
          row[LocalDatabaseHelper.colDetBarcodeType] ?? 'Variable Weight',
      quantity: qty,
      remaining: remaining,
      manufacturedQuantity: manufactured,
    );
  }

  @override
  Future<void> updateSalesOrder(SalesOrder order) async {
    // Note: Update logic for Innodis might be different
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Future<void> syncScans(List<Map<String, dynamic>> scans) async {
    try {
      final payload = scans
          .map(
            (s) => {
              'soNumber': s['soNumber'],
              'itemCode': s['itemCode'],
              'quantity': s['quantity'],
              'scanTimestamp': s['timestamp'],
            },
          )
          .toList();

      await _dio.post('Logistics/sync-scans', data: payload);
    } catch (e) {
      throw 'Failed to sync scans: $e';
    }
  }

  @override
  Future<bool> isValidProduct(String code) async {
    return await LocalDatabaseHelper.instance.isValidProduct(code);
  }

  Future<void> saveProductionScan(Map<String, dynamic> scan) async {
    try {
      // 1. Map UI payload to SQLite schema
      final localRow = {
        LocalDatabaseHelper.columnSoNumber: scan['soNumber'] ?? '',
        LocalDatabaseHelper.columnProductCode: scan['itemCode'] ?? '',
        LocalDatabaseHelper.columnQuantity: scan['scanAmountKg'] ?? 0.0,
        LocalDatabaseHelper.columnTimestamp: DateTime.now().toIso8601String(),
        LocalDatabaseHelper.columnItemStatus: scan['itemStatus'] ?? 'Q',
        LocalDatabaseHelper.columnLocationCode: scan['location'] ?? '',
        LocalDatabaseHelper.columnIsSynced: 0,
      };

      // 2. Persist to Local DB IMMEDIATELY
      final id = await LocalDatabaseHelper.instance.insertScan(localRow);
      print("Offline-First: Scan saved locally with ID $id.");

      // 3. Attempt Optimistic API Call
      try {
        await _dio.post('Logistics/production-scan', data: scan);
        // On Success, mark as synced
        await LocalDatabaseHelper.instance.markAsSynced([id]);
        print("Offline-First: Scan ID $id successfully synced to API.");
      } on DioException catch (e) {
        // Suppress network errors for "Stealth Sync"
        // This allows the user to continue scanning while offline
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          print(
            "Offline-First: Connection issue. Scan ID $id kept local (unsynced).",
          );
        } else {
          // Rethrow non-connection errors (e.g., 500 Server Error, Validation)
          rethrow;
        }
      }
    } catch (e) {
      print("CRITICAL: Local persistence failed for scan: $e");
      throw 'Failed to save scan: $e';
    }
  }

  @override
  Future<List<LocationLookup>> getLocationLookups(String site) async {
    try {
      final db = await LocalDatabaseHelper.instance.database;
      final maps = await db.query(
        LocalDatabaseHelper.tableLocations,
        where: '${LocalDatabaseHelper.colLocSite} = ?',
        whereArgs: [site],
      );
      return maps
          .map(
            (m) => LocationLookup(
              site: m[LocalDatabaseHelper.colLocSite] as String,
              location: m[LocalDatabaseHelper.colLocCode] as String,
              warehouse: m[LocalDatabaseHelper.colLocWrh] as String?,
              warehouseName: m[LocalDatabaseHelper.colLocWrhName] as String?,
              locationType: m[LocalDatabaseHelper.colLocType] as String?,
              locationTypeName:
                  m[LocalDatabaseHelper.colLocTypeName] as String?,
            ),
          )
          .toList();
    } catch (e) {
      throw 'Failed to fetch location lookups from local DB: $e';
    }
  }

  Future<Map<String, dynamic>?> decodeBarcode(String barcode) async {
    // 1. Variable Weight (VW) - Prefix "20"
    // Format: 20[5-char item code][5-char weight in grams][1-char checksum]
    if (barcode.startsWith('20') && barcode.length == 13) {
      final productCode = barcode.substring(2, 7);
      final weightStr = barcode.substring(7, 12);
      final weight = int.parse(weightStr) / 1000.0;
      return {'productCode': productCode, 'weight': weight};
    }

    // 2. Fixed Weight (FW) - Prefix "10"
    // Format: 10[5-char item code]...
    if (barcode.startsWith('10') && barcode.length >= 7) {
      final productCode = barcode.substring(2, 7);
      return {'productCode': productCode, 'weight': 1.0};
    }

    // 3. Global Lookup (GL) - Full match in product_master
    final product = await LocalDatabaseHelper.instance.getProductByCode(barcode);
    if (product != null) {
      return {
        'productCode': product[LocalDatabaseHelper.colProdCode],
        'weight': 1.0
      };
    }

    return null;
  }
}

/// Top-level background function for Isolate-based data processing.
/// This prevents large payload mapping from blocking the UI thread.
Map<String, List<Map<String, dynamic>>> _parseAndSanitizeData(dynamic data) {
  final orders = (data['orders'] as List)
      .map<Map<String, dynamic>>((j) => SalesOrderDto.fromJson(j).toSqlMap())
      .toList();

  final details = (data['details'] as List)
      .map<Map<String, dynamic>>((j) => SalesOrderDetailDto.fromJson(j).toSqlMap())
      .toList();

  final customers = (data['customers'] as List)
      .map<Map<String, dynamic>>((j) => LookupDto.fromJson(j).toSqlMap())
      .toList();

  final reps = (data['reps'] as List)
      .map<Map<String, dynamic>>((j) => LookupDto.fromJson(j).toSqlMap())
      .toList();

  final locations = (data['locations'] as List)
      .map<Map<String, dynamic>>((j) => LocationLookupDto.fromJson(j).toSqlMap())
      .toList();

  final products = (data['products'] as List)
      .map<Map<String, dynamic>>((j) => ProductMasterDto.fromJson(j).toSqlMap())
      .toList();

  return {
    'orders': orders,
    'details': details,
    'customers': customers,
    'reps': reps,
    'locations': locations,
    'products': products,
  };
}
