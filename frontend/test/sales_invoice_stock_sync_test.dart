import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';
import 'package:enterprise_auth_mobile/core/secure_storage_service.dart';
import 'package:enterprise_auth_mobile/core/services/device_heartbeat_service.dart';
import 'package:enterprise_auth_mobile/core/services/device_info_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/sales_invoice_product_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/sales_invoice_sync_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/usecases/synchronize_sales_invoice_use_case.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_sync_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_sync_event.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/widgets/sales_invoice_sync_overlay.dart';

class _MockHttpAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  _MockHttpAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

String _buildUnexpiredTestJwt() {
  final header = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}')).replaceAll('=', '');
  final payload = base64Url.encode(utf8.encode('{"sub":"u1","exp":4102444800}')).replaceAll('=', '');
  return '$header.$payload.sig';
}

Future<Database> _createTestDatabase() async {
  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

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
      ${LocalDatabaseHelper.colSiProdSku} TEXT PRIMARY KEY,
      ${LocalDatabaseHelper.colSiProdName} TEXT NOT NULL,
      ${LocalDatabaseHelper.colSiProdStockQty} REAL,
      ${LocalDatabaseHelper.colSiProdWarehouse} TEXT,
      ${LocalDatabaseHelper.colSiProdSalesUnit} TEXT,
      ${LocalDatabaseHelper.colSiProdIsSynced} INTEGER NOT NULL DEFAULT 1,
      cce0 TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tableSiInvoices} (
      invoiceId TEXT PRIMARY KEY,
      customerCode TEXT,
      customerName TEXT,
      salesSite TEXT,
      totalVat REAL,
      totalDiscount REAL,
      grandTotal REAL,
      createdAt TEXT,
      status TEXT,
      isSynced INTEGER DEFAULT 0,
      transactionType TEXT DEFAULT 'INVOICE',
      isReversed INTEGER DEFAULT 0,
      x3DocumentId TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tableSiInvoiceLines} (
      lineId INTEGER PRIMARY KEY AUTOINCREMENT,
      lineNo INTEGER DEFAULT 0,
      invoiceId TEXT,
      sku TEXT,
      name TEXT,
      quantity REAL,
      basePrice REAL,
      discountAmount REAL,
      vatAmount REAL,
      total REAL,
      lotNumber TEXT,
      warehouse TEXT,
      location TEXT,
      salesUnit TEXT,
      cce0 TEXT,
      taxRule TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tableSiCreditNotes} (
      creditNoteId TEXT PRIMARY KEY,
      creditNoteType TEXT NOT NULL,
      x3CreditNoteType TEXT DEFAULT 'CRN',
      salesSite TEXT NOT NULL,
      customerCode TEXT NOT NULL,
      customerName TEXT NOT NULL,
      currency TEXT DEFAULT 'MUR',
      grandTotal REAL NOT NULL,
      originalInvoiceId TEXT,
      linkedInvoiceIds TEXT,
      settlementType TEXT NOT NULL,
      reference TEXT,
      isSynced INTEGER DEFAULT 0,
      x3DocumentId TEXT,
      createdAt TEXT NOT NULL,
      createdBy TEXT NOT NULL,
      deviceId TEXT,
      reason TEXT,
      salesRep TEXT,
      transactionMode TEXT DEFAULT '1',
      stockTransaction INTEGER DEFAULT 0,
      x3StockReceiptId TEXT,
      x3RefundPaymentId TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tableSiCreditNoteLines} (
      lineId INTEGER PRIMARY KEY AUTOINCREMENT,
      creditNoteId TEXT NOT NULL,
      lineNo INTEGER NOT NULL,
      quantity REAL NOT NULL,
      originInvoiceId TEXT,
      originLineNo INTEGER,
      standaloneSku TEXT,
      standaloneName TEXT,
      standaloneSalesUnit TEXT,
      standalonePrice REAL,
      standaloneTaxRule TEXT,
      standaloneLot TEXT,
      standaloneWarehouse TEXT,
      standaloneCce0 TEXT,
      stockStatus TEXT DEFAULT 'A',
      returnCondition TEXT,
      expiryDate TEXT,
      location TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tableDeviceLocations} (
      deviceId TEXT PRIMARY KEY,
      deviceName TEXT NOT NULL,
      hardwareModel TEXT,
      hardwareIdentifier TEXT,
      siteCode TEXT NOT NULL,
      warehouseCode TEXT,
      locationCode TEXT NOT NULL,
      hepProfileId TEXT,
      hepApiKey TEXT,
      isLocked INTEGER NOT NULL DEFAULT 1,
      isLicensed INTEGER NOT NULL DEFAULT 1,
      licenseStatus TEXT NOT NULL DEFAULT 'VALID',
      licenseUpdatedAt TEXT,
      licenseUpdatedBy TEXT,
      assignedUserId TEXT,
      assignedUserName TEXT,
      isActive INTEGER NOT NULL DEFAULT 1,
      updatedAt TEXT,
      updatedBy TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tableFacilities} (
      salesSiteCode TEXT PRIMARY KEY,
      salesSiteName TEXT NOT NULL,
      salesFlag INTEGER NOT NULL DEFAULT 1,
      financialSiteCode TEXT NOT NULL,
      financialSiteName TEXT,
      legalCompany TEXT NOT NULL DEFAULT 'INL',
      updatedAt TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tableDocumentSequences} (
      docType TEXT NOT NULL,
      financialSite TEXT NOT NULL,
      lorryCode TEXT NOT NULL,
      deviceTag TEXT NOT NULL,
      yearMonth TEXT NOT NULL,
      lastSequence INTEGER NOT NULL DEFAULT 0,
      updatedAt TEXT NOT NULL,
      PRIMARY KEY (docType, financialSite, lorryCode, deviceTag, yearMonth)
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tableTaxMatrix} (
      ${LocalDatabaseHelper.colTaxMatrixCustomerRule} TEXT,
      ${LocalDatabaseHelper.colTaxMatrixItemLevel} TEXT,
      ${LocalDatabaseHelper.colTaxMatrixTaxCode} TEXT,
      PRIMARY KEY (${LocalDatabaseHelper.colTaxMatrixCustomerRule}, ${LocalDatabaseHelper.colTaxMatrixItemLevel})
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tableTaxRates} (
      ${LocalDatabaseHelper.colTaxRateTaxCode} TEXT PRIMARY KEY,
      ${LocalDatabaseHelper.colTaxRateDescription} TEXT,
      ${LocalDatabaseHelper.colTaxRatePercent} REAL
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tableReps} (
      ${LocalDatabaseHelper.colCode} TEXT PRIMARY KEY,
      ${LocalDatabaseHelper.colName} TEXT,
      assignedSite TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tablePriceLists} (
      pliCode TEXT,
      priority INTEGER,
      ruleType INTEGER,
      isQtyBased INTEGER,
      focType INTEGER,
      fil0 TEXT,
      fld0 TEXT,
      fil1 TEXT,
      fld1 TEXT,
      matchKey1 TEXT,
      matchKey2 TEXT,
      basePrice REAL,
      discountPct REAL,
      discountAmt REAL,
      focQtyMin REAL,
      focQtyBkt REAL,
      focAmtMin REAL,
      focAmtBkt REAL,
      focItmRef TEXT,
      focQty REAL,
      minQty REAL,
      maxQty REAL,
      validFrom TEXT,
      validTo TEXT,
      reasonType INTEGER
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tableSyncHistory} (
      ${LocalDatabaseHelper.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${LocalDatabaseHelper.colSyncTimestamp} TEXT NOT NULL,
      ${LocalDatabaseHelper.colSyncStatus} TEXT NOT NULL,
      ${LocalDatabaseHelper.colSyncMessage} TEXT,
      ${LocalDatabaseHelper.colSyncCounts} TEXT,
      ${LocalDatabaseHelper.colSyncSite} TEXT
    )
  ''');

  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> secureStore;
  late Database db;
  late NetworkService networkService;
  late SecureStorageService storageService;
  late SalesInvoiceProductRepository productRepository;

  setUp(() async {
    secureStore = {
      'jwt_token': _buildUnexpiredTestJwt(),
      'selected_x3_schema': 'INLDRYRUN',
      'site_code': 'POD',
      'username': 'driver1',
    };

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      final key = args['key']?.toString();
      switch (call.method) {
        case 'read':
          return key != null ? secureStore[key] : null;
        case 'write':
          if (key != null) {
            secureStore[key] = args['value']?.toString() ?? '';
          }
          return null;
        case 'delete':
          if (key != null) secureStore.remove(key);
          return null;
        case 'deleteAll':
          secureStore.clear();
          return null;
        default:
          return null;
      }
    });

    SharedPreferences.setMockInitialValues({});
    db = await _createTestDatabase();
    LocalDatabaseHelper.setTestDatabase(db);

    await DeviceInfoService.instance.setDeviceIdentity(
      uuid: '11111111-1111-1111-1111-111111111111',
      name: 'HM5',
      hardwareIdentifier: 'hw-test-001',
      siteCode: 'POD',
      warehouseCode: 'WRH57',
      locationCode: '57',
    );

    storageService = SecureStorageService();
    networkService = NetworkService(storageService: storageService);
    productRepository = SalesInvoiceProductRepository(networkService);
  });

  tearDown(() async {
    LocalDatabaseHelper.setTestDatabase(null);
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  test('resolveEffectiveSiteCode and resolveAssignedLorryScope treat ALL safely when device has concrete site & lorry', () async {
    secureStore['site_code'] = 'ALL';
    await DeviceInfoService.instance.setDeviceIdentity(
      uuid: '11111111-1111-1111-1111-111111111111',
      name: 'HM5',
      hardwareIdentifier: 'hw-test-001',
      siteCode: 'SCP',
      warehouseCode: 'WRH57',
      locationCode: '57',
    );

    expect(DeviceInfoService.instance.resolveEffectiveSiteCode('ALL'), 'SCP');
    final scope = await productRepository.resolveAssignedLorryScope(siteCode: 'ALL');
    expect(scope.isAssigned, isTrue);
    expect(scope.siteCode, 'SCP');
    expect(scope.lorryCode, '57');
    expect(scope.warehouseCode, 'WRH57');
  });

  test('syncSalesInvoiceItemStockDetails omits If-None-Match when local stock is empty and keys ETag by schema & lorry', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('etag_stock_INLDRYRUN_POD_57', '"stale-etag-empty-db"');

    final adapter = _MockHttpAdapter((options) async {
      expect(options.headers['X-X3-Schema'], 'INLDRYRUN');
      expect(options.headers['X-Device-Hardware-Id'], 'hw-test-001');
      if (options.headers.containsKey('If-None-Match')) {
        return ResponseBody.fromString('', 304, headers: {});
      }
      return ResponseBody.fromString(
        jsonEncode([
          {
            'itemCode': 'SKU01',
            'itemName': 'Chicken Breast',
            'lotNumber': 'LOT1',
            'warehouse': 'WRH57',
            'location': '57',
            'totalQty': 25.0,
            'salesUnit': 'KG',
            'siteCode': 'POD',
            'stockStatus': 'A',
          }
        ]),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          'etag': ['"fresh-etag-dryrun"'],
          'x-assigned-lorry': ['57'],
          'x-assigned-warehouse': ['WRH57'],
        },
      );
    });
    networkService.dio.httpClientAdapter = adapter;

    // 1. Empty SQLite table must NOT send If-None-Match even though prefs had stale ETag
    final firstResult = await productRepository.syncSalesInvoiceItemStockDetails('POD');
    expect(adapter.requests.first.headers.containsKey('If-None-Match'), isFalse);
    expect(firstResult.syncedCount, 1);
    expect(firstResult.fromCache304, isFalse);
    expect(firstResult.lorryRequired, isFalse);

    final products = await productRepository.getSalesInvoiceProducts(siteCode: 'POD');
    expect(products.length, 1);
    expect(products.first.sku, 'SKU01');
    expect(products.first.stockQty, 25.0);

    // 2. Non-empty SQLite table in SAME schema DOES send If-None-Match -> 304
    final secondResult = await productRepository.syncSalesInvoiceItemStockDetails('POD');
    expect(adapter.requests[1].headers['If-None-Match'], '"fresh-etag-dryrun"');
    expect(secondResult.fromCache304, isTrue);
    expect(secondResult.syncedCount, 1);

    // 3. Switching schema to INLPROD must NOT reuse INLDRYRUN ETag
    secureStore['selected_x3_schema'] = 'INLPROD';
    await productRepository.syncSalesInvoiceItemStockDetails('POD');
    expect(adapter.requests[2].headers['X-X3-Schema'], 'INLPROD');
    expect(adapter.requests[2].headers.containsKey('If-None-Match'), isFalse);
  });

  test('syncSalesInvoiceItemStockDetails clears stale stock and reports lorryRequired when server sends X-Lorry-Required', () async {
    await db.insert(LocalDatabaseHelper.tableSalesInvoiceItemStockDetails, {
      'itemCode': 'OLD_SKU',
      'itemName': 'Old Item',
      'lotNumber': 'L0',
      'warehouse': 'WRH57',
      'location': '57',
      'totalQty': 10.0,
      'siteCode': 'POD',
      'stockStatus': 'A',
    });

    final adapter = _MockHttpAdapter((options) async {
      return ResponseBody.fromString(
        '[]',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          'x-lorry-required': ['true'],
        },
      );
    });
    networkService.dio.httpClientAdapter = adapter;

    final result = await productRepository.syncSalesInvoiceItemStockDetails('POD');
    expect(result.lorryRequired, isTrue);
    expect(result.syncedCount, 0);

    final remainingCount = await LocalDatabaseHelper.instance.getSalesInvoiceItemStockCount();
    expect(remainingCount, 0);
  });

  test('syncSalesInvoiceItemStockDetails reconciles X-Assigned-Lorry header when local device lacked lorry', () async {
    await DeviceInfoService.instance.setDeviceIdentity(
      uuid: '11111111-1111-1111-1111-111111111111',
      name: 'HM5',
      hardwareIdentifier: 'hw-test-001',
      siteCode: 'POD',
      warehouseCode: 'POD',
      locationCode: 'POD',
    );
    await db.insert(LocalDatabaseHelper.tableDeviceLocations, {
      'deviceId': '11111111-1111-1111-1111-111111111111',
      'deviceName': 'HM5',
      'hardwareIdentifier': 'hw-test-001',
      'siteCode': 'POD',
      'warehouseCode': 'POD',
      'locationCode': 'POD',
    });

    final adapter = _MockHttpAdapter((options) async {
      return ResponseBody.fromString(
        jsonEncode([
          {
            'itemCode': 'SKU57',
            'itemName': 'Wing Pack',
            'lotNumber': 'L57',
            'warehouse': 'WRH57',
            'location': '57',
            'totalQty': 14.0,
            'salesUnit': 'PK',
            'siteCode': 'POD',
            'stockStatus': 'A',
          }
        ]),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          'x-assigned-lorry': ['57'],
          'x-assigned-warehouse': ['WRH57'],
          'etag': ['"etag-57"'],
        },
      );
    });
    networkService.dio.httpClientAdapter = adapter;

    final result = await productRepository.syncSalesInvoiceItemStockDetails('POD');
    expect(result.lorryRequired, isFalse);
    expect(result.assignedLorry, '57');
    expect(DeviceInfoService.instance.assignedLocation, '57');
    expect(DeviceInfoService.instance.assignedWarehouse, 'WRH57');

    final products = await productRepository.getSalesInvoiceProducts(siteCode: 'POD');
    expect(products.length, 1);
    expect(products.first.sku, 'SKU57');
  });

  test('syncSalesInvoiceItemStockDetails reconciles unsynced invoice and credit note stock ledger without SQLite errors', () async {
    await db.insert(LocalDatabaseHelper.tableSiInvoices, {
      'invoiceId': 'INV-001',
      'customerCode': 'CUST1',
      'customerName': 'Customer 1',
      'salesSite': 'POD',
      'totalVat': 0.0,
      'totalDiscount': 0.0,
      'grandTotal': 100.0,
      'createdAt': '2026-11-24T10:00:00',
      'status': 'SAVED',
      'isSynced': 0,
      'transactionType': 'INVOICE',
      'isReversed': 0,
    });
    await db.insert(LocalDatabaseHelper.tableSiInvoiceLines, {
      'lineNo': 1,
      'invoiceId': 'INV-001',
      'sku': 'SKU57',
      'name': 'Wing Pack',
      'quantity': 3.0,
      'basePrice': 50.0,
      'discountAmount': 0.0,
      'vatAmount': 0.0,
      'total': 100.0,
      'lotNumber': 'L57',
      'warehouse': 'WRH57',
      'location': '57',
      'salesUnit': 'PK',
      'cce0': '',
      'taxRule': 'VAT15',
    });
    await db.insert(LocalDatabaseHelper.tableSiCreditNotes, {
      'creditNoteId': 'CN-001',
      'creditNoteType': 'STANDALONE',
      'x3CreditNoteType': 'CRN',
      'salesSite': 'POD',
      'customerCode': 'CUST1',
      'customerName': 'Customer 1',
      'currency': 'MUR',
      'grandTotal': 25.0,
      'originalInvoiceId': 'INV-001',
      'settlementType': 'CREDIT',
      'isSynced': 0,
      'createdAt': '2026-11-24T11:00:00',
      'createdBy': 'driver1',
      'stockTransaction': 1,
    });
    await db.insert(LocalDatabaseHelper.tableSiCreditNoteLines, {
      'creditNoteId': 'CN-001',
      'lineNo': 1,
      'quantity': 1.0,
      'originInvoiceId': 'INV-001',
      'originLineNo': 1,
      'standaloneSku': 'SKU57',
      'standaloneName': 'Wing Pack',
      'standaloneSalesUnit': 'PK',
      'standalonePrice': 25.0,
      'standaloneLot': 'L57',
      'standaloneWarehouse': 'WRH57',
      'stockStatus': 'A',
      'location': '57',
    });

    final adapter = _MockHttpAdapter((options) async {
      return ResponseBody.fromString(
        jsonEncode([
          {
            'itemCode': 'SKU57',
            'itemName': 'Wing Pack',
            'lotNumber': 'L57',
            'warehouse': 'WRH57',
            'location': '57',
            'totalQty': 20.0,
            'salesUnit': 'PK',
            'siteCode': 'POD',
            'stockStatus': 'A',
          }
        ]),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          'x-assigned-lorry': ['57'],
          'x-assigned-warehouse': ['WRH57'],
          'etag': ['"etag-ledger-57"'],
        },
      );
    });
    networkService.dio.httpClientAdapter = adapter;

    final result = await productRepository.syncSalesInvoiceItemStockDetails('POD');
    expect(result.syncedCount, 1);

    final products = await productRepository.getSalesInvoiceProducts(siteCode: 'POD');
    expect(products.length, 1);
    expect(products.first.stockQty, 18.0); // 20.0 - 3.0 invoice + 1.0 credit note return
  });

  test('DeviceHeartbeatService sends Dio heartbeat, reconciles lorry assignment, and clears stock ETag on lorry change', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('etag_stock_INLDRYRUN_POD_57', '"old-57"');
    await db.insert(LocalDatabaseHelper.tableSalesInvoiceItemStockDetails, {
      'itemCode': 'SKU57',
      'itemName': 'Old Lorry Item',
      'lotNumber': 'L1',
      'warehouse': 'WRH57',
      'location': '57',
      'totalQty': 4.0,
      'siteCode': 'POD',
      'stockStatus': 'A',
    });

    final adapter = _MockHttpAdapter((options) async {
      expect(options.path, contains('Devices/heartbeat'));
      return ResponseBody.fromString(
        jsonEncode({
          'deviceId': '22222222-2222-2222-2222-222222222222',
          'deviceName': 'HM9',
          'hardwareIdentifier': 'hw-test-001',
          'siteCode': 'SCP',
          'warehouseCode': 'WRH60',
          'locationCode': '60',
          'isLicensed': true,
          'licenseStatus': 'VALID',
          'isLocked': false,
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    });
    networkService.dio.httpClientAdapter = adapter;

    final heartbeatService = DeviceHeartbeatService(
      networkService: networkService,
      storageService: storageService,
    );
    final ok = await heartbeatService.syncDeviceLocation(siteCode: 'ALL');
    expect(ok, isTrue);
    expect(DeviceInfoService.instance.deviceId, '22222222-2222-2222-2222-222222222222');
    expect(DeviceInfoService.instance.assignedSite, 'SCP');
    expect(DeviceInfoService.instance.assignedLocation, '60');
    expect(prefs.getString('etag_stock_INLDRYRUN_POD_57'), isNull);
    expect(await LocalDatabaseHelper.instance.getSalesInvoiceItemStockCount(), 0);
  });

  testWidgets('SalesInvoiceSyncRepository records ERR_LORRY_REQUIRED and SalesInvoiceSyncOverlay shows warning instead of success', (tester) async {
    await DeviceInfoService.instance.setDeviceIdentity(
      uuid: '11111111-1111-1111-1111-111111111111',
      name: 'HM5',
      hardwareIdentifier: 'hw-unassigned',
      siteCode: 'POD',
      warehouseCode: 'POD',
      locationCode: 'POD',
    );

    final adapter = _MockHttpAdapter((options) async {
      final path = options.path.toLowerCase();
      if (path.contains('devices/heartbeat')) {
        return ResponseBody.fromString(
          jsonEncode({
            'deviceId': '11111111-1111-1111-1111-111111111111',
            'deviceName': 'HM5',
            'hardwareIdentifier': 'hw-unassigned',
            'siteCode': 'POD',
            'warehouseCode': 'POD',
            'locationCode': 'POD',
            'isLicensed': true,
            'licenseStatus': 'VALID',
            'isLocked': false,
          }),
          200,
          headers: {Headers.contentTypeHeader: ['application/json']},
        );
      }
      if (path.contains('salesinvoice/itemstockdetails')) {
        return ResponseBody.fromString(
          '[]',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
            'x-lorry-required': ['true'],
          },
        );
      }
      if (path.contains('salesinvoice/sales-extras') || path.contains('sync/sales-extras')) {
        return ResponseBody.fromString(
          jsonEncode({'orders': [], 'details': []}),
          200,
          headers: {Headers.contentTypeHeader: ['application/json']},
        );
      }
      if (path.contains('salesinvoice/customers') ||
          path.contains('salesinvoice/price-lists') ||
          path.contains('salesinvoice/open-invoices') ||
          path.contains('salesinvoice/x3-history')) {
        return ResponseBody.fromString('', 304, headers: {});
      }
      if (path.contains('sync/log-event')) {
        return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: ['application/json']});
      }
      return ResponseBody.fromString('[]', 200, headers: {Headers.contentTypeHeader: ['application/json']});
    });
    networkService.dio.httpClientAdapter = adapter;

    final syncRepository = SalesInvoiceSyncRepository(
      networkService: networkService,
      productRepository: productRepository,
    );
    final useCase = SynchronizeSalesInvoiceUseCase(syncRepository);
    final syncBloc = SalesInvoiceSyncBloc(
      synchronizeSalesInvoiceUseCase: useCase,
      repository: syncRepository,
    );

    await tester.pumpWidget(
      BlocProvider<SalesInvoiceSyncBloc>.value(
        value: syncBloc,
        child: const MaterialApp(
          home: Scaffold(
            body: SalesInvoiceSyncOverlay(),
          ),
        ),
      ),
    );

    await tester.runAsync(() async {
      syncBloc.add(const StartSalesInvoiceSyncRequested(siteCode: 'POD', downloadOnly: true));
      await syncBloc.stream.firstWhere(
        (s) => s is SalesInvoiceSyncSuccess || s is SalesInvoiceSyncFailure,
      );
    });
    await tester.pump();

    expect(find.text('Sync Completed with Warnings'), findsOneWidget);
    expect(find.textContaining('No lorry assigned to this tablet'), findsOneWidget);
    expect(find.text('Sync Complete'), findsNothing);

    await syncBloc.close();
  });
}
