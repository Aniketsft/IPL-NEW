import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';
import 'package:enterprise_auth_mobile/core/services/device_info_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/sales_invoice_product_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/models/transaction_config.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/repositories/i_sales_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_cart_cubit.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_event.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _StubHttpAdapter implements HttpClientAdapter {
  ResponseBody Function(RequestOptions options)? handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (handler == null) {
      throw StateError('No handler configured on _StubHttpAdapter');
    }
    return handler!(options);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeNetworkService extends Fake implements NetworkService {
  @override
  final Dio dio;

  _FakeNetworkService(this.dio);
}

class _FakeSalesRepository extends Fake implements ISalesRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late _StubHttpAdapter adapter;
  late Dio dio;
  late SalesInvoiceProductRepository repository;

  Future<void> seedStockRow({
    required String itemCode,
    required String itemName,
    required String lotNumber,
    required String warehouse,
    required String location,
    required String siteCode,
    required String stockStatus,
    required double totalQty,
    String salesUnit = 'EA',
  }) async {
    await db.insert(LocalDatabaseHelper.tableSalesInvoiceItemStockDetails, {
      'itemCode': itemCode,
      'itemName': itemName,
      'lotNumber': lotNumber,
      'warehouse': warehouse,
      'warehouseName': 'Warehouse $warehouse',
      'location': location,
      'locationType': location,
      'totalQty': totalQty,
      'taxLevel': 'TX1',
      'cce0': '',
      'salesUnit': salesUnit,
      'barcode': 'BC-$itemCode',
      'siteCode': siteCode,
      'stockStatus': stockStatus,
      'isSynced': 1,
      'createdAt': '2026-11-18T00:00:00Z',
      'updatedAt': '2026-11-18T00:00:00Z',
      'deviceId': '',
    });
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    adapter = _StubHttpAdapter();
    dio = Dio(BaseOptions(baseUrl: 'https://test.local/api/'))..httpClientAdapter = adapter;
    repository = SalesInvoiceProductRepository(_FakeNetworkService(dio));

    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} (
        itemCode TEXT,
        itemName TEXT,
        lotNumber TEXT,
        warehouse TEXT,
        warehouseName TEXT,
        location TEXT,
        locationType TEXT,
        totalQty REAL,
        taxLevel TEXT,
        cce0 TEXT,
        salesUnit TEXT,
        barcode TEXT DEFAULT "",
        siteCode TEXT DEFAULT "",
        stockStatus TEXT DEFAULT 'A',
        isSynced INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT,
        updatedAt TEXT,
        deviceId TEXT,
        PRIMARY KEY (itemCode, lotNumber, location, warehouse, stockStatus)
      )
    ''');
    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableSalesInvoiceProducts} (
        sku TEXT PRIMARY KEY,
        name TEXT,
        salesUnit TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableSiInvoices} (
        invoiceId TEXT PRIMARY KEY,
        transactionType TEXT,
        isSynced INTEGER DEFAULT 0,
        isReversed INTEGER DEFAULT 0,
        reference TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableSiInvoiceLines} (
        lineId INTEGER PRIMARY KEY AUTOINCREMENT,
        invoiceId TEXT,
        sku TEXT,
        lotNumber TEXT,
        warehouse TEXT,
        location TEXT,
        quantity REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableDeviceLocations} (
        deviceId TEXT PRIMARY KEY,
        deviceName TEXT,
        hardwareModel TEXT,
        hardwareIdentifier TEXT,
        siteCode TEXT,
        warehouseCode TEXT,
        locationCode TEXT,
        hepProfileId TEXT,
        hepApiKey TEXT,
        isLocked INTEGER DEFAULT 1,
        isLicensed INTEGER DEFAULT 1,
        licenseStatus TEXT DEFAULT 'VALID',
        licenseUpdatedAt TEXT,
        licenseUpdatedBy TEXT,
        assignedUserName TEXT,
        isActive INTEGER DEFAULT 1,
        updatedAt TEXT,
        updatedBy TEXT
      )
    ''');
    LocalDatabaseHelper.setTestDatabase(db);
  });

  tearDown(() async {
    LocalDatabaseHelper.setTestDatabase(null);
    await db.close();
  });

  test('strictly isolates products and lots to assigned lorry and single site, ignoring warehouse overrides', () async {
    await DeviceInfoService.instance.setAssignedLocation(
      siteCode: 'SCG',
      warehouseCode: 'N3',
      locationCode: 'N3',
    );

    await seedStockRow(
      itemCode: 'SKU-SCG-N3',
      itemName: 'Item on SCG N3',
      lotNumber: 'LOT-N3-1',
      warehouse: 'N3',
      location: 'N3',
      siteCode: 'SCG',
      stockStatus: 'A',
      totalQty: 10,
    );
    await seedStockRow(
      itemCode: 'SKU-SCG-N6',
      itemName: 'Item on SCG N6',
      lotNumber: 'LOT-N6-1',
      warehouse: 'N6',
      location: 'N6',
      siteCode: 'SCG',
      stockStatus: 'A',
      totalQty: 15,
    );
    await seedStockRow(
      itemCode: 'SKU-POD-N3',
      itemName: 'Same Code Wrong Site POD N3',
      lotNumber: 'LOT-POD-1',
      warehouse: 'N3',
      location: 'N3',
      siteCode: 'POD',
      stockStatus: 'A',
      totalQty: 20,
    );

    final products = await repository.getSalesInvoiceProducts(
      warehouse: 'N6',
      siteCode: 'SCG',
      stockStatus: 'ALL',
    );

    expect(products.map((p) => p.sku).toList(), equals(['SKU-SCG-N3']));
    expect(await repository.getDistinctWarehouses('SCG'), equals(['N3']));
    expect(
      await repository.getProductByItemCode('SKU-SCG-N6', siteCode: 'SCG'),
      isNull,
    );
    expect(
      await repository.getProductByItemCode('SKU-POD-N3', siteCode: 'SCG'),
      isNull,
    );
  });

  test('allows WEB concrete lorry location and rejects unassigned site placeholder', () async {
    await DeviceInfoService.instance.setAssignedLocation(
      siteCode: 'SCG',
      warehouseCode: 'SCG',
      locationCode: 'SCG',
    );

    await seedStockRow(
      itemCode: 'SKU-WEB',
      itemName: 'Item on SCG WEB',
      lotNumber: 'LOT-WEB-1',
      warehouse: 'WEB',
      location: 'WEB',
      siteCode: 'SCG',
      stockStatus: 'A',
      totalQty: 12,
    );

    expect(
      await repository.getSalesInvoiceProducts(siteCode: 'SCG'),
      isEmpty,
    );
    expect(await repository.getDistinctWarehouses('SCG'), isEmpty);

    await DeviceInfoService.instance.setAssignedLocation(
      siteCode: 'SCG',
      warehouseCode: 'WEB',
      locationCode: 'WEB',
    );

    final webProducts = await repository.getSalesInvoiceProducts(siteCode: 'SCG');
    expect(webProducts.map((p) => p.sku).toList(), equals(['SKU-WEB']));
    expect(await repository.getDistinctWarehouses('SCG'), equals(['WEB']));
  });

  test('returns A, Q, and R stock ordered A -> Q -> R and prefers A on barcode lookup', () async {
    await DeviceInfoService.instance.setAssignedLocation(
      siteCode: 'SCG',
      warehouseCode: 'N3',
      locationCode: 'N3',
    );

    await seedStockRow(
      itemCode: 'SKU-MULTI',
      itemName: 'Multi Status Item',
      lotNumber: 'LOT-R',
      warehouse: 'N3',
      location: 'N3',
      siteCode: 'SCG',
      stockStatus: 'R',
      totalQty: 50,
    );
    await seedStockRow(
      itemCode: 'SKU-MULTI',
      itemName: 'Multi Status Item',
      lotNumber: 'LOT-Q',
      warehouse: 'N3',
      location: 'N3',
      siteCode: 'SCG',
      stockStatus: 'Q01',
      totalQty: 30,
    );
    await seedStockRow(
      itemCode: 'SKU-MULTI',
      itemName: 'Multi Status Item',
      lotNumber: 'LOT-A',
      warehouse: 'N3',
      location: 'N3',
      siteCode: 'SCG',
      stockStatus: 'A',
      totalQty: 5,
    );
    await seedStockRow(
      itemCode: 'SKU-Q-ONLY',
      itemName: 'Quarantine Only Item',
      lotNumber: 'LOT-QO',
      warehouse: 'N3',
      location: 'N3',
      siteCode: 'SCG',
      stockStatus: 'Q',
      totalQty: 8,
    );

    final allProducts = await repository.getSalesInvoiceProducts(
      siteCode: 'SCG',
      stockStatus: 'ALL',
    );
    expect(
      allProducts.map((p) => '${p.sku}:${p.stockStatus}').toList(),
      equals(['SKU-MULTI:A', 'SKU-MULTI:Q01', 'SKU-Q-ONLY:Q', 'SKU-MULTI:R']),
    );

    final lots = await repository.getSalesInvoiceItemStockDetails(
      'SKU-MULTI',
      siteCode: 'SCG',
      stockStatus: 'ALL',
    );
    expect(lots.map((l) => l.stockStatus).toList(), equals(['A', 'Q01', 'R']));

    final preferredBarcode = await repository.getProductByItemCode(
      'SKU-MULTI',
      siteCode: 'SCG',
      stockStatus: 'ALL',
    );
    expect(preferredBarcode?.stockStatus, equals('A'));

    final qOnly = await repository.getProductByItemCode(
      'SKU-Q-ONLY',
      siteCode: 'SCG',
      stockStatus: 'ALL',
    );
    expect(qOnly?.stockStatus, equals('Q'));
  });

  test('getFocLorryStockMatch only selects Status A stock inside assigned lorry', () async {
    await DeviceInfoService.instance.setAssignedLocation(
      siteCode: 'SCG',
      warehouseCode: 'N3',
      locationCode: 'N3',
    );

    await seedStockRow(
      itemCode: 'FOC-GIFT',
      itemName: 'FOC Item',
      lotNumber: 'LOT-Q-FOC',
      warehouse: 'N3',
      location: 'N3',
      siteCode: 'SCG',
      stockStatus: 'Q',
      totalQty: 25,
    );
    await seedStockRow(
      itemCode: 'FOC-GIFT',
      itemName: 'FOC Item',
      lotNumber: 'LOT-A-WRONG-LORRY',
      warehouse: 'N6',
      location: 'N6',
      siteCode: 'SCG',
      stockStatus: 'A',
      totalQty: 100,
    );

    final noneSellable = await repository.getFocLorryStockMatch(
      'FOC-GIFT',
      siteCode: 'SCG',
    );
    expect(noneSellable.totalStock, equals(0.0));
    expect(noneSellable.lotNumber, isEmpty);

    await seedStockRow(
      itemCode: 'FOC-GIFT',
      itemName: 'FOC Item',
      lotNumber: 'LOT-A-N3',
      warehouse: 'N3',
      location: 'N3',
      siteCode: 'SCG',
      stockStatus: 'A',
      totalQty: 7,
    );

    final sellableMatch = await repository.getFocLorryStockMatch(
      'FOC-GIFT',
      preferredLot: 'LOT-A-N3',
      siteCode: 'SCG',
    );
    expect(sellableMatch.totalStock, equals(7.0));
    expect(sellableMatch.lotNumber, equals('LOT-A-N3'));
    expect(sellableMatch.warehouse, equals('N3'));
  });

  test('syncSalesInvoiceItemStockDetails clears cache when X-Lorry-Required header is true and invalidates on lorry switch', () async {
    await DeviceInfoService.instance.setAssignedLocation(
      siteCode: 'SCG',
      warehouseCode: 'N3',
      locationCode: 'N3',
    );

    await seedStockRow(
      itemCode: 'OLD-SKU',
      itemName: 'Old Lorry Stock',
      lotNumber: 'LOT-1',
      warehouse: 'N3',
      location: 'N3',
      siteCode: 'SCG',
      stockStatus: 'A',
      totalQty: 4,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('etag_stock_SCG', '"old-etag"');

    adapter.handler = (options) {
      return ResponseBody.fromString(
        jsonEncode([]),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
          'X-Lorry-Required': ['true'],
        },
      );
    };

    await repository.syncSalesInvoiceItemStockDetails('SCG');

    final remaining = await db.query(LocalDatabaseHelper.tableSalesInvoiceItemStockDetails);
    expect(remaining, isEmpty);
    expect(prefs.getString('etag_stock_SCG'), isNull);

    await seedStockRow(
      itemCode: 'NEW-SKU',
      itemName: 'New Lorry Stock',
      lotNumber: 'LOT-2',
      warehouse: 'N6',
      location: 'N6',
      siteCode: 'SCG',
      stockStatus: 'Q',
      totalQty: 9,
    );
    await prefs.setString('etag_stock_SCG', '"new-etag"');

    await SalesInvoiceProductRepository.invalidateStockCache(clearLocalRows: true);
    expect(await db.query(LocalDatabaseHelper.tableSalesInvoiceItemStockDetails), isEmpty);
    expect(prefs.getString('etag_stock_SCG'), isNull);
  });

  test('SalesInvoiceBloc blocks non-A stock on INVOICE but permits it on RETURN', () async {
    final bloc = SalesInvoiceBloc(repository: _FakeSalesRepository());
    final product = SalesInvoiceProductModel(
      sku: 'SKU-Q',
      name: 'Quarantine Product',
      stockQty: 5,
      warehouse: 'N3',
      salesUnit: 'EA',
      stockStatus: 'Q',
    );

    bloc.add(InitializeTransaction(
      transactionType: 'INVOICE',
      config: TransactionConfig.forType('INVOICE'),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    bloc.add(AddCartItem(CartItem(
      product: product,
      quantity: 1,
      basePrice: 100,
      warehouse: 'N3',
      location: 'N3',
      stockStatus: 'Q',
    )));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect((bloc.state as SalesInvoiceLoaded).cartItems, isEmpty);

    bloc.add(InitializeTransaction(
      transactionType: 'RETURN',
      config: TransactionConfig.forType('RETURN'),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    bloc.add(AddCartItem(CartItem(
      product: product,
      quantity: 1,
      basePrice: 100,
      warehouse: 'N3',
      location: 'N3',
      stockStatus: 'Q',
    )));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect((bloc.state as SalesInvoiceLoaded).cartItems.length, equals(1));
    await bloc.close();
  });

  test('allocateQuantityAcrossLorryLots splits across multiple Status A lots consuming preferred lot first and allocates same-SKU FOC cleanly', () async {
    await DeviceInfoService.instance.setAssignedLocation(
      siteCode: 'SCG',
      warehouseCode: 'N3',
      locationCode: 'N3',
    );

    await seedStockRow(
      itemCode: 'SKU-SPLIT',
      itemName: 'Split Lot Item',
      lotNumber: 'LOT-Q-SKIP',
      warehouse: 'N3',
      location: 'N3',
      siteCode: 'SCG',
      stockStatus: 'Q',
      totalQty: 50,
    );
    await seedStockRow(
      itemCode: 'SKU-SPLIT',
      itemName: 'Split Lot Item',
      lotNumber: 'LOT-1',
      warehouse: 'N3',
      location: 'N3',
      siteCode: 'SCG',
      stockStatus: 'A',
      totalQty: 10,
    );
    await seedStockRow(
      itemCode: 'SKU-SPLIT',
      itemName: 'Split Lot Item',
      lotNumber: 'LOT-2',
      warehouse: 'N3',
      location: 'N3',
      siteCode: 'SCG',
      stockStatus: 'A',
      totalQty: 12,
    );
    await seedStockRow(
      itemCode: 'SKU-SPLIT',
      itemName: 'Split Lot Item',
      lotNumber: 'LOT-3',
      warehouse: 'N3',
      location: 'N3',
      siteCode: 'SCG',
      stockStatus: 'A',
      totalQty: 5,
    );

    final paidAllocs = await repository.allocateQuantityAcrossLorryLots(
      'SKU-SPLIT',
      requestedQty: 18,
      preferredLot: 'LOT-1',
      siteCode: 'SCG',
    );

    expect(
      paidAllocs.map((a) => '${a.lotNumber}:${a.allocatedQty.toInt()}').toList(),
      equals(['LOT-1:10', 'LOT-2:8']),
    );

    final reservedAfterPaid = <String, double>{
      for (final a in paidAllocs)
        SalesInvoiceProductRepository.lotAllocationKey(
          a.lotNumber,
          a.warehouse,
          a.location,
        ): a.allocatedQty,
    };

    // Total remaining Status A = 4 (LOT-2) + 5 (LOT-3) = 9
    final focAllocs = await repository.allocateFocAcrossLorryLots(
      'SKU-SPLIT',
      requestedFocQty: 6,
      preferredLot: 'LOT-1',
      siteCode: 'SCG',
      reservedQtyByLotKey: reservedAfterPaid,
    );

    expect(
      focAllocs.map((a) => '${a.lotNumber}:${a.allocatedQty.toInt()}').toList(),
      equals(['LOT-2:4', 'LOT-3:2']),
    );
  });

  test('SalesInvoiceBloc UpsertProductLotCartItems replaces split lots and linked FOC atomically', () async {
    final bloc = SalesInvoiceBloc(repository: _FakeSalesRepository());
    final product = SalesInvoiceProductModel(
      sku: 'SKU-SPLIT',
      name: 'Split Item',
      stockQty: 27,
      warehouse: 'N3',
      salesUnit: 'EA',
      stockStatus: 'A',
    );
    final otherProduct = SalesInvoiceProductModel(
      sku: 'SKU-OTHER',
      name: 'Other Item',
      stockQty: 5,
      warehouse: 'N3',
      salesUnit: 'EA',
      stockStatus: 'A',
    );

    bloc.add(InitializeTransaction(
      transactionType: 'INVOICE',
      config: TransactionConfig.forType('INVOICE'),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    bloc.add(UpsertProductLotCartItems(
      sku: 'SKU-SPLIT',
      paidItems: [
        CartItem(
          product: product,
          quantity: 10,
          basePrice: 50,
          lotNumber: 'LOT-1',
          warehouse: 'N3',
          location: 'N3',
        ),
        CartItem(
          product: product,
          quantity: 8,
          basePrice: 50,
          lotNumber: 'LOT-2',
          warehouse: 'N3',
          location: 'N3',
        ),
      ],
      focItems: [
        CartItem(
          product: product,
          quantity: 2,
          basePrice: 0,
          discountPercent: 100,
          isFoc: true,
          mainItemSku: 'SKU-SPLIT',
          lotNumber: 'LOT-2',
          warehouse: 'N3',
          location: 'N3',
        ),
      ],
    ));
    bloc.add(AddCartItem(CartItem(
      product: otherProduct,
      quantity: 1,
      basePrice: 20,
      lotNumber: 'LOT-O',
      warehouse: 'N3',
      location: 'N3',
    )));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    var loaded = bloc.state as SalesInvoiceLoaded;
    expect(loaded.cartItems.length, equals(4));

    // Re-edit whole SKU from Product Selection -> replaces both split lines & FOC while preserving SKU-OTHER
    bloc.add(UpsertProductLotCartItems(
      sku: 'SKU-SPLIT',
      replaceAllForSku: true,
      paidItems: [
        CartItem(
          product: product,
          quantity: 6,
          basePrice: 50,
          lotNumber: 'LOT-1',
          warehouse: 'N3',
          location: 'N3',
        ),
      ],
      focItems: const [],
    ));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    loaded = bloc.state as SalesInvoiceLoaded;
    expect(loaded.cartItems.length, equals(2));
    expect(loaded.cartItems.where((c) => c.product.sku == 'SKU-SPLIT').single.quantity, equals(6));
    expect(loaded.cartItems.any((c) => c.product.sku == 'SKU-OTHER'), isTrue);
    await bloc.close();
  });
}
