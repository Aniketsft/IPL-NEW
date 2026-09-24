import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/sales_invoice_product_repository.dart';

class FakeNetworkService implements NetworkService {
  @override
  late final Dio dio;

  @override
  VoidCallback? onUnauthorized;

  FakeNetworkService(this.dio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late Dio dio;
  late SalesInvoiceProductRepository repository;
  RequestOptions? lastRequestOptions;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    LocalDatabaseHelper.setTestDatabase(db);

    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} (
        warehouse TEXT,
        warehouseName TEXT,
        location TEXT,
        locationType TEXT,
        itemCode TEXT,
        itemName TEXT,
        totalQty REAL,
        lotNumber TEXT,
        taxLevel TEXT,
        cce0 TEXT,
        salesUnit TEXT,
        barcode TEXT,
        isSynced INTEGER DEFAULT 1,
        createdAt TEXT,
        updatedAt TEXT,
        deviceId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableSiInvoices} (
        invoiceId TEXT PRIMARY KEY,
        customerCode TEXT,
        customerName TEXT,
        totalVat REAL,
        totalDiscount REAL,
        grandTotal REAL,
        createdAt TEXT,
        status TEXT,
        isSynced INTEGER DEFAULT 0,
        transactionType TEXT DEFAULT 'INVOICE',
        isReversed INTEGER DEFAULT 0,
        reference TEXT,
        salesSite TEXT,
        x3DocumentId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableSiInvoiceLines} (
        lineId INTEGER,
        invoiceId TEXT,
        sku TEXT,
        lotNumber TEXT,
        warehouse TEXT,
        location TEXT,
        quantity REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableSiCreditNotes} (
        creditNoteId TEXT PRIMARY KEY,
        customerCode TEXT,
        isSynced INTEGER DEFAULT 0,
        isReversed INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableSiCreditNoteLines} (
        creditNoteId TEXT,
        sku TEXT,
        lotNumber TEXT,
        warehouse TEXT,
        location TEXT,
        quantity REAL
      )
    ''');

    dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          lastRequestOptions = options;
          handler.resolve(
            Response(
              requestOptions: options,
              data: [
                {
                  'warehouse': 'WH1',
                  'warehouseName': 'Main Warehouse',
                  'location': 'LOC1',
                  'locationType': 'STD',
                  'itemCode': 'ITEM001',
                  'itemName': 'Sample Item',
                  'totalQty': 50.0,
                  'lotNumber': 'LOT001',
                  'taxLevel': 'VAT',
                  'cce0': 'CCE',
                  'salesUnit': 'EA',
                  'barcode': '1234567890'
                }
              ],
              statusCode: 200,
            ),
          );
        },
      ),
    );

    repository = SalesInvoiceProductRepository(FakeNetworkService(dio));
  });

  tearDown(() async {
    LocalDatabaseHelper.setTestDatabase(null);
    await db.close();
  });

  test('syncSalesInvoiceItemStockDetails forwards siteCode as query parameter', () async {
    await repository.syncSalesInvoiceItemStockDetails('IPL');

    expect(lastRequestOptions, isNotNull);
    expect(lastRequestOptions!.path, 'SalesInvoice/itemstockdetails');
    expect(lastRequestOptions!.queryParameters, {'sitecode': 'IPL'});

    final stored = await db.query(LocalDatabaseHelper.tableSalesInvoiceItemStockDetails);
    expect(stored.length, 1);
    expect(stored.first['itemCode'], 'ITEM001');
  });

  test('syncSalesInvoiceItemStockDetails sends no query parameters when siteCode is null', () async {
    await repository.syncSalesInvoiceItemStockDetails(null);

    expect(lastRequestOptions, isNotNull);
    expect(lastRequestOptions!.path, 'SalesInvoice/itemstockdetails');
    expect(lastRequestOptions!.queryParameters.isEmpty, isTrue);
  });
}
