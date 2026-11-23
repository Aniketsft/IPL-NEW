import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';
import 'package:enterprise_auth_mobile/core/services/printer_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/credit_note_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/eod_report_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/transaction_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/sales_invoice_product_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/transaction_history_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/models/stock_status.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/credit_note_pdf_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/sales_report_pdf_service.dart';

class _FakeNetworkService implements NetworkService {
  @override
  late final Dio dio;

  @override
  VoidCallback? onUnauthorized;

  _FakeNetworkService(this.dio);
}

Future<Database> _openReturnTestDb() async {
  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
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
      siteCode TEXT DEFAULT '',
      stockStatus TEXT DEFAULT 'A',
      isSynced INTEGER DEFAULT 1,
      createdAt TEXT,
      updatedAt TEXT,
      deviceId TEXT,
      PRIMARY KEY (itemCode, lotNumber, location, warehouse, stockStatus)
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tableSiInvoices} (
      invoiceId TEXT PRIMARY KEY,
      customerCode TEXT,
      customerName TEXT,
      totalVat REAL DEFAULT 0.0,
      totalDiscount REAL DEFAULT 0.0,
      grandTotal REAL DEFAULT 0.0,
      createdAt TEXT,
      status TEXT,
      isSynced INTEGER DEFAULT 0,
      transactionType TEXT DEFAULT 'INVOICE',
      isReversed INTEGER DEFAULT 0,
      isPartiallyReversed INTEGER DEFAULT 0,
      reference TEXT,
      salesSite TEXT,
      x3DocumentId TEXT,
      createdByUserName TEXT,
      deviceId TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tableSiInvoiceLines} (
      lineId INTEGER,
      invoiceId TEXT,
      sku TEXT,
      name TEXT,
      salesUnit TEXT,
      quantity REAL,
      basePrice REAL DEFAULT 0.0,
      discountAmountFlat REAL DEFAULT 0.0,
      vatRatePercent REAL DEFAULT 0.0,
      taxRule TEXT,
      lotNumber TEXT,
      warehouse TEXT,
      location TEXT,
      cce0 TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tableSiInvoiceLineReversals} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoiceId TEXT,
      lineId TEXT,
      reversedQty REAL,
      reversalCreditNoteId TEXT,
      createdAt TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tableSiCreditNotes} (
      creditNoteId TEXT PRIMARY KEY,
      creditNoteType TEXT,
      x3CreditNoteType TEXT,
      salesSite TEXT,
      customerCode TEXT,
      customerName TEXT,
      currency TEXT,
      grandTotal REAL,
      originalInvoiceId TEXT,
      settlementType TEXT,
      reference TEXT,
      isSynced INTEGER DEFAULT 0,
      x3DocumentId TEXT,
      createdAt TEXT,
      createdBy TEXT,
      deviceId TEXT,
      reason TEXT,
      salesRep TEXT,
      transactionMode TEXT,
      stockTransaction INTEGER DEFAULT 0
    )
  ''');

  await db.execute('''
    CREATE TABLE ${LocalDatabaseHelper.tableSiCreditNoteLines} (
      lineId INTEGER PRIMARY KEY AUTOINCREMENT,
      creditNoteId TEXT,
      lineNo INTEGER,
      quantity REAL,
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

  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ReturnCondition & StockStatus mapping', () {
    test('maps Normal -> A, Damaged -> R, Expired -> Q', () {
      expect(ReturnCondition.normal.stockStatus, 'A');
      expect(ReturnCondition.normal.reasonCode, 'RET');
      expect(ReturnCondition.normal.status, StockStatus.approved);

      expect(ReturnCondition.damaged.stockStatus, 'R');
      expect(ReturnCondition.damaged.reasonCode, 'DEF');
      expect(ReturnCondition.damaged.status, StockStatus.rejected);

      expect(ReturnCondition.expired.stockStatus, 'Q');
      expect(ReturnCondition.expired.reasonCode, 'EXP');
      expect(ReturnCondition.expired.status, StockStatus.quarantine);

      expect(StockStatus.rejected.shortLabel, 'Status R • Damaged');
      expect(StockStatus.fromCode('Q1'), StockStatus.quarantine);
      expect(StockStatus.fromCode('R1'), StockStatus.rejected);
      expect(StockStatus.fromReturnReason('RET'), StockStatus.approved);
      expect(StockStatus.fromReturnReason('DEF'), StockStatus.rejected);
      expect(StockStatus.fromReturnReason('EXP'), StockStatus.quarantine);
    });
  });

  group('PDF & Report status rendering', () {
    test('CreditNotePdfService renders exact A, R, and Q badges even when resolvedLines is empty', () async {
      final cn = CreditNoteModel(
        creditNoteId: 'HRSCG08112600001',
        creditNoteType: 'RETURN',
        x3CreditNoteType: 'RTN',
        salesSite: 'SCG',
        customerCode: 'C001',
        customerName: 'Alpha Market',
        currency: 'MUR',
        grandTotal: 450.0,
        settlementType: 'CASH',
        reason: 'EXP',
        stockTransaction: 1,
        createdAt: '2026-11-18T10:00:00',
        createdBy: 'rep_1',
        lines: [
          CreditNoteLineModel(
            creditNoteId: 'HRSCG08112600001',
            lineNo: 1000,
            quantity: 1,
            standaloneSku: 'SKU-A',
            standaloneName: 'Normal Chicken',
            standaloneSalesUnit: 'EA',
            standalonePrice: 100.0,
            standaloneLot: 'LOT-A',
            stockStatus: 'A',
          ),
          CreditNoteLineModel(
            creditNoteId: 'HRSCG08112600001',
            lineNo: 2000,
            quantity: 2,
            standaloneSku: 'SKU-R',
            standaloneName: 'Damaged Chicken',
            standaloneSalesUnit: 'EA',
            standalonePrice: 100.0,
            standaloneLot: 'LOT-R',
            stockStatus: 'R',
          ),
          CreditNoteLineModel(
            creditNoteId: 'HRSCG08112600001',
            lineNo: 3000,
            quantity: 1,
            standaloneSku: 'SKU-Q',
            standaloneName: 'Expired Chicken',
            standaloneSalesUnit: 'EA',
            standalonePrice: 150.0,
            standaloneLot: 'LOT-Q',
            stockStatus: 'Q',
          ),
        ],
      );

      final bytes = await CreditNotePdfService().generateCreditNotePdf(
        pageFormat: PdfPageFormat.a4,
        creditNote: cn,
        resolvedLines: const [],
      );
      final lines = PrinterService.lookupPdfThermalLines(bytes) ?? [];
      final text = lines.map((l) => l.text).join('\n');

      expect(text, contains('STA: A - APPROVED / SELLABLE'));
      expect(text, contains('STA: R - REJECTED / DAMAGED'));
      expect(text, contains('STA: Q - QUARANTINE / EXPIRED'));
    });

    test('SalesReportPdfService separates Stock Preview, Summary, and EOD by A / R / Q', () async {
      final service = SalesReportPdfService();

      // 1. Stock Preview
      final stockBytes = await service.generateStockPreviewPdf(
        warehouseLabel: 'N3',
        items: [
          SalesInvoiceProductModel(
            sku: 'SKU-1',
            name: 'Sellable Item',
            stockQty: 12,
            warehouse: 'N3',
            salesUnit: 'EA',
            stockStatus: 'A',
          ),
          SalesInvoiceProductModel(
            sku: 'SKU-1',
            name: 'Damaged Item',
            stockQty: 3,
            warehouse: 'N3',
            salesUnit: 'EA',
            stockStatus: 'R1',
          ),
          SalesInvoiceProductModel(
            sku: 'SKU-1',
            name: 'Expired Item',
            stockQty: 5,
            warehouse: 'N3',
            salesUnit: 'EA',
            stockStatus: 'Q1',
          ),
        ],
      );
      final stockText =
          (PrinterService.lookupPdfThermalLines(stockBytes) ?? [])
              .map((l) => l.text)
              .join('\n');
      expect(stockText, contains('[A] APPROVED / SELLABLE STOCK'));
      expect(stockText, contains('[R] DAMAGED / REJECTED STOCK'));
      expect(stockText, contains('[Q] QUARANTINE / EXPIRED STOCK'));
      expect(stockText, contains('SUBTOTAL'));

      // 2. Sales Summary
      final summaryBytes = await service.generateInvoiceSummaryPdf(
        reportDate: '18/11/2026',
        invoices: const [
          TransactionModel(
            id: 'INV-1',
            type: 'INVOICE',
            customerCode: 'C1',
            customerName: 'Cust',
            grandTotal: 1000,
            createdAt: '2026-11-18T09:00:00',
            status: 'CONFIRMED',
            isSynced: 0,
            isReversed: 0,
            auditMetadata: AuditMetadata(),
          ),
          TransactionModel(
            id: 'HR1',
            type: 'RETURN',
            customerCode: 'C1',
            customerName: 'Cust',
            grandTotal: 300,
            createdAt: '2026-11-18T10:00:00',
            status: 'CONFIRMED',
            isSynced: 0,
            isReversed: 0,
            auditMetadata: AuditMetadata(),
          ),
        ],
        productRows: const [
          {
            'sku': 'SKU-1',
            'name': 'Chicken Breast',
            'uom': 'EA',
            'salesQty': 10.0,
            'returnQty': 4.0,
            'returnQtyA': 1.0,
            'returnQtyR': 1.0,
            'returnQtyQ': 2.0,
            'salesValue': 1000.0,
            'returnValue': 400.0,
            'returnValueA': 100.0,
            'returnValueR': 100.0,
            'returnValueQ': 200.0,
          },
        ],
      );
      final summaryText =
          (PrinterService.lookupPdfThermalLines(summaryBytes) ?? [])
              .map((l) => l.text)
              .join('\n');
      expect(summaryText, contains('Return Sta: A:1  R:1  Q:2'));
      expect(summaryText, contains('[A] Normal / Sellable'));
      expect(summaryText, contains('[R] Damaged'));
      expect(summaryText, contains('[Q] Expired / Quarantine'));
      expect(summaryText, contains('Returns: 1'));

      // 3. EOD Report
      final eodBytes = await service.generateEodReportPdf(
        const EodReportModel(
          reportDate: '18.11.2026',
          reportTime: '17:00',
          operatorName: 'rep_1',
          registerId: 'SCG',
          salesCount: 1,
          salesGross: 1000,
          totalVat: 0,
          totalDiscount: 0,
          returnsCount: 1,
          returnsGross: 300,
          cancelledReceipts: [],
          cashBalance: EodCashBalance(cashGrossSales: 1000, withdrawals: 0),
          vatSummaries: [],
          paymentSummaries: [],
          returnStatusBreakdowns: [
            EodReturnStatusBreakdown(stockStatus: 'A', lineCount: 1, totalQty: 1, totalAmount: 100),
            EodReturnStatusBreakdown(stockStatus: 'R', lineCount: 1, totalQty: 1, totalAmount: 100),
            EodReturnStatusBreakdown(stockStatus: 'Q', lineCount: 1, totalQty: 2, totalAmount: 100),
          ],
        ),
      );
      final eodText =
          (PrinterService.lookupPdfThermalLines(eodBytes) ?? [])
              .map((l) => l.text)
              .join('\n');
      expect(eodText, contains('RETURNS BY STOCK STATUS:'));
      expect(eodText, contains('[A] Normal / Sellable (1)'));
      expect(eodText, contains('[R] Damaged / Rejected (1)'));
      expect(eodText, contains('[Q] Expired / Quarantine (2)'));
    });
  });

  group('SQLite repositories & stock ledger sync', () {
    late Database db;
    late TransactionHistoryRepository historyRepo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await _openReturnTestDb();
      historyRepo = TransactionHistoryRepository(dbProvider: () async => db);
    });

    tearDown(() async {
      LocalDatabaseHelper.setTestDatabase(null);
      await db.close();
    });

    test('TransactionHistoryRepository preserves A/R/Q stockStatus in lines and sales summary', () async {
      await db.insert(LocalDatabaseHelper.tableSiInvoices, {
        'invoiceId': 'HISC01',
        'customerCode': 'C1',
        'customerName': 'Buyer',
        'grandTotal': 500.0,
        'createdAt': '2026-11-18T09:00:00',
        'status': 'PAID',
        'transactionType': 'INVOICE',
        'isSynced': 0,
      });
      await db.insert(LocalDatabaseHelper.tableSiInvoiceLines, {
        'lineId': 1,
        'invoiceId': 'HISC01',
        'sku': 'SKU-1',
        'name': 'Prod 1',
        'salesUnit': 'EA',
        'quantity': 5.0,
        'basePrice': 100.0,
        'taxRule': 'ZERO',
        'lotNumber': 'L1',
        'warehouse': 'N3',
        'location': 'N3',
        'cce0': 'COM',
      });

      await db.insert(LocalDatabaseHelper.tableSiCreditNotes, {
        'creditNoteId': 'HRPOD03112600001',
        'creditNoteType': 'RETURN',
        'x3CreditNoteType': 'RTN',
        'salesSite': 'SCG',
        'customerCode': 'C1',
        'customerName': 'Buyer',
        'currency': 'MUR',
        'grandTotal': 300.0,
        'originalInvoiceId': 'HISC01',
        'settlementType': 'CASH',
        'createdAt': '2026-11-18T11:00:00',
        'createdBy': 'rep_1',
        'stockTransaction': 1,
      });

      await db.insert(LocalDatabaseHelper.tableSiCreditNoteLines, {
        'creditNoteId': 'HRPOD03112600001',
        'lineNo': 1000,
        'quantity': 1.0,
        'standaloneSku': 'SKU-1',
        'standaloneName': 'Prod 1',
        'standaloneSalesUnit': 'EA',
        'standalonePrice': 100.0,
        'standaloneLot': 'L1',
        'standaloneWarehouse': 'N3',
        'stockStatus': 'A',
        'returnCondition': 'RET',
        'location': 'N3',
      });
      await db.insert(LocalDatabaseHelper.tableSiCreditNoteLines, {
        'creditNoteId': 'HRPOD03112600001',
        'lineNo': 2000,
        'quantity': 1.0,
        'standaloneSku': 'SKU-1',
        'standaloneName': 'Prod 1',
        'standaloneSalesUnit': 'EA',
        'standalonePrice': 100.0,
        'standaloneLot': 'L1',
        'standaloneWarehouse': 'N3',
        'stockStatus': 'R',
        'returnCondition': 'DEF',
        'location': 'N3',
      });
      await db.insert(LocalDatabaseHelper.tableSiCreditNoteLines, {
        'creditNoteId': 'HRPOD03112600001',
        'lineNo': 3000,
        'quantity': 2.0,
        'standaloneSku': 'SKU-1',
        'standaloneName': 'Prod 1',
        'standaloneSalesUnit': 'EA',
        'standalonePrice': 50.0,
        'standaloneLot': 'L2',
        'standaloneWarehouse': 'N3',
        'stockStatus': 'Q',
        'returnCondition': 'EXP',
        'location': 'N3',
      });

      final returnsOnly = await historyRepo.getTransactions(type: 'RETURN');
      expect(returnsOnly.length, 1);
      expect(returnsOnly.first.type, 'RETURN');

      final lines = await historyRepo.getTransactionLines('HRPOD03112600001');
      expect(lines.length, 3);
      expect(lines.map((l) => l['stockStatus']).toList(), ['A', 'R', 'Q']);

      final summary = await historyRepo.getSalesSummaryRows(
        startDate: '2026-11-18T00:00:00',
        endDate: '2026-11-18T23:59:59',
      );
      expect(summary.length, 1);
      expect(summary.first['salesQty'], 5.0);
      expect(summary.first['returnQty'], 4.0);
      expect(summary.first['returnQtyA'], 1.0);
      expect(summary.first['returnQtyR'], 1.0);
      expect(summary.first['returnQtyQ'], 2.0);
    });

    test('syncSalesInvoiceItemStockDetails applies unsynced A/R/Q returns into matching status buckets', () async {
      await db.insert(LocalDatabaseHelper.tableSiInvoices, {
        'invoiceId': 'HIPOD01',
        'customerCode': 'C1',
        'customerName': 'Buyer',
        'grandTotal': 200.0,
        'createdAt': '2026-11-18T08:00:00',
        'status': 'PAID',
        'isSynced': 0,
        'transactionType': 'INVOICE',
        'isReversed': 0,
      });
      await db.insert(LocalDatabaseHelper.tableSiInvoiceLines, {
        'lineId': 1,
        'invoiceId': 'HIPOD01',
        'sku': 'SKU-1',
        'lotNumber': 'LOT1',
        'warehouse': 'N3',
        'location': 'N3',
        'quantity': 2.0,
      });

      await db.insert(LocalDatabaseHelper.tableSiCreditNotes, {
        'creditNoteId': 'HRPOD01',
        'creditNoteType': 'RETURN',
        'customerCode': 'C1',
        'customerName': 'Buyer',
        'grandTotal': 300.0,
        'createdAt': '2026-11-18T09:00:00',
        'isSynced': 0,
        'stockTransaction': 1,
      });
      await db.insert(LocalDatabaseHelper.tableSiCreditNoteLines, {
        'creditNoteId': 'HRPOD01',
        'lineNo': 1000,
        'quantity': 1.0,
        'standaloneSku': 'SKU-1',
        'standaloneName': 'Prod 1',
        'standaloneSalesUnit': 'EA',
        'standalonePrice': 100.0,
        'standaloneLot': 'LOT1',
        'standaloneWarehouse': 'N3',
        'stockStatus': 'A',
        'returnCondition': 'RET',
        'location': 'N3',
      });
      await db.insert(LocalDatabaseHelper.tableSiCreditNoteLines, {
        'creditNoteId': 'HRPOD01',
        'lineNo': 2000,
        'quantity': 2.0,
        'standaloneSku': 'SKU-1',
        'standaloneName': 'Prod 1',
        'standaloneSalesUnit': 'EA',
        'standalonePrice': 100.0,
        'standaloneLot': 'LOT1',
        'standaloneWarehouse': 'N3',
        'stockStatus': 'R',
        'returnCondition': 'DEF',
        'location': 'N3',
      });
      await db.insert(LocalDatabaseHelper.tableSiCreditNoteLines, {
        'creditNoteId': 'HRPOD01',
        'lineNo': 3000,
        'quantity': 3.0,
        'standaloneSku': 'SKU-2',
        'standaloneName': 'Prod 2',
        'standaloneSalesUnit': 'EA',
        'standalonePrice': 50.0,
        'standaloneLot': 'LOT2',
        'standaloneWarehouse': 'N3',
        'stockStatus': 'Q',
        'returnCondition': 'EXP',
        'location': 'N3',
      });

      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: [
                  {
                    'warehouse': 'N3',
                    'warehouseName': 'Lorry N3',
                    'location': 'N3',
                    'locationType': 'VAN',
                    'itemCode': 'SKU-1',
                    'itemName': 'Prod 1',
                    'totalQty': 10.0,
                    'lotNumber': 'LOT1',
                    'taxLevel': 'VAT',
                    'cce0': 'COM',
                    'salesUnit': 'EA',
                    'barcode': '111',
                    'siteCode': 'SCG',
                    'stockStatus': 'A',
                  },
                  {
                    'warehouse': 'N3',
                    'warehouseName': 'Lorry N3',
                    'location': 'N3',
                    'locationType': 'VAN',
                    'itemCode': 'SKU-2',
                    'itemName': 'Prod 2',
                    'totalQty': 1.0,
                    'lotNumber': 'LOT2',
                    'taxLevel': 'VAT',
                    'cce0': 'COM',
                    'salesUnit': 'EA',
                    'barcode': '222',
                    'siteCode': 'SCG',
                    'stockStatus': 'Q',
                  },
                ],
              ),
            );
          },
        ),
      );

      final stockRepo = SalesInvoiceProductRepository(_FakeNetworkService(dio));
      await stockRepo.syncSalesInvoiceItemStockDetails('SCG');

      final rows = await db.query(
        LocalDatabaseHelper.tableSalesInvoiceItemStockDetails,
        orderBy: 'itemCode ASC, stockStatus ASC',
      );

      double qtyFor(String sku, String status) => rows
          .where((r) => r['itemCode'] == sku && r['stockStatus'] == status)
          .fold<double>(0.0, (s, r) => s + ((r['totalQty'] as num?)?.toDouble() ?? 0.0));

      expect(qtyFor('SKU-1', 'A'), 9.0);
      expect(qtyFor('SKU-1', 'R'), 2.0);
      expect(qtyFor('SKU-1', 'Q'), 0.0);
      expect(qtyFor('SKU-2', 'Q'), 4.0);
    });
  });
}
