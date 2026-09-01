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
    int? facilityFlag,
    required String sku,
    required double qty,
  }) async {
    final db = await _dbHelper.database;

    // 1. Check if we have active price lists for this matching context.
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    print('--- RESOLVING PRICE FOR SKU: $sku, CUSTOMER: $customerCode, BCGCOD: $bcgcod, TSCCOD: $tsccod, FACILITY: $facilityFlag ---');
    
    List<Map<String, dynamic>> results;

    // Facility Override: If facilityFlag == 2, bypass standard logic and use T40 only
    if (facilityFlag == 2) {
      print('Pricing Engine: Facility override detected (BETFCY_0 = 2). Enforcing T40 price list.');
      results = await db.rawQuery('''
        SELECT * FROM ${LocalDatabaseHelper.tablePriceLists}
        WHERE pliCode = 'T40'
          AND (
            (fld0 = 'ITMREF' AND (fld1 IS NULL OR fld1 = '') AND matchKey1 = ?)
            OR (fld0 = 'BPCNUM' AND (fld1 IS NULL OR fld1 = '') AND matchKey1 = ?)
            OR (fld0 = 'BCGCOD' AND (fld1 IS NULL OR fld1 = '') AND matchKey1 = ?)
            OR (fld0 = 'TSCCOD' AND (fld1 IS NULL OR fld1 = '') AND matchKey1 = ?)
          )
          AND (validFrom IS NULL OR validFrom <= ?)
          AND (validTo IS NULL OR validTo >= ?)
        ORDER BY priority ASC
      ''', [
        sku,
        customerCode,
        bcgcod,
        tsccod,
        todayStr,
        todayStr,
      ]);
    } else {
      // Optimized SQL: push all criteria down to SQLite
      results = await db.rawQuery('''
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
          AND (validFrom IS NULL OR validFrom <= ?)
          AND (validTo IS NULL OR validTo >= ?)
        ORDER BY priority ASC
      ''', [
        bcgcod, sku,
        tsccod, sku,
        customerCode, sku,
        sku,
        customerCode,
        bcgcod,
        tsccod,
        todayStr,
        todayStr,
      ]);
    }

    if (results.isEmpty) {
      print('Pricing Engine: No matching price lists found for current date $todayStr.');
      return PricingResult.empty();
    }

    print('Pricing Engine: Found ${results.length} active price lists for this context.');

    PricingResult? bestPriceResult;
    PricingResult? bestDiscountResult;
    
    int? bestPricePriority;
    int? bestDiscountPriority;

    for (var row in results) {
      final String? matchKey1 = row['matchKey1']?.toString();
      final String? fld0 = row['fld0']?.toString();
      
      print('MATCHED RULE: pliCode=${row['pliCode']} priority=${row['priority']} ruleType=${row['ruleType']} fld0=$fld0 fil0=${row['fil0']} fld1=${row['fld1']} fil1=${row['fil1']} matchKey1=$matchKey1 matchKey2=${row['matchKey2']} basePrice=${row['basePrice']} isQtyBased=${row['isQtyBased']} minQty=${row['minQty']} maxQty=${row['maxQty']}');

      final int isQtyBased = row['isQtyBased'] as int? ?? 1;
      final double minQty = (row['minQty'] as num?)?.toDouble() ?? 0.0;
      final double maxQty = (row['maxQty'] as num?)?.toDouble() ?? 999999.0;

      if (isQtyBased == 2) {
        if (qty < minQty || qty > maxQty) continue;
      }

      final int ruleType = row['ruleType'] as int? ?? 0;
      final int priority = row['priority'] as int? ?? 9999;
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
        // Discount rule. Sequence priority first, then highest discount.
        if (bestDiscountPriority == null || priority < bestDiscountPriority) {
          bestDiscountPriority = priority;
          bestDiscountResult = PricingResult(
            basePrice: basePrice,
            discountPct: discountPct,
            discountAmt: discountAmt,
            source: source,
            hasFoc: hasFoc,
            focItemSku: focSku,
            focQuantity: focQty,
          );
        } else if (priority == bestDiscountPriority) {
          // Tie-breaker: Highest discount wins
          if (bestDiscountResult != null && (discountPct > bestDiscountResult.discountPct || discountAmt > bestDiscountResult.discountAmt)) {
            bestDiscountResult = PricingResult(
              basePrice: basePrice,
              discountPct: discountPct,
              discountAmt: discountAmt,
              source: source,
              hasFoc: hasFoc,
              focItemSku: focSku,
              focQuantity: focQty,
            );
          }
        }
      } else if (ruleType == 2) {
        // Price rule. Hard stop on priority, but apply lowest price tie-breaker for SAME priority.
        if (bestPricePriority == null || priority < bestPricePriority) {
           bestPricePriority = priority;
           bestPriceResult = PricingResult(
             basePrice: basePrice,
             discountPct: discountPct,
             discountAmt: discountAmt,
             source: source,
             hasFoc: hasFoc,
             focItemSku: focSku,
             focQuantity: focQty,
           );
        } else if (priority == bestPricePriority) {
           // Tie-breaker: Lowest base price wins
           if (bestPriceResult != null && basePrice < bestPriceResult.basePrice) {
             bestPriceResult = PricingResult(
               basePrice: basePrice,
               discountPct: discountPct,
               discountAmt: discountAmt,
               source: source,
               hasFoc: hasFoc,
               focItemSku: focSku,
               focQuantity: focQty,
             );
           } else if (hasFoc && !bestPriceResult!.hasFoc) {
             // Merge FOC if same priority but higher price (assuming FOC applies)
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
        } else if (hasFoc && bestPriceResult != null && !bestPriceResult.hasFoc) {
           // FOC from a lower priority rule? (X3 usually stops at base price, but keeping this just in case)
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

    // If only a discount rule matched (no base price rule), tag the source so the
    // UI knows to keep the price field empty and prompt the user to enter it manually.
    if (finalBasePrice == 0.0 && bestDiscountResult != null && bestPriceResult == null) {
      finalSource = '${bestDiscountResult.source} (discount-only — enter price manually)';
      print('Pricing Engine: Discount-only match. No base price rule found. User must enter price.');
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
