import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:enterprise_auth_mobile/core/network_service.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:enterprise_auth_mobile/features/auth/presentation/bloc/auth_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/sales_invoice_product_model.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/sales_report_pdf_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/pages/sales_invoice/sales_reports_screen.dart';

class _FakeAuthBloc extends Fake implements AuthBloc {
  final AuthState _state;
  _FakeAuthBloc(this._state);

  @override
  AuthState get state => _state;

  @override
  Stream<AuthState> get stream => const Stream<AuthState>.empty();

  @override
  Future<void> close() async {}
}

class _FakeNetworkService extends Fake implements NetworkService {}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Dynamic Discount Limit (SQLite GlobalSettings)', () {
    late Database db;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE ${LocalDatabaseHelper.tableGlobalSettings} (
          ${LocalDatabaseHelper.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
          ${LocalDatabaseHelper.colSettingKey} TEXT,
          ${LocalDatabaseHelper.colSettingValue} TEXT,
          ${LocalDatabaseHelper.colSettingIsSynced} INTEGER NOT NULL DEFAULT 0,
          ${LocalDatabaseHelper.colSettingLastUpdated} TEXT,
          ${LocalDatabaseHelper.colSettingUpdatedBy} TEXT,
          ${LocalDatabaseHelper.colSettingAction} TEXT
        )
      ''');
      LocalDatabaseHelper.setTestDatabase(db);
    });

    tearDown(() async {
      LocalDatabaseHelper.setTestDatabase(null);
      await db.close();
    });

    test('defaults to 5.0 when MaxDiscountPercent is absent', () async {
      final limit = await LocalDatabaseHelper.instance.getMaxDiscountPercent();
      expect(limit, 5.0);
    });

    test('loads synced MaxDiscountPercent from GlobalSettings map', () async {
      await LocalDatabaseHelper.instance.saveGlobalSettingsMap({
        'MaxDiscountPercent': '12.5',
      });
      final limit = await LocalDatabaseHelper.instance.getMaxDiscountPercent();
      expect(limit, 12.5);
    });

    test('preserves pending offline supervisor edit during sync download', () async {
      await LocalDatabaseHelper.instance.updateGlobalSetting(
        'MaxDiscountPercent',
        '15',
        isSynced: false,
        updatedBy: 'supervisor1',
      );
      await LocalDatabaseHelper.instance.saveGlobalSettingsMap({
        'MaxDiscountPercent': '5.0',
      });

      final limit = await LocalDatabaseHelper.instance.getMaxDiscountPercent();
      expect(limit, 15.0);
    });

    test('clamps invalid values into 0..100', () async {
      await LocalDatabaseHelper.instance.updateGlobalSetting(
        'MaxDiscountPercent',
        '150',
        isSynced: true,
      );
      expect(await LocalDatabaseHelper.instance.getMaxDiscountPercent(), 100.0);
    });
  });

  group('SalesReportsScreen Previous Date Permission', () {
    Widget buildScreen(List<String> permissions) {
      final authBloc = _FakeAuthBloc(Authenticated(
        username: 'tester',
        permissions: permissions,
        siteCode: 'POD',
      ));
      return MultiRepositoryProvider(
        providers: [
          RepositoryProvider<NetworkService>(create: (_) => _FakeNetworkService()),
        ],
        child: BlocProvider<AuthBloc>.value(
          value: authBloc,
          child: MaterialApp(
            home: SalesReportsScreen(permissions: permissions),
          ),
        ),
      );
    }

    testWidgets('locks report date to today without previous_date permission', (tester) async {
      await tester.pumpWidget(buildScreen(['logistics.reports.read']));
      await tester.pumpAndSettle();

      final todayLabel = DateFormat('EEE, dd MMM yyyy').format(DateTime.now());
      expect(find.text(todayLabel), findsOneWidget);
      expect(find.text('Default: Current date only'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);

      await tester.tap(find.text(todayLabel));
      await tester.pumpAndSettle();
      // DatePicker should not open
      expect(find.byType(DatePickerDialog), findsNothing);
    });

    testWidgets('allows opening date picker with previous_date permission', (tester) async {
      await tester.pumpWidget(buildScreen([
        'logistics.reports.read',
        'logistics.reports.previous_date.read',
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Tap to select a previous date'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);

      final todayLabel = DateFormat('EEE, dd MMM yyyy').format(DateTime.now());
      await tester.tap(find.text(todayLabel));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget);
    });
  });

  group('SalesReportPdfService Stock Preview Date', () {
    test('generates Stock Preview PDF cleanly with reportDate metadata', () async {
      final service = SalesReportPdfService();
      final bytes = await service.generateStockPreviewPdf(
        items: [
          SalesInvoiceProductModel(
            sku: 'SKU1',
            name: 'Chicken Breast',
            stockQty: 10,
            warehouse: '57',
            salesUnit: 'KG',
            stockStatus: 'A',
          ),
        ],
        warehouseLabel: '57',
        reportDate: '10 Nov 2026',
        isHistoricalDate: true,
      );
      expect(bytes, isNotEmpty);
    });
  });
}
