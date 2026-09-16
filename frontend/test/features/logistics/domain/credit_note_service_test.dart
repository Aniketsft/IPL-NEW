import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/credit_note_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/credit_note_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late CreditNoteService service;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);

    // Setup base tables
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
        isPartiallyReversed INTEGER DEFAULT 0,
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
        location TEXT,
        salesUnit TEXT,
        cce0 TEXT,
        taxRule TEXT,
        isFoc INTEGER DEFAULT 0,
        isReversed INTEGER DEFAULT 0
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

    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} (
        itemCode TEXT,
        itemName TEXT,
        lotNumber TEXT,
        warehouse TEXT,
        location TEXT,
        locationType TEXT,
        totalQty REAL DEFAULT 0,
        PRIMARY KEY (itemCode, lotNumber, location, warehouse)
      )
    ''');

    // Dedicated Credit Note Tables
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

    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableSiInvoiceLineReversals} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoiceId TEXT NOT NULL,
        lineId TEXT NOT NULL,
        reversedQty REAL NOT NULL,
        reversalCreditNoteId TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    service = CreditNoteService(dbProvider: () async => db);
  });

  tearDown(() async {
    await db.close();
  });

  test('createReversalCreditNote auto-reverses by original settlement and replenishes stock', () async {
    // Seed initial stock = 50
    await db.insert(LocalDatabaseHelper.tableSalesInvoiceItemStockDetails, {
      'itemCode': 'SKU-001',
      'itemName': 'Widget A',
      'lotNumber': 'LOT-1',
      'warehouse': 'WH1',
      'location': 'LOC1',
      'totalQty': 50.0,
    });

    // Seed invoice with CHEQUE payment
    await db.insert(LocalDatabaseHelper.tableSiInvoices, {
      'invoiceId': 'INV-100',
      'customerCode': 'CUST-A',
      'customerName': 'Customer Alpha',
      'grandTotal': 500.0,
      'createdAt': '2026-06-01T10:00:00',
      'salesSite': 'SCG',
      'isReversed': 0,
    });

    await db.insert(LocalDatabaseHelper.tableSiInvoiceLines, {
      'invoiceId': 'INV-100',
      'sku': 'SKU-001',
      'name': 'Widget A',
      'quantity': 10.0,
      'basePrice': 50.0,
      'total': 500.0,
      'lotNumber': 'LOT-1',
      'warehouse': 'WH1',
      'location': 'LOC1',
      'salesUnit': 'EA',
      'taxRule': 'VAT0',
      'cce0': 'COMMERCIAL',
    });

    await db.insert(LocalDatabaseHelper.tableSiPayments, {
      'invoiceId': 'INV-100',
      'method': 'CHEQUE',
      'amount': 500.0,
      'bankCode': 'MCB',
      'bankName': 'MCB Bank',
      'chequeNumber': 'CHQ-999',
      'chequeDate': '2026-06-05',
    });

    // Execute Reversal
    final creditNote = await service.createReversalCreditNote(
      invoiceId: 'INV-100',
      createdBy: 'agent1',
      deviceId: 'DEV-01',
    );

    expect(creditNote.creditNoteType, CreditNoteType.reversal);
    expect(creditNote.settlementType, 'CHEQUE');
    expect(creditNote.grandTotal, 500.0);
    expect(creditNote.originalInvoiceId, 'INV-100');

    // Verify invoice marked reversed
    final invRows = await db.query(
      LocalDatabaseHelper.tableSiInvoices,
      where: 'invoiceId = ?',
      whereArgs: ['INV-100'],
    );
    expect(invRows.first['isReversed'], 1);

    // Verify stock replenished: 50 + 10 = 60
    final stockRows = await db.query(
      LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
      where: 'itemCode = ? AND lotNumber = ?',
      whereArgs: ['SKU-001', 'LOT-1'],
    );
    expect(stockRows.first['totalQty'], 60.0);

    // Verify refund record created
    final refunds = await db.query(
      LocalDatabaseHelper.tableSiCreditNoteRefunds,
      where: 'creditNoteId = ?',
      whereArgs: [creditNote.creditNoteId],
    );
    expect(refunds.length, 1);
    expect(refunds.first['method'], 'CHEQUE');
    expect(refunds.first['chequeNumber'], 'CHQ-999');
  });

  test('createStandaloneCreditNote rejects QR and saves standalone item lines', () async {
    // Attempt QR -> should throw ArgumentError
    expect(
      () => service.createStandaloneCreditNote(
        salesSite: 'SCG',
        customerCode: 'CUST-B',
        customerName: 'Customer Beta',
        refundMethod: 'QR',
        refundAmount: 200.0,
        items: [],
        createdBy: 'agent1',
      ),
      throwsA(isA<ArgumentError>()),
    );

    // Seed stock
    await db.insert(LocalDatabaseHelper.tableSalesInvoiceItemStockDetails, {
      'itemCode': 'SKU-DIRECT',
      'itemName': 'Direct Item',
      'lotNumber': 'LOT-DIR',
      'warehouse': 'WH1',
      'location': 'LOC1',
      'totalQty': 20.0,
    });

    final creditNote = await service.createStandaloneCreditNote(
      salesSite: 'SCG',
      customerCode: 'CUST-B',
      customerName: 'Customer Beta',
      refundMethod: CreditNoteRefundMethod.cash,
      refundAmount: 200.0,
      createdBy: 'agent1',
      items: [
        CreditNoteLineModel(
          creditNoteId: '',
          lineNo: 1000,
          quantity: 4.0,
          standaloneSku: 'SKU-DIRECT',
          standaloneName: 'Direct Item',
          standaloneSalesUnit: 'EA',
          standalonePrice: 50.0,
          standaloneTaxRule: 'VAT0',
          standaloneLot: 'LOT-DIR',
          standaloneWarehouse: 'WH1',
          standaloneCce0: 'COMMERCIAL',
        ),
      ],
    );

    expect(creditNote.creditNoteType, CreditNoteType.standalone);
    expect(creditNote.settlementType, 'CASH');

    // Stock should be 20 + 4 = 24
    final stockRows = await db.query(
      LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
      where: 'itemCode = ? AND lotNumber = ?',
      whereArgs: ['SKU-DIRECT', 'LOT-DIR'],
    );
    expect(stockRows.first['totalQty'], 24.0);
  });

  test('createCashOnlyCreditNote enforces mandatory linked invoices and balance check', () async {
    // Seed invoices
    await db.insert(LocalDatabaseHelper.tableSiInvoices, {
      'invoiceId': 'INV-LINK-1',
      'customerCode': 'CUST-C',
      'customerName': 'Customer Charlie',
      'grandTotal': 300.0,
      'createdAt': '2026-06-01T10:00:00',
      'salesSite': 'SCG',
      'isReversed': 0,
    });

    // 1. Rejects if linkedInvoiceIds is empty
    expect(
      () => service.createCashOnlyCreditNote(
        salesSite: 'SCG',
        customerCode: 'CUST-C',
        customerName: 'Customer Charlie',
        refundAmount: 100.0,
        linkedInvoiceIds: [],
        createdBy: 'agent1',
      ),
      throwsA(isA<ArgumentError>()),
    );

    // 2. Rejects if refund amount > linked invoices total (300)
    expect(
      () => service.createCashOnlyCreditNote(
        salesSite: 'SCG',
        customerCode: 'CUST-C',
        customerName: 'Customer Charlie',
        refundAmount: 500.0,
        linkedInvoiceIds: ['INV-LINK-1'],
        createdBy: 'agent1',
      ),
      throwsA(isA<ArgumentError>()),
    );

    // 3. Valid Cash Only creation
    final creditNote = await service.createCashOnlyCreditNote(
      salesSite: 'SCG',
      customerCode: 'CUST-C',
      customerName: 'Customer Charlie',
      refundAmount: 250.0,
      linkedInvoiceIds: ['INV-LINK-1'],
      createdBy: 'agent1',
    );

    expect(creditNote.creditNoteType, CreditNoteType.cashOnly);
    expect(creditNote.settlementType, 'CASH');
    expect(creditNote.grandTotal, 250.0);
    expect(creditNote.linkedInvoiceIds, contains('INV-LINK-1'));
  });

  // Partial Reversal Quantity Enforcement Tests
  test('createPartialReversalCreditNote rejects requestedQty exceeding remaining quantity', () async {
    // Seed invoice with quantity 5
    await db.insert(LocalDatabaseHelper.tableSiInvoices, {
      'invoiceId': 'INV-PARTIAL-1',
      'customerCode': 'CUST-P',
      'customerName': 'Partial Customer',
      'grandTotal': 500.0,
      'createdAt': '2026-06-01T10:00:00',
      'salesSite': 'SCG',
      'isReversed': 0,
      'isPartiallyReversed': 0,
    });

    await db.insert(LocalDatabaseHelper.tableSiInvoiceLines, {
      'lineId': 1,
      'invoiceId': 'INV-PARTIAL-1',
      'sku': 'SKU-P1',
      'name': 'Item P1',
      'quantity': 5.0,
      'basePrice': 100.0,
      'total': 500.0,
      'lotNumber': 'LOT-P1',
      'warehouse': 'WH1',
      'location': 'LOC1',
      'salesUnit': 'EA',
      'taxRule': 'VAT0',
      'cce0': 'COMMERCIAL',
    });

    // Attempt to reverse 6 when ordered is 5 -> must throw ArgumentError
    expect(
      () => service.createPartialReversalCreditNote(
        invoiceId: 'INV-PARTIAL-1',
        selectedLines: [
          {'lineId': '1', 'reversedQty': 6.0},
        ],
        createdBy: 'agent1',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('createPartialReversalCreditNote rejects negative or zero quantity', () async {
    await db.insert(LocalDatabaseHelper.tableSiInvoices, {
      'invoiceId': 'INV-PARTIAL-ZERO',
      'customerCode': 'CUST-P',
      'customerName': 'Partial Customer',
      'grandTotal': 500.0,
      'createdAt': '2026-06-01T10:00:00',
      'salesSite': 'SCG',
      'isReversed': 0,
      'isPartiallyReversed': 0,
    });

    await db.insert(LocalDatabaseHelper.tableSiInvoiceLines, {
      'lineId': 2,
      'invoiceId': 'INV-PARTIAL-ZERO',
      'sku': 'SKU-P2',
      'name': 'Item P2',
      'quantity': 5.0,
      'basePrice': 100.0,
      'total': 500.0,
      'lotNumber': 'LOT-P2',
      'warehouse': 'WH1',
      'location': 'LOC1',
      'salesUnit': 'EA',
      'taxRule': 'VAT0',
      'cce0': 'COMMERCIAL',
    });

    // Zero quantity
    expect(
      () => service.createPartialReversalCreditNote(
        invoiceId: 'INV-PARTIAL-ZERO',
        selectedLines: [
          {'lineId': '2', 'reversedQty': 0.0},
        ],
        createdBy: 'agent1',
      ),
      throwsA(isA<ArgumentError>()),
    );

    // Negative quantity
    expect(
      () => service.createPartialReversalCreditNote(
        invoiceId: 'INV-PARTIAL-ZERO',
        selectedLines: [
          {'lineId': '2', 'reversedQty': -2.0},
        ],
        createdBy: 'agent1',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('createPartialReversalCreditNote tracks remaining quantity across multiple reversals and prevents exceeding remaining', () async {
    await db.insert(LocalDatabaseHelper.tableSalesInvoiceItemStockDetails, {
      'itemCode': 'SKU-MULTI',
      'itemName': 'Multi Item',
      'lotNumber': 'LOT-M',
      'warehouse': 'WH1',
      'location': 'LOC1',
      'totalQty': 10.0,
    });

    await db.insert(LocalDatabaseHelper.tableSiInvoices, {
      'invoiceId': 'INV-MULTI',
      'customerCode': 'CUST-M',
      'customerName': 'Multi Customer',
      'grandTotal': 1000.0,
      'createdAt': '2026-06-01T10:00:00',
      'salesSite': 'SCG',
      'isReversed': 0,
      'isPartiallyReversed': 0,
    });

    await db.insert(LocalDatabaseHelper.tableSiInvoiceLines, {
      'lineId': 10,
      'invoiceId': 'INV-MULTI',
      'sku': 'SKU-MULTI',
      'name': 'Multi Item',
      'quantity': 10.0,
      'basePrice': 100.0,
      'total': 1000.0,
      'lotNumber': 'LOT-M',
      'warehouse': 'WH1',
      'location': 'LOC1',
      'salesUnit': 'EA',
      'taxRule': 'VAT0',
      'cce0': 'COMMERCIAL',
    });

    // Reversal 1: Reverse 4 out of 10
    final cn1 = await service.createPartialReversalCreditNote(
      invoiceId: 'INV-MULTI',
      selectedLines: [
        {'lineId': '10', 'reversedQty': 4.0},
      ],
      createdBy: 'agent1',
    );

    expect(cn1.grandTotal, 400.0);

    // Verify invoice is marked as partially reversed
    final invRows1 = await db.query(
      LocalDatabaseHelper.tableSiInvoices,
      where: 'invoiceId = ?',
      whereArgs: ['INV-MULTI'],
    );
    expect(invRows1.first['isPartiallyReversed'], 1);
    expect(invRows1.first['isReversed'], 0);

    // Verify stock replenished by 4 (10 + 4 = 14)
    final stock1 = await db.query(
      LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
      where: 'itemCode = ? AND lotNumber = ?',
      whereArgs: ['SKU-MULTI', 'LOT-M'],
    );
    expect(stock1.first['totalQty'], 14.0);

    // Reversal 2 Attempt: Try to reverse 7 (only 6 remaining) -> must fail
    expect(
      () => service.createPartialReversalCreditNote(
        invoiceId: 'INV-MULTI',
        selectedLines: [
          {'lineId': '10', 'reversedQty': 7.0},
        ],
        createdBy: 'agent1',
      ),
      throwsA(isA<ArgumentError>()),
    );

    // Reversal 2 Valid: Reverse remaining 6
    final cn2 = await service.createPartialReversalCreditNote(
      invoiceId: 'INV-MULTI',
      selectedLines: [
        {'lineId': '10', 'reversedQty': 6.0},
      ],
      createdBy: 'agent1',
    );

    expect(cn2.grandTotal, 600.0);

    // Now all 10 have been reversed -> invoice should now be marked isReversed = 1
    final invRows2 = await db.query(
      LocalDatabaseHelper.tableSiInvoices,
      where: 'invoiceId = ?',
      whereArgs: ['INV-MULTI'],
    );
    expect(invRows2.first['isReversed'], 1);
    expect(invRows2.first['isPartiallyReversed'], 0);

    // Stock should now be 14 + 6 = 20
    final stock2 = await db.query(
      LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
      where: 'itemCode = ? AND lotNumber = ?',
      whereArgs: ['SKU-MULTI', 'LOT-M'],
    );
    expect(stock2.first['totalQty'], 20.0);
  });

  test('createReversalCreditNote rejects full reversal if invoice is partially reversed', () async {
    await db.insert(LocalDatabaseHelper.tableSiInvoices, {
      'invoiceId': 'INV-PARTIAL-LOCKED',
      'customerCode': 'CUST-L',
      'customerName': 'Locked Customer',
      'grandTotal': 500.0,
      'createdAt': '2026-06-01T10:00:00',
      'salesSite': 'SCG',
      'isReversed': 0,
      'isPartiallyReversed': 1,
    });

    expect(
      () => service.createReversalCreditNote(
        invoiceId: 'INV-PARTIAL-LOCKED',
        createdBy: 'agent1',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
