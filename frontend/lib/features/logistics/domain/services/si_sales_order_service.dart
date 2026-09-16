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

  static const String hardcodedOrderNumber = 'CGDSO250800001';
  static const String hardcodedCustomerCode = 'WIN001';
  static const String hardcodedCustomerName = "WINNER'S BEL AIR";

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

  Future<List<Map<String, dynamic>>> getSalesOrders() async {
    final db = await _getDb();
    final List<Map<String, dynamic>> maps = await db.query(
      LocalDatabaseHelper.tableSiSalesOrders,
      orderBy: 'createdAt DESC',
    );
    return maps;
  }

  Future<List<Map<String, dynamic>>> getSalesOrderDetails(int orderId) async {
    final db = await _getDb();
    final List<Map<String, dynamic>> maps = await db.query(
      LocalDatabaseHelper.tableSiSalesOrderDetails,
      where: 'orderId = ?',
      whereArgs: [orderId],
    );
    return maps;
  }

  Future<void> markOrderAsConverted(int orderId) async {
    final db = await _getDb();
    await db.update(
      LocalDatabaseHelper.tableSiSalesOrders,
      {'status': 'Converted'},
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  Future<void> updateDeliveryDate(int orderId, String deliveryDate) async {
    final db = await _getDb();
    await db.update(
      LocalDatabaseHelper.tableSiSalesOrders,
      {'deliveryDate': deliveryDate},
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  /// Seeds the hardcoded Sage X3 Sales Order (CGDSO250800001) for WINNER'S BEL AIR
  /// with 5 products, and ensures customer/product records exist in master tables.
  Future<void> ensureHardcodedSalesOrderSeeded() async {
    final db = await _getDb();

    // Check if already seeded
    final existing = await db.query(
      LocalDatabaseHelper.tableSiSalesOrders,
      where: 'orderNumber = ?',
      whereArgs: [hardcodedOrderNumber],
      limit: 1,
    );

    if (existing.isNotEmpty) return;

    await db.transaction((txn) async {
      // 1. Insert Master Order Header
      final orderId = await txn.insert(
        LocalDatabaseHelper.tableSiSalesOrders,
        {
          'orderNumber': hardcodedOrderNumber,
          'customerCode': hardcodedCustomerCode,
          'customerName': hardcodedCustomerName,
          'totalAmount': 9577.96,
          'status': 'Open',
          'deliveryDate': '2025-08-21T00:00:00.000',
          'createdAt': '2025-08-21T10:30:00.000',
        },
      );

      // 2. Insert 5 Detailed Line Items from Sage X3
      final lineItems = [
        {
          'orderId': orderId,
          'productCode': '8101',
          'productName': 'Barilla Macaroni 500g',
          'quantity': 16.0,
          'basePrice': 75.0,
          'discountAmount': 0.0,
          'vatAmount': 180.0,
          'total': 1380.0,
          'salesUnit': 'EA',
          'lotNumber': 'LOT-BAR-8101',
          'warehouse': 'CGD',
          'location': 'A-01',
          'cce0': '',
          'taxRule': 'VATR',
        },
        {
          'orderId': orderId,
          'productCode': '620410',
          'productName': 'Lorenz Naturels Sal&Pep 100g',
          'quantity': 25.0,
          'basePrice': 77.74,
          'discountAmount': 0.0,
          'vatAmount': 291.56,
          'total': 2235.29,
          'salesUnit': 'EA',
          'lotNumber': 'LOT-LOR-620410',
          'warehouse': 'CGD',
          'location': 'A-02',
          'cce0': '',
          'taxRule': 'VATR',
        },
        {
          'orderId': orderId,
          'productCode': '624050',
          'productName': 'EVERFRESH UHT MILK 1L LOWFATX6',
          'quantity': 6.0,
          'basePrice': 324.0,
          'discountAmount': 0.0,
          'vatAmount': 0.0,
          'total': 1944.0,
          'salesUnit': 'EA',
          'lotNumber': 'LOT-EVR-624050',
          'warehouse': 'CGD',
          'location': 'B-01',
          'cce0': '',
          'taxRule': 'EXEMPT',
        },
        {
          'orderId': orderId,
          'productCode': '624004',
          'productName': 'Twin Cows UHT FC 1L',
          'quantity': 15.0,
          'basePrice': 61.25,
          'discountAmount': 0.0,
          'vatAmount': 0.0,
          'total': 918.75,
          'salesUnit': 'EA',
          'lotNumber': 'LOT-TC-624004',
          'warehouse': 'CGD',
          'location': 'B-02',
          'cce0': '',
          'taxRule': 'EXEMPT',
        },
        {
          'orderId': orderId,
          'productCode': '6251',
          'productName': 'Twin Cows IFCMP 1Kg',
          'quantity': 10.0,
          'basePrice': 309.992,
          'discountAmount': 0.0,
          'vatAmount': 0.0,
          'total': 3099.92,
          'salesUnit': 'EA',
          'lotNumber': 'LOT-TC-6251',
          'warehouse': 'CGD',
          'location': 'B-03',
          'cce0': '',
          'taxRule': 'EXEMPT',
        },
      ];

      for (final item in lineItems) {
        await txn.insert(
          LocalDatabaseHelper.tableSiSalesOrderDetails,
          item,
        );
      }

      // 3. Ensure Customer Exists in Master (for seamless order conversion)
      try {
        final custExists = await txn.query(
          LocalDatabaseHelper.tableSalesInvoiceCustomers,
          where: 'code = ?',
          whereArgs: [hardcodedCustomerCode],
          limit: 1,
        );
        if (custExists.isEmpty) {
          await txn.insert(
            LocalDatabaseHelper.tableSalesInvoiceCustomers,
            {
              'code': hardcodedCustomerCode,
              'name': hardcodedCustomerName,
              'status': '1',
              'taxRule': 'VATR',
              'paymentTerm': '30 Days',
              'outstandingBalance': 0.0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      } catch (_) {}

      // 4. Ensure Products & Stock Records Exist in Master
      try {
        for (final item in lineItems) {
          final sku = item['productCode'] as String;
          final name = item['productName'] as String;
          final unit = item['salesUnit'] as String;

          await txn.insert(
            LocalDatabaseHelper.tableSalesInvoiceProducts,
            {
              LocalDatabaseHelper.colSiProdSku: sku,
              LocalDatabaseHelper.colSiProdName: name,
              LocalDatabaseHelper.colSiProdStockQty: 100.0,
              LocalDatabaseHelper.colSiProdWarehouse: 'CGD',
              LocalDatabaseHelper.colSiProdSalesUnit: unit,
              LocalDatabaseHelper.colSiProdIsSynced: 1,
              'cce0': '',
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );

          await txn.insert(
            LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
            {
              'itemCode': sku,
              'itemName': name,
              'lotNumber': item['lotNumber'],
              'warehouse': 'CGD',
              'location': item['location'],
              'totalQty': 100.0,
              'salesUnit': unit,
              'isSynced': 1,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      } catch (_) {}
    });
  }
}
