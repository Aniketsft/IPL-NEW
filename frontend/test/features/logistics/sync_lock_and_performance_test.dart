import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:enterprise_auth_mobile/core/utils/barcode_scanner/hardware_scanner_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/sales_invoice_sync_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/usecases/synchronize_sales_invoice_use_case.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_sync_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_sync_event.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_sync_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/widgets/sales_invoice_sync_overlay.dart';

class _FakeSalesInvoiceSyncRepository implements SalesInvoiceSyncRepository {
  Completer<SyncBatchResult>? syncCompleter;
  void Function(String stepMessage)? capturedOnProgress;
  CustomerSyncResult? nextCustomerResult;

  @override
  Future<SyncBatchResult> synchronizeSalesInvoiceData(
    String siteCode, {
    bool uploadOnly = false,
    bool downloadOnly = false,
    void Function(String stepMessage)? onProgress,
  }) async {
    capturedOnProgress = onProgress;
    if (syncCompleter != null) {
      return syncCompleter!.future;
    }
    return SyncBatchResult(
      reports: const [
        SyncEntityReport(
          entityName: 'Facilities',
          direction: SyncDirection.download,
          status: SyncStatus.success,
          count: 1,
        ),
      ],
    );
  }

  @override
  Future<CustomerSyncResult> syncSingleCustomerData({
    required String customerCode,
    String? siteCode,
  }) async {
    return nextCustomerResult ??
        CustomerSyncResult(
          success: true,
          customerCode: customerCode,
          liveBalance: 125.50,
          openInvoicesCount: 2,
          x3HistoryInvoicesCount: 5,
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSynchronizeSalesInvoiceUseCase implements SynchronizeSalesInvoiceUseCase {
  final _FakeSalesInvoiceSyncRepository _repo;

  _FakeSynchronizeSalesInvoiceUseCase(this._repo);

  @override
  Future<SyncBatchResult> execute({
    required String siteCode,
    bool uploadOnly = false,
    bool downloadOnly = false,
    void Function(String stepMessage)? onProgress,
  }) {
    return _repo.synchronizeSalesInvoiceData(
      siteCode,
      uploadOnly: uploadOnly,
      downloadOnly: downloadOnly,
      onProgress: onProgress,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();

  group('LocalDatabaseHelper batched open invoices sync', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE ${LocalDatabaseHelper.tableSiOpenInvoices} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          documentNo TEXT NOT NULL,
          customerNo TEXT NOT NULL,
          customerName TEXT,
          dueDate TEXT NOT NULL,
          site TEXT NOT NULL,
          company TEXT NOT NULL,
          docType TEXT NOT NULL,
          remainingAmtLCY REAL NOT NULL,
          allocatedAmount REAL DEFAULT 0.0,
          isPaid INTEGER DEFAULT 0,
          lastSyncAt TEXT,
          UNIQUE(documentNo, dueDate)
        )
      ''');
      await db.execute('''
        CREATE TABLE ${LocalDatabaseHelper.tableSiOpenInvoicePayments} (
          paymentId TEXT PRIMARY KEY,
          documentNo TEXT NOT NULL,
          customerNo TEXT NOT NULL,
          amount REAL NOT NULL,
          paymentMethod TEXT NOT NULL,
          bankCode TEXT,
          bankName TEXT,
          chequeNumber TEXT,
          chequeDate TEXT,
          qrTransactionRef TEXT,
          siteCode TEXT,
          company TEXT,
          createdAt TEXT,
          userName TEXT,
          deviceId TEXT,
          isSynced INTEGER DEFAULT 0,
          syncedAt TEXT
        )
      ''');
      LocalDatabaseHelper.setTestDatabase(db);
    });

    tearDown(() async {
      LocalDatabaseHelper.setTestDatabase(null);
      await db.close();
    });

    test('refreshOpenInvoices commits >500 rows in chunks, rounds cleanly, deducts unsynced payments, and excludes CN', () async {
      await db.insert(LocalDatabaseHelper.tableSiOpenInvoicePayments, {
        'paymentId': 'PAY-1',
        'documentNo': 'INV-0001',
        'customerNo': 'CUST-1',
        'amount': 40.0,
        'paymentMethod': 'CASH',
        'isSynced': 0,
      });
      await db.insert(LocalDatabaseHelper.tableSiOpenInvoicePayments, {
        'paymentId': 'PAY-2',
        'documentNo': 'INV-0002',
        'customerNo': 'CUST-1',
        'amount': 50.0,
        'paymentMethod': 'CASH',
        'isSynced': 0,
      });

      final payload = <Map<String, dynamic>>[
        {
          'documentNo': 'INV-0001',
          'customerNo': 'CUST-1',
          'customerName': 'Customer One',
          'dueDate': '2026-11-30',
          'site': 'HIPOD57',
          'company': 'INL',
          'docType': 'INV',
          'remainingAmtLCY': 100.335,
        },
        {
          'documentNo': 'INV-0002',
          'customerNo': 'CUST-1',
          'customerName': 'Customer One',
          'dueDate': '2026-11-30',
          'site': 'HIPOD57',
          'company': 'INL',
          'docType': 'INV',
          'remainingAmtLCY': 50.0,
        },
        {
          'documentNo': 'CN-0001',
          'customerNo': 'CUST-1',
          'customerName': 'Customer One',
          'dueDate': '2026-11-30',
          'site': 'HIPOD57',
          'company': 'INL',
          'docType': 'CN',
          'remainingAmtLCY': 25.0,
        },
      ];

      // Add 617 more valid open invoices to cross the 500-row batch chunk boundary
      for (int i = 3; i <= 619; i++) {
        payload.add({
          'documentNo': 'INV-${i.toString().padLeft(4, '0')}',
          'customerNo': 'CUST-2',
          'customerName': 'Customer Two',
          'dueDate': '2026-12-01',
          'site': 'HIPOD57',
          'company': 'INL',
          'docType': 'INV',
          'remainingAmtLCY': 10.0,
        });
      }

      await LocalDatabaseHelper.instance.refreshOpenInvoices(payload);

      final allRows = await db.query(LocalDatabaseHelper.tableSiOpenInvoices);
      // 620 total input - 1 excluded CN = 619 stored rows
      expect(allRows.length, 619);

      final inv1 = allRows.firstWhere((r) => r['documentNo'] == 'INV-0001');
      expect(inv1['remainingAmtLCY'], 60.34);
      expect(inv1['allocatedAmount'], 40.0);
      expect(inv1['isPaid'], 0);

      final inv2 = allRows.firstWhere((r) => r['documentNo'] == 'INV-0002');
      expect(inv2['remainingAmtLCY'], 0.0);
      expect(inv2['isPaid'], 1);

      expect(allRows.any((r) => r['documentNo'] == 'CN-0001'), isFalse);
    });

    test('refreshOpenInvoicesForCustomer replaces only target customer invoices and preserves others', () async {
      await db.insert(LocalDatabaseHelper.tableSiOpenInvoices, {
        'documentNo': 'OLD-CUST1',
        'customerNo': 'CUST-1',
        'customerName': 'Customer One',
        'dueDate': '2026-11-01',
        'site': 'HIPOD57',
        'company': 'INL',
        'docType': 'INV',
        'remainingAmtLCY': 99.0,
        'isPaid': 0,
      });
      await db.insert(LocalDatabaseHelper.tableSiOpenInvoices, {
        'documentNo': 'KEEP-CUST2',
        'customerNo': 'CUST-2',
        'customerName': 'Customer Two',
        'dueDate': '2026-11-01',
        'site': 'HIPOD57',
        'company': 'INL',
        'docType': 'INV',
        'remainingAmtLCY': 88.0,
        'isPaid': 0,
      });

      final activeCount = await LocalDatabaseHelper.instance.refreshOpenInvoicesForCustomer('CUST-1', [
        {
          'documentNo': 'NEW-CUST1',
          'customerNo': 'CUST-1',
          'customerName': 'Customer One',
          'dueDate': '2026-12-01',
          'site': 'HIPOD57',
          'company': 'INL',
          'docType': 'INV',
          'remainingAmtLCY': 45.25,
        },
      ]);

      expect(activeCount, 1);
      final rows = await db.query(LocalDatabaseHelper.tableSiOpenInvoices);
      expect(rows.any((r) => r['documentNo'] == 'OLD-CUST1'), isFalse);
      expect(rows.any((r) => r['documentNo'] == 'NEW-CUST1'), isTrue);
      expect(rows.any((r) => r['documentNo'] == 'KEEP-CUST2'), isTrue);
    });
  });

  group('Sync Lock & SalesInvoiceSyncOverlay', () {
    test('HardwareScannerService exposes lock toggle cleanly', () {
      final scanner = HardwareScannerService();
      scanner.isLocked = false;
      expect(scanner.isLocked, isFalse);

      scanner.isLocked = true;
      expect(scanner.isLocked, isTrue);

      scanner.isLocked = false;
      expect(scanner.isLocked, isFalse);
    });

    testWidgets('Overlay displays ModalBarrier(dismissible: false), PopScope(canPop: false), and step progress during sync', (tester) async {
      final fakeRepo = _FakeSalesInvoiceSyncRepository();
      final completer = Completer<SyncBatchResult>();
      fakeRepo.syncCompleter = completer;

      final bloc = SalesInvoiceSyncBloc(
        synchronizeSalesInvoiceUseCase: _FakeSynchronizeSalesInvoiceUseCase(fakeRepo),
        repository: fakeRepo,
      );

      int backgroundTapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SalesInvoiceSyncBloc>.value(
            value: bloc,
            child: Stack(
              children: [
                Scaffold(
                  body: Center(
                    child: BlocBuilder<SalesInvoiceSyncBloc, SalesInvoiceSyncState>(
                      builder: (context, syncState) {
                        final locked = syncState is SalesInvoiceSyncInProgress ||
                            syncState is SalesInvoiceCustomerSyncInProgress;
                        return AbsorbPointer(
                          absorbing: locked,
                          child: ElevatedButton(
                            onPressed: () => backgroundTapCount++,
                            child: const Text('Tap Me'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SalesInvoiceSyncOverlay(),
              ],
            ),
          ),
        ),
      );

      // Initially unlocked and overlay hidden
      expect(
        find.descendant(
          of: find.byType(SalesInvoiceSyncOverlay),
          matching: find.byType(ModalBarrier),
        ),
        findsNothing,
      );

      await tester.tap(find.text('Tap Me'));
      expect(backgroundTapCount, 1);

      // Start sync -> locks UI immediately
      bloc.add(const StartSalesInvoiceSyncRequested(siteCode: 'HIPOD57'));
      await tester.pump();

      final barrierFinder = find.descendant(
        of: find.byType(SalesInvoiceSyncOverlay),
        matching: find.byType(ModalBarrier),
      );
      expect(barrierFinder, findsOneWidget);
      final barrier = tester.widget<ModalBarrier>(barrierFinder);
      expect(barrier.dismissible, isFalse);

      final popScopeFinder = find.descendant(
        of: find.byType(SalesInvoiceSyncOverlay),
        matching: find.byType(PopScope),
      );
      expect(popScopeFinder, findsOneWidget);
      final popScope = tester.widget<PopScope>(popScopeFinder);
      expect(popScope.canPop, isFalse);

      // Step progress callback updates UI message while locked
      fakeRepo.capturedOnProgress?.call('Step 3/7: Syncing customers...');
      await tester.pump();
      expect(find.text('Step 3/7: Syncing customers...'), findsOneWidget);

      // Background button taps are blocked while sync is running
      await tester.tap(find.text('Tap Me'), warnIfMissed: false);
      expect(backgroundTapCount, 1);

      // Complete sync cleanly -> transitions to success, then auto-dismisses after 3.2s
      completer.complete(
        SyncBatchResult(
          reports: const [
            SyncEntityReport(
              entityName: 'Customers',
              direction: SyncDirection.download,
              status: SyncStatus.success,
              count: 10,
            ),
          ],
        ),
      );
      await tester.pump();
      expect(find.text('Sync Complete'), findsOneWidget);

      // Wait out the 3.2s auto-dismiss timer so no pending timers remain
      await tester.pump(const Duration(milliseconds: 3300));
      await tester.pump();

      expect(barrierFinder, findsNothing);

      // Background interaction works again once dismissed
      await tester.tap(find.text('Tap Me'));
      expect(backgroundTapCount, 2);

      await bloc.close();
    });
  });
}
