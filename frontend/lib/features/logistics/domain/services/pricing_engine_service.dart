import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/pricing_result.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';

class PricingEngineService {
  final LocalDatabaseHelper _dbHelper = LocalDatabaseHelper.instance;

  Future<PricingResult> resolvePrice({
    required String customerCode,
    required String bcgcod,
    required String tsccod,
    required String sku,
    required double qty,
  }) async {
    final db = await _dbHelper.database;

    // 1. Check if we have active price lists for this matching context.
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    print('--- RESOLVING PRICE FOR SKU: $sku, CUSTOMER: $customerCode, BCGCOD: $bcgcod, TSCCOD: $tsccod ---');
    
    // Optimized SQL: push all criteria down to SQLite so we don't load 50k rows into Dart memory!
    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT * FROM ${LocalDatabaseHelper.tablePriceLists}
      WHERE 
        (
          (fld0 = 'BCGCOD' AND fld1 = 'ITMREF' AND matchKey1 = ? AND matchKey2 = ?)
          OR (fld0 = 'TSCCOD' AND fld1 = 'ITMREF' AND matchKey1 = ? AND matchKey2 = ?)
          OR (fld0 = 'BPCNUM' AND fld1 = 'ITMREF' AND matchKey1 = ? AND matchKey2 = ?)
          OR (fld0 = 'ITMREF' AND (fld1 IS NULL OR fld1 = '') AND matchKey1 = ?)
          OR (fld0 = 'BPCNUM' AND (fld1 IS NULL OR fld1 = '') AND matchKey1 = ?)
          OR (fld0 = 'BCGCOD' AND (fld1 IS NULL OR fld1 = '') AND matchKey1 = ?)
          OR (fld0 = 'TSCCOD' AND (fld1 IS NULL OR fld1 = '') AND matchKey1 = ?)
        )
      ORDER BY priority ASC
    ''', [
      bcgcod, sku,
      tsccod, sku,
      customerCode, sku,
      sku,
      customerCode,
      bcgcod,
      tsccod
    ]);

    if (results.isEmpty) {
      print('Pricing Engine: No matching price lists found for current date $todayStr.');
      return PricingResult.empty();
    }

    print('Pricing Engine: Found ${results.length} active price lists for this context.');

    PricingResult? bestPriceResult;
    PricingResult? bestDiscountResult;

    for (var row in results) {
      // Since SQLite already perfectly filtered the rows, we don't need Dart criteria matching anymore.
      final String? matchKey1 = row['matchKey1']?.toString();
      final String? fld0 = row['fld0']?.toString();
      
      print('MATCHED RULE: fld0=$fld0, matchKey1=$matchKey1, basePrice=${row['basePrice']}');

      final int isQtyBased = row['isQtyBased'] as int? ?? 1;
      final double minQty = (row['minQty'] as num?)?.toDouble() ?? 0.0;
      final double maxQty = (row['maxQty'] as num?)?.toDouble() ?? 999999.0;

      if (isQtyBased == 2) {
        if (qty < minQty || qty > maxQty) continue;
      }

      final int ruleType = row['ruleType'] as int? ?? 0;
      final double basePrice = (row['basePrice'] as num?)?.toDouble() ?? 0.0;
      final double discountPct = (row['discountPct'] as num?)?.toDouble() ?? 0.0;
      final double discountAmt = (row['discountAmt'] as num?)?.toDouble() ?? 0.0;
      final int focType = row['focType'] as int? ?? 1;
      final String source = row['pliCode']?.toString() ?? 'UNKNOWN';

      bool hasFoc = false;
      String focSku = '';
      double focQty = 0.0;

      if (focType == 2 || focType == 3) {
        final double focQtyMin = (row['focQtyMin'] as num?)?.toDouble() ?? 0.0;
        final double focQtyBkt = (row['focQtyBkt'] as num?)?.toDouble() ?? 1.0;
        final double ruleFocQty = (row['focQty'] as num?)?.toDouble() ?? 0.0;
        final String ruleFocSku = row['focItmRef']?.toString() ?? '';

        if (qty >= focQtyMin && focQtyBkt > 0) {
          int buckets = (qty / focQtyBkt).floor();
          focQty = buckets * ruleFocQty;
          hasFoc = focQty > 0;
          focSku = ruleFocSku.isEmpty ? sku : ruleFocSku; // If same, it might be empty or same sku
        }
      }

      if (ruleType == 1) {
        // Discount rule. Best single discount.
        // We evaluate by percentage or amount to find the "best". We'll just store the first one
        // or compare if we have multiple. Let's find the max discount percentage for simplicity.
        if (bestDiscountResult == null || discountPct > bestDiscountResult.discountPct || discountAmt > bestDiscountResult.discountAmt) {
          bestDiscountResult = PricingResult(
            basePrice: basePrice, // Usually discount rules have 0 base price
            discountPct: discountPct,
            discountAmt: discountAmt,
            source: source,
            hasFoc: hasFoc,
            focItemSku: focSku,
            focQuantity: focQty,
          );
        }
      } else if (ruleType == 2) {
        // Price rule. Lowest price wins on tie. Since we order by priority ASC,
        // the first one we hit is highest priority for base price.
        if (bestPriceResult == null) {
           bestPriceResult = PricingResult(
             basePrice: basePrice,
             discountPct: discountPct,
             discountAmt: discountAmt,
             source: source,
             hasFoc: hasFoc,
             focItemSku: focSku,
             focQuantity: focQty,
           );
        } else if (hasFoc && !bestPriceResult.hasFoc) {
           // We already have a base price, but a lower priority rule is granting FOC!
           // Merge the FOC into our primary result.
           bestPriceResult = PricingResult(
             basePrice: bestPriceResult.basePrice,
             discountPct: bestPriceResult.discountPct,
             discountAmt: bestPriceResult.discountAmt,
             source: "${bestPriceResult.source} + $source",
             hasFoc: true,
             focItemSku: focSku,
             focQuantity: focQty,
           );
        }
      }
    }

    // Combine best price and best discount.
    // X3 usually applies the discount over the found base price.
    double finalBasePrice = bestPriceResult?.basePrice ?? 0.0;
    double finalDiscPct = bestDiscountResult?.discountPct ?? bestPriceResult?.discountPct ?? 0.0;
    double finalDiscAmt = bestDiscountResult?.discountAmt ?? bestPriceResult?.discountAmt ?? 0.0;
    String finalSource = [
      if (bestPriceResult != null) bestPriceResult.source,
      if (bestDiscountResult != null) bestDiscountResult.source
    ].toSet().join(' & ');

    if (finalSource.isEmpty) {
      finalSource = 'MANUAL';
    }

    bool finalHasFoc = (bestPriceResult?.hasFoc ?? false) || (bestDiscountResult?.hasFoc ?? false);
    String finalFocSku = (bestPriceResult?.hasFoc ?? false) ? bestPriceResult!.focItemSku : (bestDiscountResult?.focItemSku ?? '');
    double finalFocQty = (bestPriceResult?.hasFoc ?? false) ? bestPriceResult!.focQuantity : (bestDiscountResult?.focQuantity ?? 0.0);

    print('FINAL RESOLVED: BasePrice=$finalBasePrice, Disc=$finalDiscPct');
    return PricingResult(
      basePrice: finalBasePrice,
      discountPct: finalDiscPct,
      discountAmt: finalDiscAmt,
      source: finalSource,
      hasFoc: finalHasFoc,
      focItemSku: finalFocSku,
      focQuantity: finalFocQty,
    );
  }
}
