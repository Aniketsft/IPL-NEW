import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    
    // Create base invoice tables
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
        lineId INTEGER PRIMARY KEY AUTOINCREMENT,
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
        salesUnit TEXT,
        cce0 TEXT,
        taxRule TEXT,
        isFoc INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableSiPayments} (
        paymentId INTEGER PRIMARY KEY AUTOINCREMENT,
        invoiceId TEXT,
        method TEXT,
        amount REAL,
        bankCode TEXT,
        bankName TEXT,
        chequeNumber TEXT,
        chequeDate TEXT
      )
    ''');

    // Create the new dedicated credit note tables
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
        deviceId TEXT
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
        standaloneCce0 TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableSiCreditNoteRefunds} (
        refundId INTEGER PRIMARY KEY AUTOINCREMENT,
        creditNoteId TEXT NOT NULL,
        method TEXT NOT NULL,
        amount REAL NOT NULL,
        bankCode TEXT,
        bankName TEXT,
        chequeNumber TEXT,
        chequeDate TEXT
      )
    ''');
  });

  tearDown(() async {
    await db.close();
  });

  test('Reversal Credit Note resolves lines from origin invoice lines', () async {
    // 1. Seed original invoice and line
    await db.insert(LocalDatabaseHelper.tableSiInvoices, {
      'invoiceId': 'INV-2026-001',
      'customerCode': 'CUST01',
      'customerName': 'Supermarket Alpha',
      'grandTotal': 1150.0,
      'createdAt': '2026-06-01T10:00:00',
      'status': 'PAID',
      'salesSite': 'SCG',
      'x3DocumentId': 'SCGSI2606001',
    });

    await db.insert(LocalDatabaseHelper.tableSiInvoiceLines, {
      'invoiceId': 'INV-2026-001',
      'sku': 'SKU-890774',
      'name': 'Huggies Nappies No1',
      'quantity': 10.0,
      'basePrice': 100.0,
      'discountAmount': 0.0,
      'vatAmount': 15.0,
      'total': 115.0,
      'lotNumber': 'LOT-A1',
      'warehouse': 'WH01',
      'salesUnit': 'EA',
      'cce0': 'COMMERCIAL',
      'taxRule': 'VAT15',
    });

    // 2. Insert Reversal Credit Note with lean line reference
    await db.insert(LocalDatabaseHelper.tableSiCreditNotes, {
      'creditNoteId': 'CN-2026-001',
      'creditNoteType': 'REVERSAL',
      'salesSite': 'SCG',
      'customerCode': 'CUST01',
      'customerName': 'Supermarket Alpha',
      'grandTotal': 1150.0,
      'originalInvoiceId': 'INV-2026-001',
      'settlementType': 'CASH',
      'createdAt': '2026-06-01T12:00:00',
      'createdBy': 'driver1',
    });

    await db.insert(LocalDatabaseHelper.tableSiCreditNoteLines, {
      'creditNoteId': 'CN-2026-001',
      'lineNo': 1000,
      'quantity': 10.0,
      'originInvoiceId': 'INV-2026-001',
      'originLineNo': 1,
    });

    // 3. Query merged view
    final query = '''
      SELECT 
        cnl.lineId,
        cnl.creditNoteId,
        cnl.lineNo,
        cnl.quantity,
        COALESCE(cnl.standaloneSku, il.sku) AS sku,
        COALESCE(cnl.standaloneName, il.name) AS name,
        COALESCE(cnl.standaloneSalesUnit, il.salesUnit, 'EA') AS salesUnit,
        COALESCE(cnl.standalonePrice, il.basePrice, 0.0) AS basePrice,
        COALESCE(cnl.standaloneTaxRule, il.taxRule, '') AS taxRule,
        COALESCE(cnl.standaloneLot, il.lotNumber, '') AS lotNumber,
        COALESCE(cnl.standaloneWarehouse, il.warehouse, '') AS warehouse,
        COALESCE(cnl.standaloneCce0, il.cce0, '') AS cce0
      FROM ${LocalDatabaseHelper.tableSiCreditNoteLines} cnl
      LEFT JOIN ${LocalDatabaseHelper.tableSiInvoiceLines} il
        ON cnl.originInvoiceId = il.invoiceId AND cnl.originLineNo = il.lineId
      WHERE cnl.creditNoteId = ?
    ''';

    final result = await db.rawQuery(query, ['CN-2026-001']);
    expect(result.length, 1);
    expect(result.first['sku'], 'SKU-890774');
    expect(result.first['name'], 'Huggies Nappies No1');
    expect(result.first['basePrice'], 100.0);
    expect(result.first['taxRule'], 'VAT15');
    expect(result.first['lotNumber'], 'LOT-A1');
    expect(result.first['cce0'], 'COMMERCIAL');
  });

  test('Standalone Credit Note stores and retrieves standalone fields', () async {
    await db.insert(LocalDatabaseHelper.tableSiCreditNotes, {
      'creditNoteId': 'CN-STAND-001',
      'creditNoteType': 'STANDALONE',
      'salesSite': 'IPL',
      'customerCode': 'CUST02',
      'customerName': 'Corner Store',
      'grandTotal': 500.0,
      'settlementType': 'CREDIT',
      'createdAt': '2026-06-02T10:00:00',
      'createdBy': 'rep1',
    });

    await db.insert(LocalDatabaseHelper.tableSiCreditNoteLines, {
      'creditNoteId': 'CN-STAND-001',
      'lineNo': 1000,
      'quantity': 5.0,
      'standaloneSku': 'SKU-DIRECT',
      'standaloneName': 'Direct Return Item',
      'standaloneSalesUnit': 'BOX',
      'standalonePrice': 100.0,
      'standaloneTaxRule': 'VAT0',
      'standaloneLot': 'LOT-DIR',
      'standaloneWarehouse': 'WH-IPL',
      'standaloneCce0': 'COMMERCIAL',
    });

    await db.insert(LocalDatabaseHelper.tableSiCreditNoteRefunds, {
      'creditNoteId': 'CN-STAND-001',
      'method': 'CREDIT',
      'amount': 500.0,
    });

    final query = '''
      SELECT 
        cnl.lineId,
        cnl.creditNoteId,
        cnl.lineNo,
        cnl.quantity,
        COALESCE(cnl.standaloneSku, il.sku) AS sku,
        COALESCE(cnl.standaloneName, il.name) AS name,
        COALESCE(cnl.standaloneSalesUnit, il.salesUnit, 'EA') AS salesUnit,
        COALESCE(cnl.standalonePrice, il.basePrice, 0.0) AS basePrice,
        COALESCE(cnl.standaloneTaxRule, il.taxRule, '') AS taxRule
      FROM ${LocalDatabaseHelper.tableSiCreditNoteLines} cnl
      LEFT JOIN ${LocalDatabaseHelper.tableSiInvoiceLines} il
        ON cnl.originInvoiceId = il.invoiceId AND cnl.originLineNo = il.lineId
      WHERE cnl.creditNoteId = ?
    ''';

    final lines = await db.rawQuery(query, ['CN-STAND-001']);
    expect(lines.length, 1);
    expect(lines.first['sku'], 'SKU-DIRECT');
    expect(lines.first['name'], 'Direct Return Item');
    expect(lines.first['salesUnit'], 'BOX');
    expect(lines.first['basePrice'], 100.0);

    final refunds = await db.query(
      LocalDatabaseHelper.tableSiCreditNoteRefunds,
      where: 'creditNoteId = ?',
      whereArgs: ['CN-STAND-001'],
    );
    expect(refunds.length, 1);
    expect(refunds.first['method'], 'CREDIT');
    expect(refunds.first['amount'], 500.0);
  });
}
