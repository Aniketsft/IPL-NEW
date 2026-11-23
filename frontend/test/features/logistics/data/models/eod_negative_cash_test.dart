import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/eod_report_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/sales_report_pdf_service.dart';
import 'package:enterprise_auth_mobile/core/services/printer_service.dart';

void main() {
  sqfliteFfiInit();

  group('Negative Cash in Hand & Shortfall Tracking', () {
    test('EodReportModel preserves negative netPhysicalCashInHand and separates shortfall from cheques', () {
      final report = EodReportModel(
        reportDate: '17.11.2026',
        reportTime: '17:00',
        operatorName: 'salesman1',
        registerId: 'HM1',
        salesCount: 1,
        salesGross: 1000.0,
        totalVat: 0.0,
        totalDiscount: 0.0,
        returnsCount: 1,
        returnsGross: 500.0,
        cancelledReceipts: const [],
        cashBalance: const EodCashBalance(
          cashGrossSales: 0.0,
          withdrawals: 500.0,
        ),
        vatSummaries: const [],
        paymentSummaries: const [],
        cashInvoices: const [
          EodInvoiceItem(
            invoiceId: 'HIPOD57112600001',
            customerCode: 'C001',
            customerName: 'Cheque Customer',
            grandTotal: 1000.0,
            paymentTerm: 'CHQ',
            tenderSummary: 'CHEQUE',
            chequeAmount: 1000.0,
            createdAt: '2026-11-17T10:00:00',
            isCredit: false,
          ),
        ],
        chequeList: const [
          EodChequeDetail(
            chequeNumber: '123456',
            bankName: 'MCB',
            customerName: 'Cheque Customer',
            source: 'INV: 2600001',
            amount: 1000.0,
          ),
        ],
        cashRefundedOnReturns: 500.0,
        cashShortfallRefunds: const [
          EodCashShortfallItem(
            creditNoteId: 'HCPOD57112600001',
            customerName: 'Return Customer',
            refundAmount: 500.0,
            cashInHandBefore: 0.0,
            shortfallAmount: 500.0,
            createdAt: '2026-11-17T11:00:00',
          ),
        ],
      );

      expect(report.netPhysicalCashInHand, -500.0);
      expect(report.isNegativeCashInHand, isTrue);
      expect(report.physicalCashToHandOver, 0.0);
      expect(report.cashShortfallAmount, 500.0);
      expect(report.cashBalance.expectedBalance, -500.0);
      expect(report.recordedRefundShortfallTotal, 500.0);
      // Cheque handover is not reduced by negative cash shortfall
      expect(report.grandTotalFundsCollected, 1000.0);
    });

    test('SalesReportPdfService prints negative NET CASH IN HAND and CASH SHORTFALL without deducting from cheques', () async {
      final report = EodReportModel(
        reportDate: '17.11.2026',
        reportTime: '17:00',
        operatorName: 'salesman1',
        registerId: 'HM1',
        salesCount: 0,
        salesGross: 0.0,
        totalVat: 0.0,
        totalDiscount: 0.0,
        returnsCount: 1,
        returnsGross: 350.0,
        cancelledReceipts: const [],
        cashBalance: const EodCashBalance(cashGrossSales: 0.0, withdrawals: 350.0),
        vatSummaries: const [],
        paymentSummaries: const [],
        chequeList: const [
          EodChequeDetail(
            chequeNumber: '999',
            bankName: 'MCB',
            customerName: 'Test Cust',
            source: 'OPEN: SIH1',
            amount: 800.0,
          ),
        ],
        cashRefundedOnReturns: 350.0,
        cashShortfallRefunds: const [
          EodCashShortfallItem(
            creditNoteId: 'HCPOD57112600001',
            customerName: 'Test Cust',
            refundAmount: 350.0,
            cashInHandBefore: 0.0,
            shortfallAmount: 350.0,
            createdAt: '2026-11-17T12:00:00',
          ),
        ],
      );

      final pdfBytes = await SalesReportPdfService().generateEodReportPdf(report);
      final lines = PrinterService.getPdfThermalLines(pdfBytes)?.map((l) => l.text).toList() ?? [];

      expect(lines.any((l) => l.contains('NET CASH IN HAND') && l.contains('-350.00')), isTrue);
      expect(lines.any((l) => l.contains('CASH SHORTFALL (OWED TO SALESMAN)') && l.contains('350.00')), isTrue);
      expect(lines.any((l) => l.contains('TOTAL HANDOVER (CASH + CHEQUES)') && l.contains('800.00')), isTrue);
      expect(lines.any((l) => l.contains('HCPOD57112600001')), isTrue);
    });

    test('computePhysicalCashInHandForDate returns negative cash when cash refunds exceed cash received', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE ${LocalDatabaseHelper.tableSiInvoices} (
          invoiceId TEXT PRIMARY KEY,
          transactionType TEXT,
          createdAt TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE ${LocalDatabaseHelper.tableSiPayments} (
          paymentId INTEGER PRIMARY KEY AUTOINCREMENT,
          invoiceId TEXT,
          method TEXT,
          amount REAL,
          createdAt TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE ${LocalDatabaseHelper.tableSiOpenInvoicePayments} (
          paymentId TEXT PRIMARY KEY,
          paymentMethod TEXT,
          amount REAL,
          createdAt TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE ${LocalDatabaseHelper.tableSiCreditNotes} (
          creditNoteId TEXT PRIMARY KEY,
          createdAt TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE ${LocalDatabaseHelper.tableSiCreditNoteRefunds} (
          refundId INTEGER PRIMARY KEY AUTOINCREMENT,
          creditNoteId TEXT,
          method TEXT,
          amount REAL,
          createdAt TEXT
        )
      ''');

      await db.insert(LocalDatabaseHelper.tableSiInvoices, {
        'invoiceId': 'HIPOD57112600001',
        'transactionType': 'INVOICE',
        'createdAt': '2026-11-17T09:00:00',
      });
      await db.insert(LocalDatabaseHelper.tableSiPayments, {
        'invoiceId': 'HIPOD57112600001',
        'method': 'CASH',
        'amount': 200.0,
        'createdAt': '2026-11-17T09:00:00',
      });
      await db.insert(LocalDatabaseHelper.tableSiCreditNotes, {
        'creditNoteId': 'HCPOD57112600001',
        'createdAt': '2026-11-17T11:00:00',
      });
      await db.insert(LocalDatabaseHelper.tableSiCreditNoteRefunds, {
        'creditNoteId': 'HCPOD57112600001',
        'method': 'CASH',
        'amount': 500.0,
        'createdAt': '2026-11-17T11:00:00',
      });

      final cash = await LocalDatabaseHelper.computePhysicalCashInHandForDate(
        db,
        DateTime(2026, 11, 17),
      );
      expect(cash, -300.0);
      await db.close();
    });
  });
}
