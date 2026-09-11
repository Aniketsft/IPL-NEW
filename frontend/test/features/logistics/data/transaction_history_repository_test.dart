import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/credit_note_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/transaction_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/transaction_history_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/credit_note_pdf_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TransactionHistoryRepository repository;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    repository = TransactionHistoryRepository(dbProvider: () async => db);

    // 1. Create Invoices table
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

    // 2. Create Invoice Lines table
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

    // 3. Create Payments table
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

    // 4. Create Stock table
    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        itemCode TEXT,
        itemName TEXT,
        lotNumber TEXT,
        warehouse TEXT,
        location TEXT,
        totalQty REAL,
        taxLevel TEXT,
        cce0 TEXT,
        isSynced INTEGER DEFAULT 1,
        createdAt TEXT
      )
    ''');

    // 5. Create Credit Note tables
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
        createdAt TEXT NOT NULL,
        createdBy TEXT,
        deviceId TEXT,
        x3DocumentId TEXT,
        syncErrorMessage TEXT
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
        chequeDate TEXT,
        FOREIGN KEY (creditNoteId) REFERENCES ${LocalDatabaseHelper.tableSiCreditNotes} (creditNoteId) ON DELETE CASCADE
      )
    ''');
  });

  tearDown(() async {
    await db.close();
  });

  test('TransactionHistoryRepository fetches both invoices and credit notes', () async {
    // Insert test invoice
    await db.insert(LocalDatabaseHelper.tableSiInvoices, {
      'invoiceId': 'INV-001',
      'customerCode': 'CUST01',
      'customerName': 'Supermarket A',
      'grandTotal': 1500.0,
      'createdAt': '2026-09-09T08:00:00',
      'status': 'PAID',
      'transactionType': 'INVOICE',
    });

    // Insert test credit note
    await db.insert(LocalDatabaseHelper.tableSiCreditNotes, {
      'creditNoteId': 'CN-INV-001',
      'creditNoteType': CreditNoteType.reversal,
      'salesSite': 'SCG',
      'customerCode': 'CUST01',
      'customerName': 'Supermarket A',
      'grandTotal': 1500.0,
      'settlementType': 'CASH',
      'createdAt': '2026-09-09T09:00:00',
      'createdBy': 'rep_john',
      'deviceId': 'DEV-1',
    });

    // 1. Fetch All
    final all = await repository.getTransactions(type: 'ALL');
    expect(all.length, 2);
    expect(all.first.id, 'CN-INV-001'); // Most recent first
    expect(all.last.id, 'INV-001');

    // 2. Filter CREDIT_NOTE
    final cnList = await repository.getTransactions(type: 'CREDIT_NOTE');
    expect(cnList.length, 1);
    expect(cnList.first.id, 'CN-INV-001');
    expect(cnList.first.type, 'CREDIT_NOTE');

    // 3. Filter INVOICE
    final invList = await repository.getTransactions(type: 'INVOICE');
    expect(invList.length, 1);
    expect(invList.first.id, 'INV-001');
  });

  test('cancelInvoice executes reversal credit note and restocks item', () async {
    // Seed initial stock
    await db.insert(LocalDatabaseHelper.tableSalesInvoiceItemStockDetails, {
      'itemCode': '890774',
      'itemName': 'Huggies Nappies',
      'lotNumber': 'LOT-ABC',
      'warehouse': 'SCG',
      'location': 'QUAI',
      'totalQty': 10.0,
    });

    // Insert invoice to be reversed
    await db.insert(LocalDatabaseHelper.tableSiInvoices, {
      'invoiceId': 'INV-REVERSE-1',
      'customerCode': 'HD999',
      'customerName': 'Hypermarket Central',
      'grandTotal': 3100.0,
      'createdAt': '2026-09-09T07:30:00',
      'status': 'PAID',
      'transactionType': 'INVOICE',
      'salesSite': 'SCG',
      'isReversed': 0,
    });

    // Insert invoice line (10 qty sold)
    await db.insert(LocalDatabaseHelper.tableSiInvoiceLines, {
      'invoiceId': 'INV-REVERSE-1',
      'sku': '890774',
      'name': 'Huggies Nappies',
      'quantity': 10.0,
      'basePrice': 310.0,
      'total': 3100.0,
      'lotNumber': 'LOT-ABC',
      'warehouse': 'SCG',
      'location': 'QUAI',
      'isReversed': 0,
    });

    // Insert original payment as CHEQUE
    await db.insert(LocalDatabaseHelper.tableSiPayments, {
      'invoiceId': 'INV-REVERSE-1',
      'method': 'CHEQUE',
      'amount': 3100.0,
      'bankCode': 'MCB',
      'bankName': 'MCB Port Louis',
      'chequeNumber': 'CHQ-8899',
      'chequeDate': '2026-09-09',
    });

    final txModel = TransactionModel(
      id: 'INV-REVERSE-1',
      type: 'INVOICE',
      customerCode: 'HD999',
      customerName: 'Hypermarket Central',
      grandTotal: 3100.0,
      createdAt: '2026-09-09T07:30:00',
      status: 'PAID',
      isSynced: 0,
      isReversed: 0,
      auditMetadata: const AuditMetadata(createdByUserName: 'agent_tester', deviceId: 'DEV-MOBILE'),
    );

    // Execute cancelInvoice
    final creditNote = await repository.cancelInvoice(txModel);

    expect(creditNote.creditNoteId, 'CN-INV-REVERSE-1');
    expect(creditNote.settlementType, 'CHEQUE'); // Auto-reversed by CHEQUE
    expect(creditNote.grandTotal, 3100.0);

    // Verify origin invoice is marked reversed
    final invCheck = await db.query(LocalDatabaseHelper.tableSiInvoices, where: 'invoiceId = ?', whereArgs: ['INV-REVERSE-1']);
    expect(invCheck.first['isReversed'], 1);

    // Verify stock is replenished (10 + 10 = 20)
    final stockCheck = await db.query(
      LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
      where: 'itemCode = ? AND lotNumber = ?',
      whereArgs: ['890774', 'LOT-ABC'],
    );
    expect((stockCheck.first['totalQty'] as num).toDouble(), 20.0);

    // Verify credit note refund method is CHEQUE
    final refundCheck = await db.query(
      LocalDatabaseHelper.tableSiCreditNoteRefunds,
      where: 'creditNoteId = ?',
      whereArgs: ['CN-INV-REVERSE-1'],
    );
    expect(refundCheck.length, 1);
    expect(refundCheck.first['method'], 'CHEQUE');
    expect(refundCheck.first['chequeNumber'], 'CHQ-8899');

    // Verify getTransactionLines resolves the credit note lines
    final lines = await repository.getTransactionLines('CN-INV-REVERSE-1');
    expect(lines.length, 1);
    expect(lines.first['sku'], '890774');
    expect((lines.first['quantity'] as num).toDouble(), 10.0);
  });

  test('CreditNotePdfService produces valid 80mm continuous thermal receipt bytes', () async {
    final pdfService = CreditNotePdfService();
    final creditNote = CreditNoteModel(
      creditNoteId: 'CN-TEST-99',
      creditNoteType: CreditNoteType.standalone,
      x3CreditNoteType: 'CRN',
      salesSite: 'SCG',
      customerCode: 'CUST-009',
      customerName: 'Corner Store Ltd',
      currency: 'MUR',
      grandTotal: 1250.0,
      settlementType: 'CASH',
      reference: 'CN-TEST-99',
      isSynced: 0,
      createdAt: '2026-09-09T10:00:00',
      createdBy: 'rep_tester',
      deviceId: 'DEV-POS-1',
    );

    final resolvedLines = [
      {
        'sku': '10001',
        'name': 'Mineral Water 1L',
        'quantity': 25.0,
        'basePrice': 50.0,
        'lotNumber': 'LOT-WAT',
        'warehouse': 'SCG',
        'location': 'QUAI',
      }
    ];

    final pdfBytes = await pdfService.generateCreditNotePdf(
      pageFormat: const PdfPageFormat(288, double.infinity, marginAll: 10),
      creditNote: creditNote,
      resolvedLines: resolvedLines,
    );

    expect(pdfBytes, isNotNull);
    expect(pdfBytes.isNotEmpty, isTrue);
    // Standard PDF header signature check: %PDF-
    final header = String.fromCharCodes(pdfBytes.take(5));
    expect(header, '%PDF-');
  });
}
