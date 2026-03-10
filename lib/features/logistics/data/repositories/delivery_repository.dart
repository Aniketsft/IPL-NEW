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
import 'package:sqflite/sqflite.dart';
import '../../domain/entities/location_lookup.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';
import '../local/local_database_helper.dart';

class DeliveryRepository implements ILogisticsRepository {
  final Dio _dio;

  DeliveryRepository({required NetworkService networkService})
    : _dio = networkService.dio;

  @override
  Future<List<SalesOrderDetail>> getSalesOrderDetails(String soNumber) async {
    try {
      final db = await LocalDatabaseHelper.instance.database;
      final maps = await db.query(
        LocalDatabaseHelper.tableDetails,
        where: '${LocalDatabaseHelper.colDetSoNum} = ?',
        whereArgs: [soNumber],
      );

      // We also need to factor in local scans for manufactured/remaining
      final scans = await LocalDatabaseHelper.instance.getUnsyncedScans();
      final filteredScans = scans
          .where((s) => s['soNumber'] == soNumber)
          .toList();

      return maps.map((map) {
        final itemCode = map[LocalDatabaseHelper.colDetItemCode] as String;
        final qty = (map[LocalDatabaseHelper.colDetQuantity] as num).toDouble();

        final localManufactured = filteredScans
            .where((s) => s['productCode'] == itemCode)
            .fold(0.0, (sum, s) => sum + (s['quantity'] as num).toDouble());

        return SalesOrderDetail(
          soNumber: map[LocalDatabaseHelper.colDetSoNum] as String,
          itemCode: itemCode,
          description: map[LocalDatabaseHelper.colDetDescription] as String,
          barcodeType: map[LocalDatabaseHelper.colDetBarcodeType] as String,
          quantity: qty,
          remaining: qty - localManufactured,
          manufacturedQuantity: localManufactured,
        );
      }).toList();
    } catch (e) {
      throw 'Failed to fetch sales order details from local DB: $e';
    }
  }

  @override
  Future<List<SalesOrderDetail>> getProductionTracking() async {
    // In the new model, this is just another view of the local Orders/Details
    // For now, let's return all details for all orders marked as Internal or Sage
    try {
      final db = await LocalDatabaseHelper.instance.database;
      final maps = await db.query(LocalDatabaseHelper.tableDetails);
      return maps.map((m) => _mapLocalDetailToEntity(m)).toList();
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

  Future<String> saveCutBulkEntry(Map<String, dynamic> entry) async {
    final db = await LocalDatabaseHelper.instance.database;
    final today = DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(today);

    try {
      // 1. Generate Local ID (CB-DATE-COUNT style to match backend expectations)
      final existingCount =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM ${LocalDatabaseHelper.tableOrders} WHERE ${LocalDatabaseHelper.colOrderNum} LIKE ?',
              ['CB-$dateStr%'],
            ),
          ) ??
          0;
      final entryNo =
          'CB-$dateStr-${(existingCount + 1).toString().padLeft(4, '0')}';

      // 2. Save to SQLite with "Internal" flag to protect from sync-wipes
      await db.transaction((txn) async {
        await txn.insert(LocalDatabaseHelper.tableOrders, {
          LocalDatabaseHelper.colOrderNum: entryNo,
          LocalDatabaseHelper.colPoNum: entry['poNumber'],
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

        // Add a detail record so it shows up in tracking lists
        await txn.insert(LocalDatabaseHelper.tableDetails, {
          LocalDatabaseHelper.colDetSoNum: entryNo,
          LocalDatabaseHelper.colDetItemCode: entry['type'] == 'Cuts'
              ? 'PROD-CUT'
              : 'PROD-BLK',
          LocalDatabaseHelper.colDetDescription: entry['type'] == 'Cuts'
              ? 'Internal - Cuts'
              : 'Internal - Bulk',
          LocalDatabaseHelper.colDetBarcodeType: 'Variable Weight',
          LocalDatabaseHelper.colDetQuantity: entry['amountKg'],
        });
      });

      // 3. Attempt to push to API (Stealth Background Sync)
      try {
        await _dio.post('Logistics/cut-bulk', data: entry);
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
              // Fetch amount from details
              final details = await LocalDatabaseHelper.instance
                  .getSalesOrderDetails(soNum);
              double amount = 0;
              if (details.isNotEmpty) {
                amount = (details.first['quantity'] as num).toDouble();
              }

              return {
                'entryNumber': soNum,
                'type': soNum.toUpperCase().contains('CUT')
                    ? 'Cuts'
                    : 'Bulks', // Consistent with Entry generation
                'customerCode': o[LocalDatabaseHelper.colCustomerCode],
                'customerName': o[LocalDatabaseHelper.colCustomerName],
                'date': o[LocalDatabaseHelper.colOrderDate],
                'poNumber': o[LocalDatabaseHelper.colPoNum],
                'salesman1Code': o[LocalDatabaseHelper.colRep0],
                'salesman2Code': o[LocalDatabaseHelper.colRep1],
                'amountKg': amount,
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

      counts = {
        'orders': orders.length,
        'details': details.length,
        'customers': customers.length,
        'reps': reps.length,
        'locations': locations.length,
      };

      await LocalDatabaseHelper.instance.refreshLogisticsData(
        orders: orders,
        details: details,
        customers: customers,
        reps: reps,
        locations: locations,
      );

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
    return SalesOrderDetail(
      soNumber: row[LocalDatabaseHelper.colDetSoNum] ?? '',
      itemCode: row[LocalDatabaseHelper.colDetItemCode] ?? '',
      description: row[LocalDatabaseHelper.colDetDescription] ?? '',
      barcodeType:
          row[LocalDatabaseHelper.colDetBarcodeType] ?? 'Variable Weight',
      quantity: (row[LocalDatabaseHelper.colDetQuantity] as num).toDouble(),
      remaining: 0, // Calculated in UI/Business logic
      manufacturedQuantity: 0,
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
}

/// Top-level background function for Isolate-based data processing.
/// This prevents large payload mapping from blocking the UI thread.
Map<String, List<Map<String, dynamic>>> _parseAndSanitizeData(dynamic data) {
  final orders = (data['orders'] as List)
      .map((j) => SalesOrderDto.fromJson(j).toSqlMap())
      .toList();

  final details = (data['details'] as List)
      .map((j) => SalesOrderDetailDto.fromJson(j).toSqlMap())
      .toList();

  final customers = (data['customers'] as List)
      .map((j) => LookupDto.fromJson(j).toSqlMap())
      .toList();

  final reps = (data['reps'] as List)
      .map((j) => LookupDto.fromJson(j).toSqlMap())
      .toList();

  final locations = (data['locations'] as List)
      .map((j) => LocationLookupDto.fromJson(j).toSqlMap())
      .toList();

  return {
    'orders': orders,
    'details': details,
    'customers': customers,
    'reps': reps,
    'locations': locations,
  };
}
