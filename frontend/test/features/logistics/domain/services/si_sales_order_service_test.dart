import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/si_sales_order_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SISalesOrderService service;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);

    // Setup tbl_si_sales_orders matching v83 schema
    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableSiSalesOrders} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        orderNumber TEXT,
        customerCode TEXT NOT NULL,
        customerName TEXT NOT NULL,
        totalAmount REAL NOT NULL,
        status TEXT NOT NULL,
        deliveryDate TEXT,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableSiSalesOrderDetails} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        orderId INTEGER NOT NULL,
        productCode TEXT NOT NULL,
        productName TEXT NOT NULL,
        quantity REAL NOT NULL,
        basePrice REAL NOT NULL,
        discountAmount REAL NOT NULL,
        vatAmount REAL NOT NULL,
        total REAL NOT NULL,
        salesUnit TEXT,
        lotNumber TEXT,
        warehouse TEXT,
        location TEXT,
        cce0 TEXT,
        taxRule TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${LocalDatabaseHelper.tableSalesInvoiceCustomers} (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        status TEXT,
        taxRule TEXT,
        paymentTerm TEXT,
        outstandingBalance REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${LocalDatabaseHelper.tableSalesInvoiceProducts} (
        sku TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        stockQty REAL,
        warehouse TEXT,
        salesUnit TEXT,
        isSynced INTEGER NOT NULL DEFAULT 1,
        cce0 TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} (
        itemCode TEXT,
        itemName TEXT,
        lotNumber TEXT,
        warehouse TEXT,
        location TEXT,
        totalQty REAL,
        salesUnit TEXT,
        isSynced INTEGER NOT NULL DEFAULT 1
      )
    ''');

    service = SISalesOrderService(dbProvider: () async => db);
  });

  tearDown(() async {
    await db.close();
  });

  group('SISalesOrderService Delivery Date Tests', () {
    test('saveSalesOrder correctly persists deliveryDate', () async {
      const targetDeliveryDate = '2026-09-25T00:00:00.000';
      final customer = {'code': 'CUST001', 'name': 'Acme Corp'};
      final item = CartItem(
        product: SalesInvoiceProductModel(
          sku: 'SKU01',
          name: 'Product A',
          stockQty: 10,
          warehouse: 'WH1',
          salesUnit: 'EA',
        ),
        quantity: 5,
        basePrice: 100,
      );

      await service.saveSalesOrder(
        customer: customer,
        items: [item],
        totalAmount: 500,
        deliveryDate: targetDeliveryDate,
      );

      final orders = await service.getSalesOrders();
      expect(orders.length, equals(1));
      expect(orders.first['customerCode'], equals('CUST001'));
      expect(orders.first['deliveryDate'], equals(targetDeliveryDate));
      expect(orders.first['status'], equals('Open'));
    });

    test('saveSalesOrder with empty deliveryDate defaults to current ISO string', () async {
      final customer = {'code': 'CUST002', 'name': 'Beta Ltd'};

      await service.saveSalesOrder(
        customer: customer,
        items: [],
        totalAmount: 0,
        deliveryDate: '',
      );

      final orders = await service.getSalesOrders();
      expect(orders.length, equals(1));
      expect(orders.first['deliveryDate'], isNotEmpty);
      expect(DateTime.tryParse(orders.first['deliveryDate']), isNotNull);
    });

    test('updateDeliveryDate updates delivery date for an open order', () async {
      await db.insert(LocalDatabaseHelper.tableSiSalesOrders, {
        'customerCode': 'CUST003',
        'customerName': 'Gamma Inc',
        'totalAmount': 250.0,
        'status': 'Open',
        'deliveryDate': '2026-09-20T00:00:00.000',
        'createdAt': DateTime.now().toIso8601String(),
      });

      final ordersBefore = await service.getSalesOrders();
      final orderId = ordersBefore.first['id'] as int;

      const updatedDate = '2026-09-28T00:00:00.000';
      await service.updateDeliveryDate(orderId, updatedDate);

      final ordersAfter = await service.getSalesOrders();
      expect(ordersAfter.first['deliveryDate'], equals(updatedDate));
    });

    test('legacy orders with NULL deliveryDate are handled gracefully', () async {
      await db.insert(LocalDatabaseHelper.tableSiSalesOrders, {
        'customerCode': 'CUST004',
        'customerName': 'Legacy Client',
        'totalAmount': 100.0,
        'status': 'Open',
        'deliveryDate': null,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final orders = await service.getSalesOrders();
      expect(orders.length, equals(1));
      expect(orders.first['deliveryDate'], isNull);
    });
  });

  group('SalesInvoiceCartCubit Delivery Date State Tests', () {
    test('clearCart with SI_SALES_ORDER initializes deliveryDate to today', () {
      final cubit = SalesInvoiceCartCubit();
      cubit.clearCart(transactionType: 'SI_SALES_ORDER');

      final now = DateTime.now();
      expect(cubit.state.transactionType, equals('SI_SALES_ORDER'));
      expect(cubit.state.deliveryDate, isNotNull);
      expect(cubit.state.deliveryDate!.year, equals(now.year));
      expect(cubit.state.deliveryDate!.month, equals(now.month));
      expect(cubit.state.deliveryDate!.day, equals(now.day));
    });

    test('setDeliveryDate updates deliveryDate in state', () {
      final cubit = SalesInvoiceCartCubit();
      final futureDate = DateTime(2026, 10, 15);
      cubit.setDeliveryDate(futureDate);

      expect(cubit.state.deliveryDate, equals(futureDate));
    });

    test('changing customer preserves selected deliveryDate for SI_SALES_ORDER', () {
      final cubit = SalesInvoiceCartCubit();
      cubit.setTransactionType('SI_SALES_ORDER');
      final futureDate = DateTime(2026, 11, 20);
      cubit.setDeliveryDate(futureDate);

      cubit.setCustomer({'code': 'C99', 'name': 'Customer 99'});

      expect(cubit.state.customer?['code'], equals('C99'));
      expect(cubit.state.deliveryDate, equals(futureDate));
    });
  });

  group('Sales Order Stock Limit Independence Tests', () {
    test('saveSalesOrder successfully saves items with quantity exceeding stockQty and empty lot', () async {
      final customer = {'code': 'CUST_ADV', 'name': 'Advance Wholesale'};
      // Item has 0 stock on hand, but customer places order for 500 units
      final zeroStockItem = CartItem(
        product: SalesInvoiceProductModel(
          sku: 'OUT_OF_STOCK_SKU',
          name: 'Manufactured On Demand Item',
          stockQty: 0,
          warehouse: 'WH1',
          salesUnit: 'BOX',
        ),
        quantity: 500,
        lotNumber: '', // Unassigned / not yet manufactured
        warehouse: 'WH1',
        location: 'A1-B1',
        basePrice: 45.0,
      );

      await service.saveSalesOrder(
        customer: customer,
        items: [zeroStockItem],
        totalAmount: 22500.0,
        deliveryDate: '2026-10-01T00:00:00.000',
      );

      final orders = await service.getSalesOrders();
      expect(orders.length, equals(1));
      final orderId = orders.first['id'] as int;

      final details = await service.getSalesOrderDetails(orderId);
      expect(details.length, equals(1));
      expect(details.first['productCode'], equals('OUT_OF_STOCK_SKU'));
      expect(details.first['quantity'], equals(500.0));
      expect(details.first['lotNumber'], equals(''));
      expect(details.first['total'], equals(22500.0));
    });
  });

  group('SISalesOrderService Hardcoded Sage X3 Order Tests', () {
    test('ensureHardcodedSalesOrderSeeded creates all 3 Sage X3 orders with full details', () async {
      await service.ensureHardcodedSalesOrderSeeded();

      final orders = await service.getSalesOrders();
      expect(orders.length, equals(3));

      // 1. Verify CGDSO250800001
      final order1 = orders.firstWhere((o) => o['orderNumber'] == 'CGDSO250800001');
      expect(order1['customerCode'], equals('WIN001'));
      expect(order1['customerName'], equals("WINNER'S BEL AIR"));
      expect(order1['totalAmount'], equals(9577.96));
      expect(order1['status'], equals('Open'));

      final details1 = await service.getSalesOrderDetails(order1['id'] as int);
      expect(details1.length, equals(5));
      expect(details1.any((d) => d['productCode'] == '8101' && d['quantity'] == 16.0), isTrue);

      // 2. Verify CGDSO250800002
      final order2 = orders.firstWhere((o) => o['orderNumber'] == 'CGDSO250800002');
      expect(order2['customerCode'], equals('WIN006'));
      expect(order2['customerName'], equals("WINNER'S FLACQ"));
      expect(order2['totalAmount'], equals(71954.66));
      expect(order2['status'], equals('Open'));

      final details2 = await service.getSalesOrderDetails(order2['id'] as int);
      expect(details2.length, equals(18));
      expect(details2.any((d) => d['productCode'] == '6243' && d['quantity'] == 12.0), isTrue);
      expect(details2.any((d) => d['productCode'] == '721401' && d['quantity'] == 200.0), isTrue);

      // 3. Verify CGDSO250800006
      final order3 = orders.firstWhere((o) => o['orderNumber'] == 'CGDSO250800006');
      expect(order3['customerCode'], equals('SDP028'));
      expect(order3['customerName'], equals('DREAM PRICE - TRIOLET EXPRESS'));
      expect(order3['totalAmount'], equals(125946.62));
      expect(order3['status'], equals('Open'));

      final details3 = await service.getSalesOrderDetails(order3['id'] as int);
      expect(details3.length, equals(19));
      expect(details3.any((d) => d['productCode'] == '624251' && d['quantity'] == 60.0), isTrue);
      expect(details3.any((d) => d['productCode'] == '721401' && d['quantity'] == 1000.0), isTrue);
    });

    test('ensureHardcodedSalesOrderSeeded is idempotent and does not create duplicate orders', () async {
      await service.ensureHardcodedSalesOrderSeeded();
      await service.ensureHardcodedSalesOrderSeeded();
      await service.ensureHardcodedSalesOrderSeeded();

      final orders = await service.getSalesOrders();
      expect(orders.length, equals(3));
    });

    test('saveSalesOrder persists custom orderNumber and falls back to auto-generated', () async {
      final customer = {'code': 'CUST_X', 'name': 'Test Client'};
      final item = CartItem(
        product: SalesInvoiceProductModel(sku: 'SKU_X', name: 'Item X', stockQty: 10, warehouse: 'WH1', salesUnit: 'EA'),
        quantity: 2,
        basePrice: 50,
      );

      // Custom order number
      await service.saveSalesOrder(
        customer: customer,
        items: [item],
        totalAmount: 100.0,
        deliveryDate: '2026-10-10',
        orderNumber: 'CUSTOM-SO-999',
      );

      // Default auto-generated order number
      await service.saveSalesOrder(
        customer: customer,
        items: [item],
        totalAmount: 100.0,
        deliveryDate: '2026-10-10',
      );

      final orders = await service.getSalesOrders();
      expect(orders.length, equals(2));

      final customOrder = orders.firstWhere((o) => o['orderNumber'] == 'CUSTOM-SO-999');
      expect(customOrder['customerCode'], equals('CUST_X'));

      final autoOrder = orders.firstWhere((o) => (o['orderNumber'] as String).startsWith('SO-'));
      expect(autoOrder['customerCode'], equals('CUST_X'));
    });
  });
}

