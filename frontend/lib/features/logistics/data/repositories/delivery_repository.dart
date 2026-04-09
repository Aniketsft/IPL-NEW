import 'package:dio/dio.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import '../../domain/entities/sales_order.dart';
import '../../domain/entities/sales_order_detail.dart';
import '../../domain/entities/site.dart';
import '../../domain/repositories/ilogistics_repository.dart';
import '../models/sales_order_dto.dart';
import '../models/sales_order_detail_dto.dart';
import '../models/location_lookup_dto.dart';
import '../models/lookup_dto.dart';
import '../models/lot_dto.dart';
import '../models/product_master_dto.dart';
import '../../domain/entities/sync_progress.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/sales_rep.dart';
import '../../domain/entities/location_lookup.dart';
import '../local/local_database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:enterprise_auth_mobile/core/utils/barcode_scanner/offline_barcode_processor.dart';

class DeliveryRepository implements ILogisticsRepository {
  final Dio _dio;
  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

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
          scannedQuantity: (map['reconciledProduced'] as num).toDouble(),
          manufacturedQuantity: (map['reconciledManufactured'] as num?)?.toDouble() ?? (map['reconciledProduced'] as num).toDouble(),
          isPrepared: map[LocalDatabaseHelper.colDetIsPrepared] == 1,
          isValidated: map[LocalDatabaseHelper.colDetIsValidated] == 1,
          unit: map[LocalDatabaseHelper.colDetUnit] as String? ?? 'KG',
          headerIsClosed: map['headerStatus'] == 2,
          headerIsPreparedForShipment: map['headerIsPreparedForShipment'] == 1,
        );
      }).toList();
    } catch (e) {
      throw 'Failed to fetch reconciled sales order details: $e';
    }
  }

  @override
  Future<List<SalesOrderDetail>> getProductionTracking({
    String? siteCode,
    String? customerCode,
    String? salesRepCode,
    DateTime? date,
  }) async {
    try {
      final db = await LocalDatabaseHelper.instance.database;

      List<String> filters = [];
      if (siteCode != null && siteCode.isNotEmpty) {
        filters.add('ord.${LocalDatabaseHelper.colSite} = "$siteCode"');
      }
      if (customerCode != null && customerCode.isNotEmpty) {
        filters.add('ord.${LocalDatabaseHelper.colCustomerCode} = "$customerCode"');
      }
      if (salesRepCode != null && salesRepCode.isNotEmpty) {
        filters.add('(ord.${LocalDatabaseHelper.colRep0} = "$salesRepCode" OR ord.${LocalDatabaseHelper.colRep1} = "$salesRepCode")');
      }
      if (date != null) {
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        filters.add('DATE(ord.${LocalDatabaseHelper.colOrderDate}) = "$dateStr"');
      }

      String filterClause = filters.isNotEmpty ? 'WHERE ${filters.join(' AND ')}' : '';

      final query = '''
        SELECT 
          det.*,
          (COALESCE(det.${LocalDatabaseHelper.colDetScanned}, 0) + COALESCE(scn.totalScannedQty, 0)) as reconciledProduced,
          (COALESCE(det.${LocalDatabaseHelper.colDetScanned}, 0) + COALESCE(scn.totalManufacturedQty, 0)) as reconciledManufactured,
          (COALESCE(det.${LocalDatabaseHelper.colDetQuantity}, 0) - (COALESCE(det.${LocalDatabaseHelper.colDetScanned}, 0) + COALESCE(scn.totalManufacturedQty, 0))) as reconciledRemaining
        FROM ${LocalDatabaseHelper.tableDetails} det
        INNER JOIN ${LocalDatabaseHelper.tableOrders} ord ON det.${LocalDatabaseHelper.colDetSoNum} = ord.${LocalDatabaseHelper.colOrderNum}
        LEFT JOIN (
          SELECT 
            ${LocalDatabaseHelper.columnSoNumber}, 
            ${LocalDatabaseHelper.columnProductCode}, 
            SUM(${LocalDatabaseHelper.columnQuantity}) as totalScannedQty,
            SUM(${LocalDatabaseHelper.columnManufacturedQuantity}) as totalManufacturedQty
          FROM ${LocalDatabaseHelper.tableScans}
          WHERE ${LocalDatabaseHelper.columnIsReflected} = 0
          GROUP BY ${LocalDatabaseHelper.columnSoNumber}, ${LocalDatabaseHelper.columnProductCode}
        ) scn ON det.${LocalDatabaseHelper.colDetSoNum} = scn.${LocalDatabaseHelper.columnSoNumber} 
          AND det.${LocalDatabaseHelper.colDetItemCode} = scn.${LocalDatabaseHelper.columnProductCode}
        $filterClause
      ''';

      final maps = await db.rawQuery(query);

      return maps.map((map) {
        return SalesOrderDetail(
          soNumber: map[LocalDatabaseHelper.colDetSoNum] as String,
          itemCode: map[LocalDatabaseHelper.colDetItemCode] as String,
          description: map[LocalDatabaseHelper.colDetDescription] as String,
          barcodeType: map[LocalDatabaseHelper.colDetBarcodeType] as String,
          quantity: (map[LocalDatabaseHelper.colDetQuantity] as num).toDouble(),
          remaining: (map['reconciledRemaining'] as num).toDouble(),
          scannedQuantity: (map['reconciledProduced'] as num).toDouble(),
          manufacturedQuantity: (map['reconciledManufactured'] as num).toDouble(),
          isPrepared: map[LocalDatabaseHelper.colDetIsPrepared] == 1,
          isValidated: map[LocalDatabaseHelper.colDetIsValidated] == 1,
          unit: map[LocalDatabaseHelper.colDetUnit] as String? ?? 'KG',
        );
      }).toList();
    } catch (e) {
      throw 'Failed to fetch production tracking: $e';
    }
  }

  @override
  Future<List<SalesOrder>> fetchSalesOrders({DateTime? date, String? siteCode}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (date != null) {
        queryParams['deliveryDate'] = DateFormat('yyyy-MM-dd').format(date);
      }
      if (siteCode != null && siteCode.isNotEmpty) {
        queryParams['site'] = siteCode;
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
  @override
  Future<List<SalesOrder>> fetchSalesOrderHeaders({
    String status = 'all',
    DateTime? date,
    String? siteCode,
    String? customerCode,
    String? locationCode,
    String? rep0,
    String? rep1,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final db = await LocalDatabaseHelper.instance.database;
      String whereClause = '1=1';
      List<dynamic> whereArgs = [];

      if (siteCode != null && siteCode.isNotEmpty) {
        whereClause += ' AND ${LocalDatabaseHelper.colSite} = ?';
        whereArgs.add(siteCode);
      }

      if (status == 'open') {
        whereClause += ' AND (${LocalDatabaseHelper.colStatus} IS NULL OR ${LocalDatabaseHelper.colStatus} != ?)';
        whereArgs.add(2);
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

      if (rep0 != null && rep0.isNotEmpty) {
        whereClause += ' AND ${LocalDatabaseHelper.colRep0} = ?';
        whereArgs.add(rep0);
      }

      if (rep1 != null && rep1.isNotEmpty) {
        whereClause += ' AND TRIM(${LocalDatabaseHelper.colRep1}) = ?';
        whereArgs.add(rep1);
      }

      if (locationCode != null && locationCode.isNotEmpty) {
        whereClause +=
            ' AND EXISTS (SELECT 1 FROM ${LocalDatabaseHelper.tableDetails} d '
            ' WHERE d.${LocalDatabaseHelper.colDetSoNum} = ${LocalDatabaseHelper.tableOrders}.${LocalDatabaseHelper.colOrderNum} '
            ' AND d.${LocalDatabaseHelper.colDetLocation} = ?)';
        whereArgs.add(locationCode);
      }

      // Use rawQuery to support LEFT JOIN for salesman name
      final String orderTable = LocalDatabaseHelper.tableOrders;
      final String repTable = LocalDatabaseHelper.tableReps;
      
      String sql = '''
        SELECT o.*, r.${LocalDatabaseHelper.colName} AS salesmanName
        FROM $orderTable o
        LEFT JOIN $repTable r ON o.${LocalDatabaseHelper.colRep1} = r.${LocalDatabaseHelper.colCode}
        WHERE $whereClause
        GROUP BY o.${LocalDatabaseHelper.colOrderNum}
        ORDER BY o.${LocalDatabaseHelper.colOrderDate} DESC
        LIMIT $limit OFFSET $offset
      ''';

      final maps = await db.rawQuery(sql, whereArgs);

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

      // Also update local DB so the status change reflects immediately
      final db = await LocalDatabaseHelper.instance.database;
      await db.update(
        LocalDatabaseHelper.tableOrders,
        {LocalDatabaseHelper.colStatus: 2, LocalDatabaseHelper.colStatusLabel: 'Closed'},
        where: '${LocalDatabaseHelper.colOrderNum} = ?',
        whereArgs: [soNumber],
      );
    } catch (e) {
      throw 'Failed to close order: $e';
    }
  }

  @override
  Future<List<Site>> getSites() async {
    try {
      final db = await LocalDatabaseHelper.instance.database;
      final maps = await db.query(
        LocalDatabaseHelper.tableSites,
        orderBy: LocalDatabaseHelper.colName,
      );
      return maps.map((m) => Site(
        code: (m[LocalDatabaseHelper.colCode] ?? '').toString(),
        name: (m[LocalDatabaseHelper.colName] ?? '').toString(),
      )).toList();
    } catch (e) {
      throw 'Failed to fetch sites from local DB: $e';
    }
  }

  @override
  Future<List<Customer>> getCustomers() async {
    try {
      final db = await LocalDatabaseHelper.instance.database;
      final maps = await db.query(
        LocalDatabaseHelper.tableCustomers,
        orderBy: LocalDatabaseHelper.colName,
      );
      return maps
          .map(
            (m) => Customer(
              code: (m[LocalDatabaseHelper.colCode] ?? '').toString(),
              name: (m[LocalDatabaseHelper.colName] ?? '').toString(),
            ),
          )
          .toList();
    } catch (e) {
      throw 'Failed to fetch customers from local DB: $e';
    }
  }

  @override
  Future<List<SalesRep>> getSalesReps() async {
    try {
      final db = await LocalDatabaseHelper.instance.database;
      final maps = await db.query(
        LocalDatabaseHelper.tableReps,
        orderBy: LocalDatabaseHelper.colName,
      );
      return maps
          .map(
            (m) => SalesRep(
              code: (m[LocalDatabaseHelper.colCode] ?? '').toString(),
              name: (m[LocalDatabaseHelper.colName] ?? '').toString(),
            ),
          )
          .toList();
    } catch (e) {
      throw 'Failed to fetch sales representatives from local DB: $e';
    }
  }

  @override
  Future<List<String>> getProductionSites() async {
    try {
      final sites = await LocalDatabaseHelper.instance.getSites();
      if (sites.isNotEmpty) {
        return sites.map((s) => s[LocalDatabaseHelper.colCode] as String).toList();
      }

      // Fallback to API if local is empty (e.g., first run)
      final response = await _dio.get('Logistics/production-sites');
      return (response.data as List).map((s) => s.toString()).toList();
    } catch (e) {
      debugPrint('Production Sites: Local fetch failed, falling back to basic list. Error: $e');
      return ['IPL', 'INTERNAL']; // Safe defaults for Innodis
    }
  }

  @override
  Future<List<String>> getLots(String itemCode, String siteCode) async {
    try {
      final lots = await LocalDatabaseHelper.instance.getLotsForItemAndSite(itemCode, siteCode);
      if (lots.isNotEmpty) return lots;

      // Fallback to API
      final response = await _dio.get(
        'Logistics/lots',
        queryParameters: {'itemCode': itemCode, 'siteCode': siteCode},
      );
      return (response.data as List).map((s) => s.toString()).toList();
    } catch (e) {
      debugPrint('Lots: Local fetch failed for $itemCode at $siteCode: $e');
      return [];
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
        'unit': r[LocalDatabaseHelper.colProdStu]?.toString() ?? 'KG',
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
        // Generate new SO number based on type
        final prefix = entry['type'] == 'Cuts' ? 'CUT-' : 'BLK-';
        final existingCount =
            sqflite.Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM ${LocalDatabaseHelper.tableOrders} WHERE ${LocalDatabaseHelper.colOrderNum} LIKE ?',
                ['$prefix$dateStr%'],
              ),
            ) ??
            0;
        entryNo =
            '$prefix$dateStr-${(existingCount + 1).toString().padLeft(4, '0')}';

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

      final List? products = entry['products'] as List?;

      if (products != null && products.isNotEmpty) {
        for (final product in products) {
          final productCode = product['code'];
          final productName = product['name'];
          final scans = product['scans'] as List? ?? [];
          final totalWeight = scans.fold(0.0, (sum, s) => sum + (s['weight'] as num).toDouble());

          // Insert detail line
          await db.insert(LocalDatabaseHelper.tableDetails, {
            LocalDatabaseHelper.colDetSoNum: entryNo,
            LocalDatabaseHelper.colDetItemCode: productCode,
            LocalDatabaseHelper.colDetDescription: productName,
            LocalDatabaseHelper.colDetBarcodeType: 'Variable Weight',
            LocalDatabaseHelper.colDetQuantity: totalWeight,
          });

          // Insert scans
          for (final scan in scans) {
            await db.insert(LocalDatabaseHelper.tableScans, {
              LocalDatabaseHelper.columnSoNumber: entryNo,
              LocalDatabaseHelper.columnProductCode: productCode,
              LocalDatabaseHelper.columnQuantity: scan['weight'],
              LocalDatabaseHelper.columnManufacturedQuantity: scan['weight'],
              LocalDatabaseHelper.columnTimestamp:
                  scan['timestamp'] ?? DateTime.now().toIso8601String(),
              LocalDatabaseHelper.columnSyncId: const Uuid().v4(),
              LocalDatabaseHelper.columnIsSynced: 0,
              LocalDatabaseHelper.columnItemStatus: 'A',
              LocalDatabaseHelper.columnSite: 'INTERNAL',
            });
          }
        }
      } else {
        // Fallback for legacy single-product entries
        final productCode = entry['productCode'] ??
            (entry['type'] == 'Cuts' ? 'PROD-CUT' : 'PROD-BLK');
        final quantity = entry['amountKg'] ?? 0.0;

        await db.insert(LocalDatabaseHelper.tableDetails, {
          LocalDatabaseHelper.colDetSoNum: entryNo,
          LocalDatabaseHelper.colDetItemCode: productCode,
          LocalDatabaseHelper.colDetDescription:
              entry['productName'] ??
              (entry['type'] == 'Cuts' ? 'Internal - Cuts' : 'Internal - Bulk'),
          LocalDatabaseHelper.colDetBarcodeType: 'Variable Weight',
          LocalDatabaseHelper.colDetQuantity: quantity,
        });

        if (entry['scans'] != null && (entry['scans'] as List).isNotEmpty) {
          final scans = entry['scans'] as List;
          for (final scan in scans) {
            await db.insert(LocalDatabaseHelper.tableScans, {
              LocalDatabaseHelper.columnSoNumber: entryNo,
              LocalDatabaseHelper.columnProductCode: scan['productCode'],
              LocalDatabaseHelper.columnQuantity: scan['weight'],
              LocalDatabaseHelper.columnManufacturedQuantity: scan['weight'],
              LocalDatabaseHelper.columnTimestamp:
                  scan['timestamp'] ?? DateTime.now().toIso8601String(),
              LocalDatabaseHelper.columnSyncId: const Uuid().v4(),
              LocalDatabaseHelper.columnIsSynced: 0,
              LocalDatabaseHelper.columnItemStatus: 'A',
              LocalDatabaseHelper.columnSite: 'INTERNAL',
            });
          }
        } else {
          await db.insert(LocalDatabaseHelper.tableScans, {
            LocalDatabaseHelper.columnSoNumber: entryNo,
            LocalDatabaseHelper.columnProductCode: productCode,
            LocalDatabaseHelper.columnQuantity: quantity,
            LocalDatabaseHelper.columnManufacturedQuantity: quantity,
            LocalDatabaseHelper.columnTimestamp: DateTime.now().toIso8601String(),
            LocalDatabaseHelper.columnSyncId: const Uuid().v4(),
            LocalDatabaseHelper.columnIsSynced: 0,
            LocalDatabaseHelper.columnItemStatus: 'A',
            LocalDatabaseHelper.columnSite: 'INTERNAL',
          });
        }
      }

      // Mark order as unsynced if it was previously synced (adding new detail)
      if (existingSo != null && existingSo.isNotEmpty) {
        await db.update(
          LocalDatabaseHelper.tableOrders,
          {LocalDatabaseHelper.columnIsSynced: 0},
          where: '${LocalDatabaseHelper.colOrderNum} = ?',
          whereArgs: [entryNo],
        );
      }

      // NOTE: No optimistic API call here.
      // Cut/Bulk entries are pushed exclusively through the Sync/push pipeline
      // during manual sync. This prevents the dual-write race condition
      // that caused manufactured quantities to double when online.
      debugPrint("Offline-First: Cut/Bulk entry $entryNo saved locally. Will sync via Sync/push.");

      return entryNo;
    } catch (e) {
      throw 'Failed to save Cut/Bulk entry locally: $e';
    }
  }

  // --- SYNC ORCHESTRATION ---

  @override
  Future<void> synchronize({String? siteCode}) async {
    if (_isSyncing) {
      debugPrint("Sync: Operation already in progress. Skipping redundant request.");
      return;
    }
    _isSyncing = true;
    final stopwatch = Stopwatch()..start();
    Map<String, int> counts = {};
    final activeSite = siteCode ?? 'IPL';

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
                  'syncId': s['sync_id'],
                },
              )
              .toList(),
          'shipmentPreparationUpdates': (await LocalDatabaseHelper.instance.getUnsyncedShipmentPreparation()).map((o) => {
            'soNumber': o[LocalDatabaseHelper.colOrderNum],
            'isPreparedForShipment': o[LocalDatabaseHelper.colIsPreparedForShipment] == 1,
          }).toList(),
          'cutBulkEntries': (await Future.wait(
            unsyncedOrders.map((o) async {
              final soNum = o[LocalDatabaseHelper.colOrderNum] as String;
              // Fetch details for item code and amount
              final details = await LocalDatabaseHelper.instance
                  .getReconciledDetails(soNum);
              double amount = 0;
              String? itemCode;
              String? productName;
              if (details.isNotEmpty) {
                amount = (details.first['reconciledProduced'] as num).toDouble();
                itemCode = details.first[LocalDatabaseHelper.colDetItemCode]?.toString();
                productName = details.first[LocalDatabaseHelper.colDetDescription]?.toString();
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
          'preparationStatusUpdates': (await LocalDatabaseHelper.instance.getUnsyncedPreparationStatuses()).map((u) => {
            'soNumber': u[LocalDatabaseHelper.colDetSoNum],
            'itemCode': u[LocalDatabaseHelper.colDetItemCode],
            'isPrepared': u[LocalDatabaseHelper.colDetIsPrepared] == 1,
            'isPreparedForShipment': u[LocalDatabaseHelper.colDetIsValidated] == 1, // Validation status
          }).toList(),
          'deviceId': 'mobile-terminal',
        };

        // Note: Refined sync payload construction
        debugPrint("Sync: Pushing ${unsyncedScans.length} scans and ${unsyncedOrders.length} Cut/Bulk entries to API.");
        
        try {
          await _dio.post('Sync/push', data: payload);
        } on DioException catch (e) {
          final fullUrl = '${_dio.options.baseUrl}${e.requestOptions.path}';
          debugPrint("Sync: Push failed to $fullUrl. Error: ${e.error ?? e.message}");
          rethrow;
        }

        // 1.1 Mark Everything as Synced locally EXCEPT Preparation Statuses (handled after refresh)
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

        // Preparation statuses (Item level) and Shipment statuses (Order level)
        // are marked after refresh to ensure we don't drop dirty flags prematurely.
      }

      // 2. Refresh Mirror Data
      final response = await _dio.get(
        'Sync/refresh',
        queryParameters: {'site': activeSite},
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
      final sites = processedData['sites'] as List<Map<String, dynamic>>;

      counts = {
        'orders': orders.length,
        'details': details.length,
        'customers': customers.length,
        'reps': reps.length,
        'locations': locations.length,
        'products': products.length,
        'sites': sites.length,
      };

      await LocalDatabaseHelper.instance.refreshLogisticsData(
        orders: orders,
        details: details,
        customers: customers,
        reps: reps,
        locations: locations,
        products: products,
        sites: sites,
        lots: processedData['lots'] as List<Map<String, dynamic>>,
      );

      // 3. Mark preparation status updates as synced AFTER refresh
      // This combined with the "Dirty-Aware" refresh prevents stale server data overwrites.
      final updates = (await LocalDatabaseHelper.instance.getUnsyncedPreparationStatuses());
      if (updates.isNotEmpty) {
        await LocalDatabaseHelper.instance.markDetailsAsSynced(updates);
        debugPrint("Sync: ${updates.length} preparation status updates marked as synced after refresh.");
      }

      final shipmentUpdates = (await LocalDatabaseHelper.instance.getUnsyncedShipmentPreparation());
      if (shipmentUpdates.isNotEmpty) {
        await LocalDatabaseHelper.instance.markOrderPreparationAsSynced(shipmentUpdates.map((o) => {
          'soNumber': o[LocalDatabaseHelper.colOrderNum],
        }).toList());
        debugPrint("Sync: ${shipmentUpdates.length} shipment preparation updates marked as synced after refresh.");
      }

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
        debugPrint('Reflection System: Marked ${ids.length} scans as reflected.');
      }

      final duration = stopwatch.elapsedMilliseconds;
      await LocalDatabaseHelper.instance.insertSyncHistory(
        status: 'Success',
        message: 'Sync completed in ${duration}ms',
        site: activeSite,
        counts: counts,
      );
    } catch (e) {
      // Log Failure
      await LocalDatabaseHelper.instance.insertSyncHistory(
        status: 'Failed',
        message: 'Sync error: $e',
        site: activeSite,
        counts: counts.isNotEmpty ? counts : null,
      );
      debugPrint("Sync: Operation failed: $e");
      throw 'Sync failed: $e';
    } finally {
      _isSyncing = false;
      stopwatch.stop();
      debugPrint("Sync: Finished in ${stopwatch.elapsed.inSeconds}s. Updated: $counts");
    }
  }

  @override
  Stream<SyncProgress> synchronizeWithProgress({String? siteCode}) async* {
    if (_isSyncing) {
      debugPrint("Sync (Progress): Operation already in progress. Skipping redundant request.");
      yield SyncProgress.error("Synchronization already in progress.");
      return;
    }
    _isSyncing = true;
    final stopwatch = Stopwatch()..start();
    Map<String, int> counts = {};
    final activeSite = siteCode ?? 'IPL';

    try {
      yield SyncProgress(status: 'Initializing sync...', progress: 0.05);

      // 1. Push Unsynced Work
      yield SyncProgress(status: 'Pushing local changes...', progress: 0.1);
      final unsyncedScans = await LocalDatabaseHelper.instance.getUnsyncedScans();
      final unsyncedOrders = await LocalDatabaseHelper.instance.getUnsyncedInternalOrders();
      final unsyncedStatuses = await LocalDatabaseHelper.instance.getUnsyncedPreparationStatuses();
      final unsyncedShipments = await LocalDatabaseHelper.instance.getUnsyncedShipmentPreparation();

      if (unsyncedScans.isNotEmpty || unsyncedOrders.isNotEmpty || unsyncedStatuses.isNotEmpty || unsyncedShipments.isNotEmpty) {
        final payload = {
          'scans': unsyncedScans.map((s) => {
            'soNumber': s['soNumber'],
            'itemCode': s['productCode'],
            'scanAmountKg': s['quantity'],
            'itemStatus': s['itemStatus'] ?? 'Q',
            'location': s['location'],
            'syncId': s['sync_id'],
          }).toList(),
          'cutBulkEntries': (await Future.wait(unsyncedOrders.map((o) async {
            final soNum = o[LocalDatabaseHelper.colOrderNum] as String;
            final details = await LocalDatabaseHelper.instance.getReconciledDetails(soNum);
            double amount = details.isNotEmpty ? (details.first['reconciledProduced'] as num).toDouble() : 0;
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
          'preparationStatusUpdates': unsyncedStatuses,
          'shipmentPreparationUpdates': unsyncedShipments.map((o) => {
            'soNumber': o[LocalDatabaseHelper.colOrderNum],
            'isPreparedForShipment': o[LocalDatabaseHelper.colIsPreparedForShipment] == 1,
          }).toList(),
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
          'site': activeSite,
          if (lastSync != null) 'since': lastSync,
        },
      );
      
      final rawData = response.data;
      final serverTimestamp = rawData['timestamp'] as String?;

      yield SyncProgress(status: 'Processing data...', progress: 0.6);
      final processedData = await compute(_parseAndSanitizeData, rawData);

      final tables = ['orders', 'details', 'customers', 'reps', 'locations', 'products', 'sites', 'lots'];
      for (var i = 0; i < tables.length; i++) {
        final table = tables[i];
        final data = processedData[table] as List<Map<String, dynamic>>? ?? [];
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
        sites: processedData['sites'] as List<Map<String, dynamic>>,
        lots: processedData['lots'] as List<Map<String, dynamic>>,
      );

      // 3. Mark preparation status updates as synced AFTER refresh
      // We re-fetch from DB to get the current list of what was dirty BEFORE refresh (and preserved)
      if (unsyncedStatuses.isNotEmpty) {
        await LocalDatabaseHelper.instance.markDetailsAsSynced(unsyncedStatuses);
        debugPrint("Sync (Progress): ${unsyncedStatuses.length} preparation status updates marked as synced after refresh.");
      }

      if (unsyncedShipments.isNotEmpty) {
        await LocalDatabaseHelper.instance.markOrderPreparationAsSynced(unsyncedShipments.map((o) => {
          'soNumber': o[LocalDatabaseHelper.colOrderNum],
        }).toList());
        debugPrint("Sync (Progress): ${unsyncedShipments.length} shipment preparation updates marked as synced after refresh.");
      }

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
        final Map<String, dynamic> firstRow = syncedScans.first;
        if (firstRow.containsKey('id')) {
           await LocalDatabaseHelper.instance.marksReflected(syncedScans.map((s) => s['id'] as int).toList());
        }
      }

      final duration = stopwatch.elapsedMilliseconds;
      await LocalDatabaseHelper.instance.insertSyncHistory(
        status: 'Success',
        message: 'Sync completed in ${duration}ms',
        site: activeSite,
        counts: counts,
      );
    } catch (e) {
      await LocalDatabaseHelper.instance.insertSyncHistory(
        status: 'Failed',
        message: 'Sync error: $e',
        site: activeSite,
        counts: counts.isNotEmpty ? counts : null,
      );
      yield SyncProgress.error(e.toString());
    } finally {
      _isSyncing = false;
      stopwatch.stop();
      debugPrint("Sync (Progress): Finished in ${stopwatch.elapsed.inSeconds}s. Updated: $counts");
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
      salesmanName: row['salesmanName'],
      site: row[LocalDatabaseHelper.colSite],
      isClosed: row[LocalDatabaseHelper.colStatus] == 2,
      isEditable: true,
      isPreparedForShipment: row[LocalDatabaseHelper.colIsPreparedForShipment] == 1,
    );
  }

  SalesOrderDetail _mapLocalDetailToEntity(Map<String, dynamic> row) {
    final qty = (row[LocalDatabaseHelper.colDetQuantity] as num?)?.toDouble() ?? 0.0;
    final manufactured = (row[LocalDatabaseHelper.colDetScanned] as num?)?.toDouble() ?? 0.0;
    final remaining =
        (row['reconciledRemaining'] as num?)?.toDouble() ?? (qty - manufactured);

    return SalesOrderDetail(
      soNumber: row[LocalDatabaseHelper.colDetSoNum] ?? '',
      itemCode: row[LocalDatabaseHelper.colDetItemCode] ?? '',
      description: row[LocalDatabaseHelper.colDetDescription] ?? '',
      barcodeType:
          row[LocalDatabaseHelper.colDetBarcodeType] ?? 'Variable Weight',
      quantity: qty,
      remaining: remaining,
      scannedQuantity: manufactured,
      manufacturedQuantity: manufactured, // Fallback for simple mapping
      site: row[LocalDatabaseHelper.colDetSite],
      location: row[LocalDatabaseHelper.colDetLocation],
      lot: row[LocalDatabaseHelper.colDetLot],
      warehouse: row[LocalDatabaseHelper.colDetWarehouse],
      warehouseName: row[LocalDatabaseHelper.colDetWarehouseName],
      locationType: row[LocalDatabaseHelper.colDetLocationType],
      locationTypeName: row[LocalDatabaseHelper.colDetLocationTypeName],
      isPrepared: row[LocalDatabaseHelper.colDetIsPrepared] == 1,
      unit: row[LocalDatabaseHelper.colDetUnit] as String? ?? 'KG',
    );
  }

  @override
  Future<void> updateSalesOrder(SalesOrder order) async {
    // Note: Update logic for Innodis might be different
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Future<void> syncScans(List<Map<String, dynamic>> scans, {String? siteCode}) async {
    try {
      final payload = scans
          .map(
            (s) => {
              'soNumber': s['soNumber'],
              'itemCode': s['itemCode'] ?? s['productCode'],
              'quantity': s['quantity'],
              'manufacturedQuantity': s['manufactured_quantity'] ?? s['quantity'],
              'scanTimestamp': s['timestamp'],
              'site': siteCode ?? s['site'],
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
      final syncId = const Uuid().v4();

      // 1. Map UI payload to SQLite schema
      final localRow = {
        LocalDatabaseHelper.columnSoNumber: scan['soNumber'] ?? '',
        LocalDatabaseHelper.columnProductCode: scan['itemCode'] ?? '',
        LocalDatabaseHelper.columnQuantity: (scan['scanAmountKg'] ?? 0.0).toDouble(),
        LocalDatabaseHelper.columnManufacturedQuantity: (scan['manufacturedQty'] ?? scan['scanAmountKg'] ?? 0.0).toDouble(),
        LocalDatabaseHelper.columnTimestamp: DateTime.now().toIso8601String(),
        LocalDatabaseHelper.columnItemStatus: scan['itemStatus'] ?? 'Q',
        LocalDatabaseHelper.columnLocationCode: scan['location'] ?? '',
        LocalDatabaseHelper.columnSyncId: syncId,
        LocalDatabaseHelper.columnIsSynced: 0,
      };
      // 2. Persist to Local DB IMMEDIATELY (offline-first)
      final id = await LocalDatabaseHelper.instance.insertScan(localRow);
      debugPrint("Offline-First: Scan saved locally with ID $id. Will sync via Sync/push.");
    } catch (e) {
      debugPrint("CRITICAL: Local persistence failed for scan: $e");
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
    final processor = OfflineBarcodeProcessor();
    final result = await processor.processBarcode(barcode);

    if (result != null) {
      return {
        'productCode': result.itemCode,
        'weight': result.weight,
        'batchId': result.lotNumber,
      };
    }

    return null;
  }

  @override
  Future<List<LocationLookup>> getTargetLocations(String site, String itemCode) async {
    // 1. Read from SQLite first (already synced via refreshLogisticsData)
    final localLocations = await getLocationLookups(site);
    if (localLocations.isNotEmpty) {
      debugPrint("Target locations loaded from SQLite cache (${localLocations.length} items)");
      return localLocations;
    }

    // 2. Fallback: API call only if SQLite is empty (first run before sync)
    try {
      debugPrint("SQLite empty — falling back to API for target locations");
      final prefs = await SharedPreferences.getInstance();
      var baseUrl = prefs.getString('api_base_url') ?? 'http://10.0.2.2:5042';

      final response = await _dio.get(
        '$baseUrl/api/logistics/target-locations',
        queryParameters: {'site': site, 'itemCode': itemCode},
      );

      final data = response.data as List;
      return data.map((e) => LocationLookup(
        site: e['site'] as String?,
        location: e['location'] as String?,
        warehouse: e['warehouse'] as String?,
        warehouseName: e['warehouseName'] as String?,
        locationType: e['locationType'] as String?,
        locationTypeName: e['locationTypeName'] as String?,
      )).toList();
    } catch (e) {
      debugPrint("Failed to fetch target locations from API: $e");
      return [];
    }
  }

  @override
  Future<void> updateItemPreparationStatus({
    required String soNumber,
    required String itemCode,
    required bool isPrepared,
    bool isValidation = false,
  }) async {
    try {
      final db = await LocalDatabaseHelper.instance.database;
      final column = isValidation 
          ? LocalDatabaseHelper.colDetIsValidated 
          : LocalDatabaseHelper.colDetIsPrepared;
          
      await db.update(
        LocalDatabaseHelper.tableDetails,
        {
          column: isPrepared ? 1 : 0,
          LocalDatabaseHelper.columnIsSynced: 0,
        },
        where: '${LocalDatabaseHelper.colDetSoNum} = ? AND ${LocalDatabaseHelper.colDetItemCode} = ?',
        whereArgs: [soNumber, itemCode],
      );
      
      // Immediate Sync with server
      try {
        final endpoint = isValidation
            ? 'Logistics/update-validation-status' // New endpoint for validation
            : 'Logistics/update-preparation-status';
            
        await _dio.post(
          '$endpoint/$soNumber/$itemCode?isPrepared=$isPrepared',
        );
        
        await db.update(
          LocalDatabaseHelper.tableDetails,
          {LocalDatabaseHelper.columnIsSynced: 1},
          where: '${LocalDatabaseHelper.colDetSoNum} = ? AND ${LocalDatabaseHelper.colDetItemCode} = ?',
          whereArgs: [soNumber, itemCode],
        );
      } catch (e) {
        debugPrint("Failed to sync item status to server (immediate): $e");
      }
    } catch (e) {
      throw 'Failed to update item status: $e';
    }
  }

  @override
  Future<void> updateShipmentPreparationStatus({
    required String soNumber,
    required bool isPrepared,
  }) async {
    try {
      final db = await LocalDatabaseHelper.instance.database;
      await db.update(
        LocalDatabaseHelper.tableOrders,
        {
          LocalDatabaseHelper.colIsPreparedForShipment: isPrepared ? 1 : 0,
          LocalDatabaseHelper.columnIsSynced: 0,
        },
        where: '${LocalDatabaseHelper.colOrderNum} = ?',
        whereArgs: [soNumber],
      );
    } catch (e) {
      throw 'Failed to update shipment preparation status: $e';
    }
  }

  @override
  Future<Map<String, dynamic>?> getProductByBarcode(String barcode) async {
    final db = await LocalDatabaseHelper.instance.database;

    // Case 1 & 2: Prefix 2 or 0 (Identification by first 6 digits)
    if (barcode.startsWith('2') || barcode.startsWith('0')) {
      final prefix = barcode.substring(0, 6);
      final results = await db.query(
        LocalDatabaseHelper.tableProducts,
        where: '${LocalDatabaseHelper.colProdBarcode} LIKE ?',
        whereArgs: ['$prefix%'],
      );
      if (results.isNotEmpty) return results.first;
    }

    // Case 3 & 4: Prefix 6 (Identification by full barcode)
    if (barcode.startsWith('6')) {
      final results = await db.query(
        LocalDatabaseHelper.tableProducts,
        where: '${LocalDatabaseHelper.colProdBarcode} = ?',
        whereArgs: [barcode],
      );
      if (results.isNotEmpty) return results.first;
    }

    // Final fallback to exact match on item code if barcode fails
    final fallbackCode = await db.query(
      LocalDatabaseHelper.tableProducts,
      where: '${LocalDatabaseHelper.colProdCode} = ?',
      whereArgs: [barcode],
    );
    if (fallbackCode.isNotEmpty) return fallbackCode.first;

    return null;
  }

  @override
  Future<List<Site>> getFilteredSites({required DateTime date}) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final maps = await LocalDatabaseHelper.instance.getFilteredSites(dateStr);
    return maps.map((m) => Site(
      code: m[LocalDatabaseHelper.colCode]?.toString() ?? '',
      name: m[LocalDatabaseHelper.colName]?.toString() ?? '',
    )).toList();
  }

  @override
  Future<List<SalesRep>> getFilteredSalesReps({
    required DateTime date,
    String? siteCode,
  }) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final maps = await LocalDatabaseHelper.instance.getFilteredSalesReps(dateStr, siteCode);
    return maps.map((m) => SalesRep(
      code: m[LocalDatabaseHelper.colCode]?.toString() ?? '',
      name: m[LocalDatabaseHelper.colName]?.toString() ?? '',
    )).toList();
  }

  @override
  Future<List<Customer>> getFilteredCustomers({
    required DateTime date,
    String? siteCode,
    String? salesmanCode,
  }) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final maps = await LocalDatabaseHelper.instance.getFilteredCustomers(
      dateStr,
      siteCode,
      salesmanCode,
    );
    return maps.map((m) => Customer(
      code: m[LocalDatabaseHelper.colCode]?.toString() ?? '',
      name: m[LocalDatabaseHelper.colName]?.toString() ?? '',
    )).toList();
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

  final sites = (data['sites'] as List? ?? [])
      .map<Map<String, dynamic>>((j) => LookupDto.fromJson(j).toSqlMap())
      .toList();

  final lots = (data['lots'] as List? ?? [])
      .map<Map<String, dynamic>>((j) => LotDto.fromJson(j).toSqlMap())
      .toList();

  return {
    'orders': orders,
    'details': details,
    'customers': customers,
    'reps': reps,
    'locations': locations,
    'products': products,
    'sites': sites,
    'lots': lots,
  };
}
