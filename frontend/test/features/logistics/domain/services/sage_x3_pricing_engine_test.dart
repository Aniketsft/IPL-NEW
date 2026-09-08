import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/services/pricing_engine_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late PricingEngineService service;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
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
        focItmRef TEXT,
        focQty REAL,
        minQty REAL,
        maxQty REAL,
        validFrom TEXT,
        validTo TEXT,
        reasonType INTEGER DEFAULT 0,
        focAmtMin REAL DEFAULT 0,
        focAmtBkt REAL DEFAULT 0
      )
    ''');
    service = PricingEngineService();
  });

  tearDown(() async {
    await db.close();
  });

  group('Sage X3 INL Pricing Engine Canonical Test Suite', () {
    test('Scenario 1: Inter-site Transfer (T40 Override) when facilityFlag == 2 or bcgcod == INTER', () async {
      // Setup T40 rule matching Sage X3 facility structure: FLD0=FCY/BPCNUM, FLD1=ITMREF
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T40',
        'priority': 50,
        'ruleType': 2,
        'fld0': 'FCY',
        'fld1': 'ITMREF',
        'matchKey1': 'POD',
        'matchKey2': '3802',
        'basePrice': 309.0,
        'discountPct': 0.0,
        'discountAmt': 0.0,
        'focType': 1,
      });

      // Commercial rule that would otherwise match standard customer
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T100',
        'priority': 10,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'matchKey1': '3802',
        'basePrice': 381.0,
        'discountPct': 0.0,
        'discountAmt': 0.0,
        'focType': 1,
      });

      // Facility customer POD001 (facilityFlag == 2) -> Bypasses commercial T100 and applies T40 (309.00)
      final facilityResult = await service.resolvePrice(
        customerCode: 'POD001',
        bcgcod: 'INTER',
        tsccod: '',
        facilityFlag: 2,
        sku: '3802',
        qty: 1,
        database: db,
      );

      expect(facilityResult.basePrice, 309.0);
      expect(facilityResult.priceListCode, 'T40');

      // Facility customer without explicit flag but with BCGCOD == 'INTER'
      final facilityByBcgResult = await service.resolvePrice(
        customerCode: 'POD001',
        bcgcod: 'INTER',
        tsccod: '',
        facilityFlag: null,
        sku: '3802',
        qty: 1,
        database: db,
      );

      expect(facilityByBcgResult.basePrice, 309.0);
      expect(facilityByBcgResult.priceListCode, 'T40');

      // Standard customer (facilityFlag == 1, bcgcod == 'TRA') -> T40 is bypassed, applies standard T100 (381.00)
      final standardResult = await service.resolvePrice(
        customerCode: 'AFC373',
        bcgcod: 'TRA',
        tsccod: 'TRAD',
        facilityFlag: 1,
        sku: '3802',
        qty: 1,
        database: db,
      );

      expect(standardResult.basePrice, 381.0);
      expect(standardResult.priceListCode, 'T100');
    });

    test('Scenario 2: Customer Specific Pricing T150C (Product 8390, Customer 18025)', () async {
      // Global item price T100
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T100',
        'priority': 100,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'matchKey1': '8390',
        'basePrice': 180.0,
        'focType': 1,
      });

      // Customer specific contract price T150C for Customer 18025
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T150C',
        'priority': 20,
        'ruleType': 2,
        'fil0': 'BPCUSTOMER',
        'fld0': 'BPCNUM',
        'fil1': 'ITMMASTER',
        'fld1': 'ITMREF',
        'matchKey1': '18025',
        'matchKey2': '8390',
        'basePrice': 145.0,
        'discountPct': 0.0,
        'focType': 1,
      });

      final result = await service.resolvePrice(
        customerCode: '18025',
        bcgcod: 'MOD',
        tsccod: 'DREAM',
        sku: '8390',
        qty: 1,
        database: db,
      );

      expect(result.basePrice, 145.0);
      expect(result.priceListCode, 'T150C');
      expect(result.source, 'T150C');
    });

    test('Scenario 3: Customer Specific Pricing T150D (Product 8391, Customer 18025)', () async {
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T100',
        'priority': 100,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'matchKey1': '8391',
        'basePrice': 250.0,
        'focType': 1,
      });

      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T150D',
        'priority': 20,
        'ruleType': 2,
        'fil0': 'BPCUSTOMER',
        'fld0': 'BPCNUM',
        'fil1': 'ITMMASTER',
        'fld1': 'ITMREF',
        'matchKey1': '18025',
        'matchKey2': '8391',
        'basePrice': 210.0,
        'discountPct': 0.0,
        'focType': 1,
      });

      final result = await service.resolvePrice(
        customerCode: '18025',
        bcgcod: 'MOD',
        tsccod: 'DREAM',
        sku: '8391',
        qty: 1,
        database: db,
      );

      expect(result.basePrice, 210.0);
      expect(result.priceListCode, 'T150D');
    });

    test('Scenario 4: Customer Specific Contract Discount T140 + Global Base Price T100 (Product 31141, Customer 18025)', () async {
      // Base Price T100 (Priority 100)
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T100',
        'priority': 100,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'matchKey1': '31141',
        'basePrice': 95.0,
        'focType': 1,
      });

      // Discount T140 for Customer 18025 (Priority 30 <= Priority 100)
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T140',
        'priority': 30,
        'ruleType': 1,
        'fil0': 'BPCUSTOMER',
        'fld0': 'BPCNUM',
        'fil1': 'ITMMASTER',
        'fld1': 'ITMREF',
        'matchKey1': '18025',
        'matchKey2': '31141',
        'basePrice': 0.0,
        'discountPct': 12.5,
        'focType': 1,
      });

      final result = await service.resolvePrice(
        customerCode: '18025',
        bcgcod: 'MOD',
        tsccod: 'DREAM',
        sku: '31141',
        qty: 1,
        database: db,
      );

      expect(result.basePrice, 95.0);
      expect(result.discountPct, 12.5);
      expect(result.priceListCode, 'T100');
      expect(result.source, 'T100 & T140');
    });

    test('Scenario 5: Customer Category Pricing T115 (BCGCOD = MOD, Product 721201)', () async {
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T100',
        'priority': 100,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'matchKey1': '721201',
        'basePrice': 60.0,
        'focType': 1,
      });

      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T115',
        'priority': 80,
        'ruleType': 2,
        'fil0': 'BPCUSTOMER',
        'fld0': 'BCGCOD',
        'fil1': 'ITMMASTER',
        'fld1': 'ITMREF',
        'matchKey1': 'MOD',
        'matchKey2': '721201',
        'basePrice': 55.0,
        'focType': 1,
      });

      final result = await service.resolvePrice(
        customerCode: 'CUST_MOD',
        bcgcod: 'MOD',
        tsccod: 'STD',
        sku: '721201',
        qty: 1,
        database: db,
      );

      expect(result.basePrice, 55.0);
      expect(result.priceListCode, 'T115');
    });

    test('Scenario 6: Statistical Group Pricing T160 (TSCCOD = DREAM, Product 8390)', () async {
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T115',
        'priority': 80,
        'ruleType': 2,
        'fld0': 'BCGCOD',
        'fld1': 'ITMREF',
        'matchKey1': 'MOD',
        'matchKey2': '8390',
        'basePrice': 90.0,
        'focType': 1,
      });

      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T160',
        'priority': 60,
        'ruleType': 2,
        'fil0': 'BPCUSTOMER',
        'fld0': 'TSCCOD',
        'fil1': 'ITMMASTER',
        'fld1': 'ITMREF',
        'matchKey1': 'DREAM',
        'matchKey2': '8390',
        'basePrice': 85.0,
        'focType': 1,
      });

      final result = await service.resolvePrice(
        customerCode: 'CUST_DREAM',
        bcgcod: 'MOD',
        tsccod: 'DREAM',
        sku: '8390',
        qty: 1,
        database: db,
      );

      // Priority 60 beats Priority 80
      expect(result.basePrice, 85.0);
      expect(result.priceListCode, 'T160');
    });

    test('Scenario 7: Volume Quantity Breaks (PRIQTYFLG_0 = 2)', () async {
      // Tier 1: 1 - 9 -> 50.0
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'TIER1',
        'priority': 50,
        'ruleType': 2,
        'isQtyBased': 2,
        'minQty': 1.0,
        'maxQty': 9.0,
        'fld0': 'ITMREF',
        'matchKey1': 'ITEM-VOL',
        'basePrice': 50.0,
        'focType': 1,
      });

      // Tier 2: 10 - 49 -> 45.0
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'TIER2',
        'priority': 50,
        'ruleType': 2,
        'isQtyBased': 2,
        'minQty': 10.0,
        'maxQty': 49.0,
        'fld0': 'ITMREF',
        'matchKey1': 'ITEM-VOL',
        'basePrice': 45.0,
        'focType': 1,
      });

      // Tier 3: 50+ -> 40.0
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'TIER3',
        'priority': 50,
        'ruleType': 2,
        'isQtyBased': 2,
        'minQty': 50.0,
        'maxQty': 99999.0,
        'fld0': 'ITMREF',
        'matchKey1': 'ITEM-VOL',
        'basePrice': 40.0,
        'focType': 1,
      });

      final rTier1 = await service.resolvePrice(
        customerCode: 'CUST01',
        bcgcod: 'CAT1',
        tsccod: 'STAT1',
        sku: 'ITEM-VOL',
        qty: 5,
        database: db,
      );
      expect(rTier1.basePrice, 50.0);
      expect(rTier1.priceListCode, 'TIER1');

      final rTier2 = await service.resolvePrice(
        customerCode: 'CUST01',
        bcgcod: 'CAT1',
        tsccod: 'STAT1',
        sku: 'ITEM-VOL',
        qty: 15,
        database: db,
      );
      expect(rTier2.basePrice, 45.0);
      expect(rTier2.priceListCode, 'TIER2');

      final rTier3 = await service.resolvePrice(
        customerCode: 'CUST01',
        bcgcod: 'CAT1',
        tsccod: 'STAT1',
        sku: 'ITEM-VOL',
        qty: 60,
        database: db,
      );
      expect(rTier3.basePrice, 40.0);
      expect(rTier3.priceListCode, 'TIER3');
    });

    test('Scenario 8: Priority Tie-Breakers (Minimum Base Price Wins on Same Priority)', () async {
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'RULE_EXPENSIVE',
        'priority': 20,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'matchKey1': 'ITEM-TIE',
        'basePrice': 150.0,
        'focType': 1,
      });

      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'RULE_CHEAP',
        'priority': 20,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'matchKey1': 'ITEM-TIE',
        'basePrice': 120.0,
        'focType': 1,
      });

      final result = await service.resolvePrice(
        customerCode: 'CUST01',
        bcgcod: 'CAT1',
        tsccod: 'STAT1',
        sku: 'ITEM-TIE',
        qty: 1,
        database: db,
      );

      // Tie-breaker: 120.0 wins over 150.0
      expect(result.basePrice, 120.0);
      expect(result.priceListCode, 'RULE_CHEAP');
    });

    test('Scenario 9: Priority Tie-Breakers (Maximum Discount Wins on Same Priority)', () async {
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'BASE_100',
        'priority': 100,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'matchKey1': 'ITEM-DISC-TIE',
        'basePrice': 100.0,
        'focType': 1,
      });

      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'DISC_SMALL',
        'priority': 30,
        'ruleType': 1,
        'fld0': 'ITMREF',
        'matchKey1': 'ITEM-DISC-TIE',
        'basePrice': 0.0,
        'discountPct': 5.0,
        'focType': 1,
      });

      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'DISC_LARGE',
        'priority': 30,
        'ruleType': 1,
        'fld0': 'ITMREF',
        'matchKey1': 'ITEM-DISC-TIE',
        'basePrice': 0.0,
        'discountPct': 15.0,
        'focType': 1,
      });

      final result = await service.resolvePrice(
        customerCode: 'CUST01',
        bcgcod: 'CAT1',
        tsccod: 'STAT1',
        sku: 'ITEM-DISC-TIE',
        qty: 1,
        database: db,
      );

      expect(result.basePrice, 100.0);
      expect(result.discountPct, 15.0);
    });

    test('Scenario 10: Discount Protection (Discount Priority must be <= Base Price Priority)', () async {
      // Contract Base Price: Priority 20
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'CONTRACT_PRICE',
        'priority': 20,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'matchKey1': 'ITEM-PROT',
        'basePrice': 80.0,
        'focType': 1,
      });

      // Low Priority Discount: Priority 40 (> 20) -> Must be rejected
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'WEAK_DISC',
        'priority': 40,
        'ruleType': 1,
        'fld0': 'ITMREF',
        'matchKey1': 'ITEM-PROT',
        'basePrice': 0.0,
        'discountPct': 25.0,
        'focType': 1,
      });

      final protectedResult = await service.resolvePrice(
        customerCode: 'CUST01',
        bcgcod: 'CAT1',
        tsccod: 'STAT1',
        sku: 'ITEM-PROT',
        qty: 1,
        database: db,
      );

      // Weak discount rejected
      expect(protectedResult.basePrice, 80.0);
      expect(protectedResult.discountPct, 0.0);

      // High Priority Discount: Priority 10 (<= 20) -> Must be accepted
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'STRONG_DISC',
        'priority': 10,
        'ruleType': 1,
        'fld0': 'ITMREF',
        'matchKey1': 'ITEM-PROT',
        'basePrice': 0.0,
        'discountPct': 10.0,
        'focType': 1,
      });

      final validDiscResult = await service.resolvePrice(
        customerCode: 'CUST01',
        bcgcod: 'CAT1',
        tsccod: 'STAT1',
        sku: 'ITEM-PROT',
        qty: 1,
        database: db,
      );

      expect(validDiscResult.basePrice, 80.0);
      expect(validDiscResult.discountPct, 10.0);
    });

    test('Scenario 11: Free of Charge (Same Item - FOCPRO = 2)', () async {
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T100',
        'priority': 50,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'matchKey1': 'ITEM-FOC1',
        'basePrice': 20.0,
        'focType': 2,
        'focQtyMin': 10.0,
        'focQtyBkt': 10.0,
        'focQty': 1.0,
      });

      final result = await service.resolvePrice(
        customerCode: 'CUST01',
        bcgcod: 'CAT1',
        tsccod: 'STAT1',
        sku: 'ITEM-FOC1',
        qty: 25,
        database: db,
      );

      // floor(25 / 10) = 2 buckets * 1 = 2 free items
      expect(result.hasFoc, true);
      expect(result.focQuantity, 2.0);
      expect(result.focItemSku, 'ITEM-FOC1');
    });

    test('Scenario 12: Free of Charge (Cross Item - FOCPRO = 3)', () async {
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T100',
        'priority': 50,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'matchKey1': 'ITEM-FOC2',
        'basePrice': 30.0,
        'focType': 3,
        'focQtyMin': 12.0,
        'focQtyBkt': 12.0,
        'focQty': 2.0,
        'focItmRef': 'ITEM-GIFT',
      });

      final result = await service.resolvePrice(
        customerCode: 'CUST01',
        bcgcod: 'CAT1',
        tsccod: 'STAT1',
        sku: 'ITEM-FOC2',
        qty: 24,
        database: db,
      );

      // floor(24 / 12) = 2 buckets * 2 = 4 free GIFT items
      expect(result.hasFoc, true);
      expect(result.focQuantity, 4.0);
      expect(result.focItemSku, 'ITEM-GIFT');
    });

    test(
        'Scenario 13: Date Validity Gate - Expired rule (past validTo) is skipped, active default wins',
        () async {
      // Expired rule: validTo in past -> must be skipped
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'EXPIRED_RULE',
        'priority': 10,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'matchKey1': 'ITEM-DATE',
        'basePrice': 50.0,
        'validFrom': '2020-01-01',
        'validTo': '2020-12-31', // expired
        'focType': 1,
      });

      // Active rule with open-ended default sentinel dates (1753-01-01)
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'ACTIVE_DEFAULT',
        'priority': 50,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'matchKey1': 'ITEM-DATE',
        'basePrice': 100.0,
        'validFrom': '1753-01-01',
        'validTo': '1753-01-01',
        'focType': 1,
      });

      // Future rule — validFrom in future -> must be skipped
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'FUTURE',
        'priority': 5,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'matchKey1': 'ITEM-DATE',
        'basePrice': 40.0,
        'validFrom': '2030-01-01',
        'validTo': '2035-12-31',
        'focType': 1,
      });

      final result = await service.resolvePrice(
        customerCode: 'CUST01',
        bcgcod: 'CAT1',
        tsccod: 'STAT1',
        sku: 'ITEM-DATE',
        qty: 1,
        database: db,
      );

      // EXPIRED_RULE (priority 10) skipped because validTo '2020-12-31' is expired.
      // FUTURE (priority 5) skipped because validFrom '2030-01-01' is in future.
      // ACTIVE_DEFAULT (priority 50) is the only valid active rule -> wins.
      expect(result.basePrice, 100.0);
      expect(result.priceListCode, 'ACTIVE_DEFAULT');
    });

    test(
        'Scenario 14: Product 8390 Regression - Expired historical tiers (220.99 & 221.32) are skipped; Current active tier (253.65) wins',
        () async {
      // Replicates the exact INLPROD T100 data for SKU 8390 on 2026-09-08:
      // Tier 1: 2025-10-01 to 2026-02-20 @ Rs 220.99 (Expired)
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T100',
        'priority': 99,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'fld1': '',
        'matchKey1': '8390',
        'matchKey2': '',
        'basePrice': 220.99,
        'validFrom': '2025-10-01',
        'validTo': '2026-02-20', // EXPIRED
        'focType': 1,
      });

      // Tier 2: 2026-02-21 to 2026-07-23 @ Rs 221.32 (Expired)
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T100',
        'priority': 99,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'fld1': '',
        'matchKey1': '8390',
        'matchKey2': '',
        'basePrice': 221.32,
        'validFrom': '2026-02-21',
        'validTo': '2026-07-23', // EXPIRED
        'focType': 1,
      });

      // Tier 3: 2026-07-24 to 2026-12-31 @ Rs 253.65 (Current Active on 2026-09-08)
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T100',
        'priority': 99,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'fld1': '',
        'matchKey1': '8390',
        'matchKey2': '',
        'basePrice': 253.65,
        'validFrom': '2026-07-24',
        'validTo': '2026-12-31', // ACTIVE
        'focType': 1,
      });

      final result = await service.resolvePrice(
        customerCode: '18025',
        bcgcod: 'TRA',
        tsccod: 'NORM',
        sku: '8390',
        qty: 1,
        database: db,
      );

      // Must select the currently active tier (253.65) matching Sage X3.
      // Must NOT select expired tiers (220.99 or 221.32).
      expect(result.basePrice, 253.65);
      expect(result.priceListCode, 'T100');
    });

    test(
        'Scenario 15: Future validFrom rule is still correctly skipped (T130 future vs T100 active)',
        () async {
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T130',
        'priority': 70,
        'ruleType': 2,
        'fld0': 'BCGCOD',
        'fld1': 'ITMREF',
        'matchKey1': 'RNC',
        'matchKey2': '8391',
        'basePrice': 115.60,
        'validFrom': '2099-01-01', // future start date -> must be skipped
        'validTo': '',
        'focType': 1,
      });

      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T100',
        'priority': 99,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'fld1': '',
        'matchKey1': '8391',
        'matchKey2': '',
        'basePrice': 128.26,
        'validFrom': '2024-01-01',
        'validTo': '2030-12-31',
        'focType': 1,
      });

      final result = await service.resolvePrice(
        customerCode: 'XIA697',
        bcgcod: 'RNC',
        tsccod: 'NORM',
        sku: '8391',
        qty: 1,
        database: db,
      );

      expect(result.basePrice, 128.26);
      expect(result.priceListCode, 'T100');
    });

    test(
        'Scenario 16: Customer Group BPCSHO Pricing T130 (Customer XIA697, BPCSHO = HORECA, Product 8390)',
        () async {
      // Replicates exact Sage X3 scenario for customer XIA697:
      // BPCNUM: XIA697
      // BPCSHO: HORECA
      // BCGCOD: RNC
      // TSCCOD: NORM
      // Product: 8390

      // T130 (Group-Customer conditions): BPCSHO = HORECA, ITMREF = 8390, Priority = 50, Price = 220.99
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T130',
        'priority': 50,
        'ruleType': 2,
        'fld0': 'BPCSHO',
        'fld1': 'ITMREF',
        'matchKey1': 'HORECA',
        'matchKey2': '8390',
        'basePrice': 220.99,
        'validFrom': '2025-07-01',
        'validTo': '2026-09-30',
        'focType': 1,
      });

      // T100 (Global Item Base Price): ITMREF = 8390, Priority = 99, Price = 253.65
      await db.insert(LocalDatabaseHelper.tablePriceLists, {
        'pliCode': 'T100',
        'priority': 99,
        'ruleType': 2,
        'fld0': 'ITMREF',
        'fld1': '',
        'matchKey1': '8390',
        'matchKey2': '',
        'basePrice': 253.65,
        'validFrom': '2026-07-24',
        'validTo': '2026-12-31',
        'focType': 1,
      });

      // Case A: Customer has BPCSHO = 'HORECA' -> T130 (priority 50) wins over T100 (priority 99)
      final resultWithBpcsho = await service.resolvePrice(
        customerCode: 'XIA697',
        bpcsho: 'HORECA',
        bcgcod: 'RNC',
        tsccod: 'NORM',
        sku: '8390',
        qty: 1,
        database: db,
      );

      expect(resultWithBpcsho.basePrice, 220.99);
      expect(resultWithBpcsho.priceListCode, 'T130');

      // Case B: Standard Customer without BPCSHO -> falls back to T100 (253.65)
      final resultWithoutBpcsho = await service.resolvePrice(
        customerCode: 'CUST_OTHER',
        bpcsho: '',
        bcgcod: 'RNC',
        tsccod: 'NORM',
        sku: '8390',
        qty: 1,
        database: db,
      );

      expect(resultWithoutBpcsho.basePrice, 253.65);
      expect(resultWithoutBpcsho.priceListCode, 'T100');
    });
  });
}
