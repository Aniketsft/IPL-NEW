import 'package:enterprise_auth_mobile/core/secure_storage_service.dart';
import '../../data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'package:sqflite/sqflite.dart';

class SISalesOrderService {
  final LocalDatabaseHelper _dbHelper;
  final Future<Database> Function()? _dbProvider;

  SISalesOrderService({
    LocalDatabaseHelper? dbHelper,
    Future<Database> Function()? dbProvider,
  })  : _dbHelper = dbHelper ?? LocalDatabaseHelper.instance,
        _dbProvider = dbProvider;

  Future<Database> _getDb() async {
    final provider = _dbProvider;
    if (provider != null) return await provider();
    return await _dbHelper.database;
  }

  Future<void> saveSalesOrder({
    required Map<String, dynamic> customer,
    required List<CartItem> items,
    required double totalAmount,
    required String deliveryDate,
    String? orderNumber,
  }) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      final effectiveOrderNumber = (orderNumber != null && orderNumber.trim().isNotEmpty)
          ? orderNumber.trim()
          : 'SO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

      // Insert Order
      final orderId = await txn.insert(
        LocalDatabaseHelper.tableSiSalesOrders,
        {
          'orderNumber': effectiveOrderNumber,
          'customerCode': customer['code'] ?? '',
          'customerName': customer['name'] ?? '',
          'totalAmount': totalAmount,
          'status': 'Open',
          'deliveryDate': deliveryDate.isNotEmpty ? deliveryDate : DateTime.now().toIso8601String(),
          'createdAt': DateTime.now().toIso8601String(),
        },
      );

      // Insert Details
      for (final item in items) {
        await txn.insert(
          LocalDatabaseHelper.tableSiSalesOrderDetails,
          {
            'orderId': orderId,
            'productCode': item.product.sku,
            'productName': item.product.name,
            'quantity': item.quantity,
            'basePrice': item.basePrice,
            'discountAmount': item.discountAmount,
            'vatAmount': item.vatAmount,
            'total': item.total,
            'salesUnit': item.product.salesUnit,
            'lotNumber': item.lotNumber,
            'warehouse': item.warehouse,
            'location': item.location,
            'cce0': item.product.cce0,
            'taxRule': item.taxRule,
          },
        );
      }
    });
  }

  /// Queries real Sage X3 orders from tbl_sales_orders (tableOrders) joined with
  /// tbl_sales_order_details (tableDetails), filtered strictly by customerCode and user site (SCG).
  /// Also includes locally created SI sales orders for seamless offline-first experience.
  Future<List<Map<String, dynamic>>> getSalesOrders({
    String? customerCode,
    String? siteCode,
  }) async {
    final db = await _getDb();
    final cleanCustCode = customerCode?.trim();

    // Strict single site code resolution from user session/secure storage
    final effectiveSite = (siteCode != null && siteCode.trim().isNotEmpty)
        ? siteCode.trim()
        : ((await SecureStorageService().getSiteCode()) ?? '').trim();

    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (cleanCustCode != null && cleanCustCode.isNotEmpty) {
      whereClauses.add('UPPER(TRIM(o.customerCode)) = ?');
      whereArgs.add(cleanCustCode.toUpperCase());
    }

    if (effectiveSite.isNotEmpty && effectiveSite != 'ALL') {
      whereClauses.add('UPPER(TRIM(o.site)) = ?');
      whereArgs.add(effectiveSite.toUpperCase());
    }

    final whereStr = whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' AND ')}' : '';

    final query = '''
      SELECT 
        o.id,
        o.sohNum,
        o.sohNum AS orderNumber,
        o.poNo,
        o.orderDate,
        COALESCE(NULLIF(o.orderDate, ''), o.deliveryDate) AS createdAt,
        o.deliveryDate,
        o.customerCode,
        o.customerName,
        o.rep0,
        o.rep1,
        o.salesman,
        o.site,
        CASE 
          WHEN o.status = 2 THEN 'Converted'
          ELSE 'Open'
        END AS status,
        o.source,
        COUNT(d.id) AS itemCount,
        COALESCE(SUM(d.quantity), 0.0) AS totalQuantity
      FROM ${LocalDatabaseHelper.tableOrders} o
      LEFT JOIN ${LocalDatabaseHelper.tableDetails} d ON o.sohNum = d.soNumber
      $whereStr
      GROUP BY o.sohNum
      ORDER BY o.orderDate DESC, o.id DESC
    ''';

    final List<Map<String, dynamic>> rawOrders = await db.rawQuery(query, whereArgs);
    final List<Map<String, dynamic>> ordersList = [];

    for (final row in rawOrders) {
      final orderMap = Map<String, dynamic>.from(row);
      final soNum = orderMap['sohNum']?.toString() ?? '';

      // Compute total order value by looking up base prices from tbl_price_lists
      final details = await db.query(
        LocalDatabaseHelper.tableDetails,
        where: 'UPPER(TRIM(soNumber)) = ?',
        whereArgs: [soNum.toUpperCase()],
      );

      double calculatedTotal = 0.0;
      for (final det in details) {
        final itm = det['itemCode']?.toString() ?? '';
        final qty = (det['quantity'] as num?)?.toDouble() ?? 0.0;
        final rawNetPrice = (det['netPrice'] as num?)?.toDouble();
        final rawIsFoc = (det['isFoc'] == 1 || det['isFoc'] == true);

        // Lookup base price from tbl_price_lists
        final priceRows = await db.rawQuery('''
          SELECT basePrice FROM ${LocalDatabaseHelper.tablePriceLists}
          WHERE matchKey2 = ? OR matchKey1 = ?
          ORDER BY priority ASC, basePrice DESC
          LIMIT 1
        ''', [itm, itm]);
        final catalogBasePrice = priceRows.isNotEmpty
            ? (priceRows.first['basePrice'] as num?)?.toDouble() ?? 0.0
            : 0.0;

        final effectivePrice = (rawNetPrice != null && rawNetPrice > 0.0)
            ? rawNetPrice
            : catalogBasePrice;

        // Skip only if it's explicitly FOC AND has no price
        if (rawIsFoc && effectivePrice == 0.0) {
          continue;
        }

        calculatedTotal += (qty * effectivePrice);
      }

      orderMap['totalAmount'] = calculatedTotal;
      ordersList.add(orderMap);
    }

    // Also include locally created SI sales orders if present
    try {
      final localWhereClauses = <String>[];
      final localWhereArgs = <dynamic>[];
      if (cleanCustCode != null && cleanCustCode.isNotEmpty) {
        localWhereClauses.add('UPPER(TRIM(customerCode)) = ?');
        localWhereArgs.add(cleanCustCode.toUpperCase());
      }
      final localSiOrders = await db.query(
        LocalDatabaseHelper.tableSiSalesOrders,
        where: localWhereClauses.isNotEmpty ? localWhereClauses.join(' AND ') : null,
        whereArgs: localWhereArgs.isNotEmpty ? localWhereArgs : null,
        orderBy: 'createdAt DESC',
      );

      for (final localOrder in localSiOrders) {
        final ordNum = localOrder['orderNumber']?.toString() ?? '';
        if (!ordersList.any((o) => o['sohNum'] == ordNum || o['orderNumber'] == ordNum)) {
          ordersList.add(Map<String, dynamic>.from(localOrder));
        }
      }
    } catch (_) {}

    return ordersList;
  }

  /// Retrieves order line item details by order number (sohNum) or integer ID.
  /// Seamlessly bridges real Sage X3 tbl_sales_order_details with CartItem schema.
  Future<List<Map<String, dynamic>>> getSalesOrderDetails(dynamic identifier) async {
    final db = await _getDb();
    String targetSoNumber = '';
    int? targetOrderId;

    if (identifier is int) {
      targetOrderId = identifier;
      // Check if it exists in local tableSiSalesOrders
      final localHeader = await db.query(
        LocalDatabaseHelper.tableSiSalesOrders,
        columns: ['orderNumber'],
        where: 'id = ?',
        whereArgs: [identifier],
        limit: 1,
      );
      if (localHeader.isNotEmpty && localHeader.first['orderNumber'] != null) {
        targetSoNumber = localHeader.first['orderNumber']!.toString();
      } else {
        final realHeader = await db.query(
          LocalDatabaseHelper.tableOrders,
          columns: ['sohNum'],
          where: 'id = ?',
          whereArgs: [identifier],
          limit: 1,
        );
        if (realHeader.isNotEmpty && realHeader.first['sohNum'] != null) {
          targetSoNumber = realHeader.first['sohNum']!.toString();
        }
      }
    } else if (identifier is String) {
      targetSoNumber = identifier.trim();
    }

    // 1. First attempt: check real tbl_sales_order_details
    if (targetSoNumber.isNotEmpty) {
      final realDetails = await db.query(
        LocalDatabaseHelper.tableDetails,
        where: 'UPPER(TRIM(soNumber)) = ?',
        whereArgs: [targetSoNumber.toUpperCase()],
      );

      if (realDetails.isNotEmpty) {
        final mappedList = <Map<String, dynamic>>[];
        for (final row in realDetails) {
          final itm = row['itemCode']?.toString() ?? '';
          final qty = (row['quantity'] as num?)?.toDouble() ?? 0.0;
          final rawIsFoc = row['isFoc'] == 1 || row['isFoc'] == true;
          final rawNetPrice = (row['netPrice'] as num?)?.toDouble();

          // Lookup base price from tbl_price_lists
          final priceRows = await db.rawQuery('''
            SELECT basePrice FROM ${LocalDatabaseHelper.tablePriceLists}
            WHERE matchKey2 = ? OR matchKey1 = ?
            ORDER BY priority ASC, basePrice DESC
            LIMIT 1
          ''', [itm, itm]);

          final catalogBasePrice = priceRows.isNotEmpty
              ? (priceRows.first['basePrice'] as num?)?.toDouble() ?? 0.0
              : 0.0;

          // If rawNetPrice > 0, use it. Else fall back to price list catalog price.
          final effectiveBasePrice = (rawNetPrice != null && rawNetPrice > 0.0)
              ? rawNetPrice
              : catalogBasePrice;

          // An item is truly FOC only if it has 0 price AND was flagged as FOC
          final isFoc = rawIsFoc && effectiveBasePrice == 0.0;

          mappedList.add({
            'orderId': row['id'],
            'productCode': itm,
            'productName': row['description'] ?? itm,
            'quantity': qty,
            'basePrice': isFoc ? 0.0 : effectiveBasePrice,
            'netPrice': isFoc ? 0.0 : effectiveBasePrice,
            'isFoc': isFoc ? 1 : 0,
            'hasSpecialDiscount': row['hasSpecialDiscount'] == 1 ? 1 : 0,
            'lineNum': row['lineNum'] ?? 0,
            'discountAmount': 0.0,
            'vatAmount': 0.0,
            'total': qty * (isFoc ? 0.0 : effectiveBasePrice),
            'salesUnit': row['unit'] ?? 'EA',
            'lotNumber': row['lot'] ?? '',
            'warehouse': row['warehouse'] ?? '',
            'location': row['location'] ?? '',
            'cce0': '',
            'taxRule': 'VATR',
          });
        }
        return mappedList;
      }
    }

    // 2. Fallback: check tableSiSalesOrderDetails
    if (targetOrderId != null) {
      final List<Map<String, dynamic>> localMaps = await db.query(
        LocalDatabaseHelper.tableSiSalesOrderDetails,
        where: 'orderId = ?',
        whereArgs: [targetOrderId],
      );
      if (localMaps.isNotEmpty) return localMaps;
    }

    return [];
  }

  Future<void> markOrderAsConverted(dynamic identifier) async {
    final db = await _getDb();
    if (identifier is int) {
      await db.update(
        LocalDatabaseHelper.tableOrders,
        {'status': 2},
        where: 'id = ?',
        whereArgs: [identifier],
      );
      await db.update(
        LocalDatabaseHelper.tableSiSalesOrders,
        {'status': 'Converted'},
        where: 'id = ?',
        whereArgs: [identifier],
      );
    } else if (identifier is String) {
      await db.update(
        LocalDatabaseHelper.tableOrders,
        {'status': 2},
        where: 'sohNum = ?',
        whereArgs: [identifier.trim()],
      );
      await db.update(
        LocalDatabaseHelper.tableSiSalesOrders,
        {'status': 'Converted'},
        where: 'orderNumber = ?',
        whereArgs: [identifier.trim()],
      );
    }
  }

  Future<void> updateDeliveryDate(dynamic identifier, String deliveryDate) async {
    final db = await _getDb();
    if (identifier is int) {
      await db.update(
        LocalDatabaseHelper.tableOrders,
        {'deliveryDate': deliveryDate},
        where: 'id = ?',
        whereArgs: [identifier],
      );
      await db.update(
        LocalDatabaseHelper.tableSiSalesOrders,
        {'deliveryDate': deliveryDate},
        where: 'id = ?',
        whereArgs: [identifier],
      );
    } else if (identifier is String) {
      await db.update(
        LocalDatabaseHelper.tableOrders,
        {'deliveryDate': deliveryDate},
        where: 'sohNum = ?',
        whereArgs: [identifier.trim()],
      );
      await db.update(
        LocalDatabaseHelper.tableSiSalesOrders,
        {'deliveryDate': deliveryDate},
        where: 'orderNumber = ?',
        whereArgs: [identifier.trim()],
      );
    }
  }
}
