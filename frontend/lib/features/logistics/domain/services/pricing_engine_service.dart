import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/entities/pricing_result.dart';

/// Helper model to track candidate rule evaluation steps for terminal debugging.
class _CandidateRuleEval {
  final String pli;
  final int priority;
  final int ruleType;
  final String matchKey1;
  final String matchKey2;
  final double basePrice;
  final double discountPct;
  final double discountAmt;
  final String validFrom;
  final String validTo;
  final String status;

  _CandidateRuleEval({
    required this.pli,
    required this.priority,
    required this.ruleType,
    required this.matchKey1,
    required this.matchKey2,
    required this.basePrice,
    required this.discountPct,
    required this.discountAmt,
    this.validFrom = '',
    this.validTo = '',
    required this.status,
  });
}

class PricingEngineService {
  final LocalDatabaseHelper _dbHelper = LocalDatabaseHelper.instance;

  Future<PricingResult> resolvePrice({
    required String customerCode,
    required String bcgcod,
    required String tsccod,
    String? bpcsho,
    int? facilityFlag,
    required String sku,
    required double qty,
    Database? database,
  }) async {
    final db = database ?? await _dbHelper.database;
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final String customerBpcsho = (bpcsho ?? '').trim();

    // Step 1: Inter-site / Facility Override
    // Condition: If Customer BETFCY_0 == 2 OR BCGCOD == 'INTER'.
    // Action: Bypass standard logic. Query the local matrix strictly for Price List T40.
    final bool isFacility = (facilityFlag == 2) || (bcgcod.trim().toUpperCase() == 'INTER');
    if (isFacility) {
      final List<Map<String, dynamic>> t40Results = await db.rawQuery('''
        SELECT * FROM ${LocalDatabaseHelper.tablePriceLists}
        WHERE pliCode = 'T40'
          AND (
            (fld0 IN ('FCY', 'BPCNUM', 'BPCSHO') AND fld1 = 'ITMREF' AND (matchKey1 = ? OR ? LIKE matchKey1 || '%') AND matchKey2 = ?)
            OR (fld0 = 'ITMREF' AND matchKey1 = ?)
          )
        ORDER BY priority ASC, reasonType ASC, basePrice ASC
      ''', [customerCode, customerCode, sku, sku]);

      Map<String, dynamic>? winningT40Row;
      PricingResult? facilityResult;

      for (var row in t40Results) {
        final String? validFrom = row['validFrom']?.toString()?.trim();
        final String? validTo = row['validTo']?.toString()?.trim();
        // 1. Date Validity Gate (Primary Filter)
        if (validFrom != null && validFrom.isNotEmpty && validFrom != '1753-01-01' && validFrom != '1900-01-01' && validFrom.compareTo(todayStr) > 0) continue;
        if (validTo != null && validTo.isNotEmpty && validTo != '1753-01-01' && validTo != '1900-01-01' && validTo.compareTo(todayStr) < 0) continue;

        final int isQtyBased = row['isQtyBased'] as int? ?? 1;
        final double minQty = (row['minQty'] as num?)?.toDouble() ?? 0.0;
        final double maxQty = (row['maxQty'] as num?)?.toDouble() ?? 999999.0;
        final double mQty = maxQty <= 0 ? 999999.0 : maxQty;

        if (isQtyBased == 2) {
          if (qty < minQty || qty > mQty) continue;
        }

        final double basePrice = (row['basePrice'] as num?)?.toDouble() ?? 0.0;
        final double discountPct = (row['discountPct'] as num?)?.toDouble() ?? 0.0;
        final double discountAmt = (row['discountAmt'] as num?)?.toDouble() ?? 0.0;
        final int reasonType = row['reasonType'] as int? ?? 0;
        final int focType = row['focType'] as int? ?? 1;

        bool hasFoc = false;
        String focSku = '';
        double focQuantity = 0.0;

        if (focType == 2 || focType == 3) {
          final double focQtyMin = (row['focQtyMin'] as num?)?.toDouble() ?? 0.0;
          final double focQtyBkt = (row['focQtyBkt'] as num?)?.toDouble() ?? 1.0;
          final double ruleFocQty = (row['focQty'] as num?)?.toDouble() ?? 0.0;
          final String ruleFocSku = row['focItmRef']?.toString() ?? '';

          if (focQtyMin > 0 && focQtyBkt > 0 && qty >= focQtyMin) {
            final double buckets = (qty / focQtyBkt).floorToDouble();
            if (buckets > 0) {
              focQuantity = buckets * ruleFocQty;
              hasFoc = focQuantity > 0;
              focSku = ruleFocSku.isEmpty ? sku : ruleFocSku;
            }
          }
        }

        if (basePrice > 0) {
          winningT40Row = row;
          facilityResult = PricingResult(
            basePrice: basePrice,
            discountPct: discountPct,
            discountAmt: 0.0,
            discountAmountFlat: discountAmt,
            source: 'T40',
            priceListCode: 'T40',
            reasonType: reasonType,
            hasFoc: hasFoc,
            focItemSku: focSku,
            focQuantity: focQuantity,
          );
          break;
        }
      }

      final finalResult = facilityResult ?? PricingResult.empty();
      _printFacilityMatrix(
        customerCode: customerCode,
        bcgcod: bcgcod,
        facilityFlag: facilityFlag,
        sku: sku,
        qty: qty,
        todayStr: todayStr,
        rawT40Rules: t40Results,
        winningRule: winningT40Row,
        finalResult: finalResult,
      );

      // Facility customer must have T40 rule; if none found, return empty
      return finalResult;
    }

    // Step 2: Pre-Filtering (Eligibility) for Standard Commercial Customers
    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT * FROM ${LocalDatabaseHelper.tablePriceLists}
      WHERE pliCode != 'T40'
        AND (
          (fld0 = 'BCGCOD' AND fld1 = 'ITMREF' AND matchKey1 = ? AND matchKey2 = ?)
          OR (fld0 = 'TSCCOD' AND fld1 = 'ITMREF' AND matchKey1 = ? AND matchKey2 = ?)
          OR (fld0 = 'BPCNUM' AND fld1 = 'ITMREF' AND (matchKey1 = ? OR ? LIKE matchKey1 || '%') AND matchKey2 = ?)
          OR (fld0 = 'BPCSHO' AND fld1 = 'ITMREF' AND (matchKey1 = ? OR matchKey1 = ?) AND matchKey2 = ?)
          OR (fld0 = 'ITMREF' AND (fld1 IS NULL OR fld1 = '') AND matchKey1 = ?)
          OR (fld0 = 'BPCNUM' AND (fld1 IS NULL OR fld1 = '') AND (matchKey1 = ? OR ? LIKE matchKey1 || '%'))
          OR (fld0 = 'BPCSHO' AND (fld1 IS NULL OR fld1 = '') AND (matchKey1 = ? OR matchKey1 = ?))
          OR (fld0 = 'BCGCOD' AND (fld1 IS NULL OR fld1 = '') AND matchKey1 = ?)
          OR (fld0 = 'TSCCOD' AND (fld1 IS NULL OR fld1 = '') AND matchKey1 = ?)
        )
      ORDER BY priority ASC, reasonType ASC, basePrice ASC, discountPct DESC, discountAmt DESC
    ''', [
      bcgcod, sku,
      tsccod, sku,
      customerCode, customerCode, sku,
      customerBpcsho, customerCode, sku,
      sku,
      customerCode, customerCode,
      customerBpcsho, customerCode,
      bcgcod,
      tsccod
    ]);

    final List<_CandidateRuleEval> candidateLogs = [];

    if (results.isEmpty) {
      _printCommercialMatrix(
        customerCode: customerCode,
        bcgcod: bcgcod,
        tsccod: tsccod,
        bpcsho: customerBpcsho,
        facilityFlag: facilityFlag,
        sku: sku,
        qty: qty,
        todayStr: todayStr,
        evaluations: candidateLogs,
        winningBasePrice: null,
        winningBasePricePriority: null,
        candidateDiscount: null,
        candidateDiscountPriority: null,
        discountProtectionPassed: false,
        finalResult: PricingResult.empty(),
      );
      return PricingResult.empty();
    }

    PricingResult? bestBasePrice;
    int? bestBasePricePriority;
    
    PricingResult? bestDiscount;
    int? bestDiscountPriority;

    for (var row in results) {
      final String pliCode = row['pliCode']?.toString() ?? '';
      final int priority = row['priority'] as int? ?? 999;
      final int ruleType = row['ruleType'] as int? ?? 0;
      final String matchKey1 = row['matchKey1']?.toString() ?? '';
      final String matchKey2 = row['matchKey2']?.toString() ?? '';

      final double basePrice = (row['basePrice'] as num?)?.toDouble() ?? 0.0;
      final double discountPct = (row['discountPct'] as num?)?.toDouble() ?? 0.0;
      final double discountAmt = (row['discountAmt'] as num?)?.toDouble() ?? 0.0;
      final int reasonType = row['reasonType'] as int? ?? 0;
      final int focType = row['focType'] as int? ?? 1;

      final String? validFrom = row['validFrom']?.toString()?.trim();
      final String? validTo = row['validTo']?.toString()?.trim();
      // 1. Date Validity Gate (Primary Filter)
      if (validFrom != null && validFrom.isNotEmpty && validFrom != '1753-01-01' && validFrom != '1900-01-01' && validFrom.compareTo(todayStr) > 0) {
        candidateLogs.add(_CandidateRuleEval(
          pli: pliCode,
          priority: priority,
          ruleType: ruleType,
          matchKey1: matchKey1,
          matchKey2: matchKey2,
          basePrice: basePrice,
          discountPct: discountPct,
          discountAmt: discountAmt,
          validFrom: validFrom ?? '',
          validTo: validTo ?? '',
          status: '[SKIP] Inactive future rule (validFrom: $validFrom > $todayStr)',
        ));
        continue;
      }
      if (validTo != null && validTo.isNotEmpty && validTo != '1753-01-01' && validTo != '1900-01-01' && validTo.compareTo(todayStr) < 0) {
        candidateLogs.add(_CandidateRuleEval(
          pli: pliCode,
          priority: priority,
          ruleType: ruleType,
          matchKey1: matchKey1,
          matchKey2: matchKey2,
          basePrice: basePrice,
          discountPct: discountPct,
          discountAmt: discountAmt,
          validFrom: validFrom ?? '',
          validTo: validTo ?? '',
          status: '[SKIP] Expired rule (validTo: $validTo < $todayStr)',
        ));
        continue;
      }

      final int isQtyBased = row['isQtyBased'] as int? ?? 1;
      final double minQty = (row['minQty'] as num?)?.toDouble() ?? 0.0;
      final double maxQty = (row['maxQty'] as num?)?.toDouble() ?? 999999.0;
      final double mQty = maxQty <= 0 ? 999999.0 : maxQty;

      if (isQtyBased == 2) {
        if (qty < minQty || qty > mQty) {
          candidateLogs.add(_CandidateRuleEval(
            pli: pliCode,
            priority: priority,
            ruleType: ruleType,
            matchKey1: matchKey1,
            matchKey2: matchKey2,
            basePrice: basePrice,
            discountPct: discountPct,
            discountAmt: discountAmt,
            validFrom: validFrom ?? '',
            validTo: validTo ?? '',
            status: '[SKIP] Qty $qty outside bracket [$minQty - $mQty]',
          ));
          continue;
        }
      }

      bool hasFoc = false;
      String focSku = '';
      double focQuantity = 0.0;

      // FOC Logic (Step 6 / FOCPRO_0 = 2 or 3)
      if (focType == 2 || focType == 3) {
        final double focQtyMin = (row['focQtyMin'] as num?)?.toDouble() ?? 0.0;
        final double focQtyBkt = (row['focQtyBkt'] as num?)?.toDouble() ?? 1.0;
        final double focAmtMin = (row['focAmtMin'] as num?)?.toDouble() ?? 0.0;
        final double focAmtBkt = (row['focAmtBkt'] as num?)?.toDouble() ?? 1.0;
        final double ruleFocQty = (row['focQty'] as num?)?.toDouble() ?? 0.0;
        final String ruleFocSku = row['focItmRef']?.toString() ?? '';

        bool criteriaMet = false;
        double buckets = 0;

        if (focQtyMin > 0 && focQtyBkt > 0 && qty >= focQtyMin) {
          criteriaMet = true;
          buckets = (qty / focQtyBkt).floorToDouble();
        }
        
        // Amount-based FOC implementation (FOCAMTMIN_0 / FOCAMTBKT_0)
        double lineAmount = qty * basePrice; 
        if (!criteriaMet && focAmtMin > 0 && focAmtBkt > 0 && lineAmount >= focAmtMin) {
          criteriaMet = true;
          buckets = (lineAmount / focAmtBkt).floorToDouble();
        }

        if (criteriaMet && buckets > 0) {
           focQuantity = buckets * ruleFocQty;
           hasFoc = focQuantity > 0;
           focSku = ruleFocSku.isEmpty ? sku : ruleFocSku;
        }
      }

      // X3 PRIPRO_0 evaluation: 2 = Value (Price), 1 = No (Discount)
      final bool isPriceRule = (ruleType == 2) || (ruleType == 0 && basePrice > 0);
      final bool isDiscountRule = (ruleType == 1) || (ruleType == 0 && basePrice == 0 && (discountPct > 0 || discountAmt > 0 || hasFoc));

      final List<String> matchStatuses = [];

      // 1. Evaluate Base Price (PRIPRO = 2)
      if (isPriceRule && basePrice > 0) {
        if (bestBasePrice == null) {
          bestBasePricePriority = priority;
          bestBasePrice = PricingResult(
            basePrice: basePrice,
            discountPct: discountPct,
            discountAmt: 0.0,
            discountAmountFlat: discountAmt,
            source: pliCode,
            priceListCode: pliCode,
            reasonType: reasonType,
            hasFoc: hasFoc,
            focItemSku: focSku,
            focQuantity: focQuantity,
          );
          matchStatuses.add('[WINNING BASE] Rs ${basePrice.toStringAsFixed(2)} (Prio: $priority)');
        } else if (priority == bestBasePricePriority) {
          // Priority Tie-breaker for Price: Pick the minimum price
          if (basePrice < bestBasePrice.basePrice) {
            bestBasePrice = PricingResult(
              basePrice: basePrice,
              discountPct: discountPct,
              discountAmt: 0.0,
              discountAmountFlat: discountAmt,
              source: pliCode,
              priceListCode: pliCode,
              reasonType: reasonType,
              hasFoc: hasFoc,
              focItemSku: focSku,
              focQuantity: focQuantity,
            );
            matchStatuses.add('[WINNING BASE] Min-price tie-break won (Rs ${basePrice.toStringAsFixed(2)} < Rs ${bestBasePrice.basePrice.toStringAsFixed(2)})');
          } else {
            matchStatuses.add('[SKIP BASE] Equal prio ($priority) but higher/equal price');
          }
        } else {
          matchStatuses.add('[SKIP BASE] Lower prio ($priority > $bestBasePricePriority)');
        }
      }

      // 2. Evaluate Discount (PRIPRO = 1 or standalone promotion)
      if (isDiscountRule || discountPct > 0 || discountAmt > 0 || hasFoc) {
        // Only consider if not already using this exact rule as base price
        if (bestBasePrice == null || bestBasePrice.priceListCode != pliCode || basePrice == 0) {
          if (bestDiscount == null) {
            bestDiscountPriority = priority;
            bestDiscount = PricingResult(
              basePrice: 0.0,
              discountPct: discountPct,
              discountAmt: 0.0,
              discountAmountFlat: discountAmt,
              source: pliCode,
              priceListCode: pliCode,
              reasonType: reasonType,
              hasFoc: hasFoc,
              focItemSku: focSku,
              focQuantity: focQuantity,
            );
            matchStatuses.add('[CANDIDATE DISC] ${discountPct > 0 ? '$discountPct%' : 'Rs $discountAmt'}${hasFoc ? ' + FOC' : ''} (Prio: $priority)');
          } else if (priority == bestDiscountPriority) {
            // Priority Tie-breaker for Discount: Pick the highest discount
            final double currentBestMaxDisc = bestDiscount.discountPct > 0 ? bestDiscount.discountPct : bestDiscount.discountAmountFlat;
            final double thisMaxDisc = discountPct > 0 ? discountPct : discountAmt;
            if (thisMaxDisc > currentBestMaxDisc) {
              bestDiscount = PricingResult(
                basePrice: 0.0,
                discountPct: discountPct,
                discountAmt: 0.0,
                discountAmountFlat: discountAmt,
                source: pliCode,
                priceListCode: pliCode,
                reasonType: reasonType,
                hasFoc: hasFoc,
                focItemSku: focSku,
                focQuantity: focQuantity,
              );
              matchStatuses.add('[CANDIDATE DISC] Max-discount tie-break won');
            } else {
              matchStatuses.add('[SKIP DISC] Equal prio ($priority) but lower discount');
            }
          } else if (bestDiscountPriority != null && priority > bestDiscountPriority) {
            matchStatuses.add('[SKIP DISC] Lower prio ($priority > $bestDiscountPriority)');
          }
        }
      }

      candidateLogs.add(_CandidateRuleEval(
        pli: pliCode,
        priority: priority,
        ruleType: ruleType,
        matchKey1: matchKey1,
        matchKey2: matchKey2,
        basePrice: basePrice,
        discountPct: discountPct,
        discountAmt: discountAmt,
        validFrom: validFrom ?? '',
        validTo: validTo ?? '',
        status: matchStatuses.isEmpty ? '[EVALUATED]' : matchStatuses.join(' | '),
      ));
    }

    // A valid base price is mandatory (discount-only matches without a base price cannot form an invoice line).
    if (bestBasePrice == null) {
      _printCommercialMatrix(
        customerCode: customerCode,
        bcgcod: bcgcod,
        tsccod: tsccod,
        facilityFlag: facilityFlag,
        sku: sku,
        qty: qty,
        todayStr: todayStr,
        evaluations: candidateLogs,
        winningBasePrice: null,
        winningBasePricePriority: null,
        candidateDiscount: null,
        candidateDiscountPriority: null,
        discountProtectionPassed: false,
        finalResult: PricingResult.empty(),
      );
      return PricingResult.empty();
    }

    double finalBasePrice = bestBasePrice.basePrice;
    double finalDiscPct = bestBasePrice.discountPct;
    double finalDiscAmt = bestBasePrice.discountAmountFlat;
    String finalSource = bestBasePrice.source;
    String finalPliCode = bestBasePrice.priceListCode;
    int finalReasonType = bestBasePrice.reasonType;
    
    bool finalHasFoc = bestBasePrice.hasFoc;
    String finalFocSku = bestBasePrice.focItemSku;
    double finalFocQty = bestBasePrice.focQuantity;
    bool discountProtectionPassed = false;

    // Apply discount protection: Discount priority must be <= Winning Base Price priority
    if (bestDiscount != null && bestDiscountPriority != null && bestBasePricePriority != null) {
       if (bestDiscountPriority <= bestBasePricePriority) {
          discountProtectionPassed = true;
          if (bestDiscount.discountPct > 0) finalDiscPct = bestDiscount.discountPct;
          if (bestDiscount.discountAmountFlat > 0) finalDiscAmt = bestDiscount.discountAmountFlat;
          if (bestDiscount.hasFoc && !finalHasFoc) {
             finalHasFoc = true;
             finalFocSku = bestDiscount.focItemSku;
             finalFocQty = bestDiscount.focQuantity;
          }
          if (bestDiscount.source != finalSource) {
             finalSource = "$finalSource & ${bestDiscount.source}";
          }
       }
    }

    final finalResult = PricingResult(
      basePrice: finalBasePrice,
      discountPct: finalDiscPct,
      discountAmt: 0.0,
      discountAmountFlat: finalDiscAmt,
      source: finalSource,
      priceListCode: finalPliCode,
      reasonType: finalReasonType,
      hasFoc: finalHasFoc,
      focItemSku: finalFocSku,
      focQuantity: finalFocQty,
    );

    _printCommercialMatrix(
      customerCode: customerCode,
      bcgcod: bcgcod,
      tsccod: tsccod,
      bpcsho: customerBpcsho,
      facilityFlag: facilityFlag,
      sku: sku,
      qty: qty,
      todayStr: todayStr,
      evaluations: candidateLogs,
      winningBasePrice: bestBasePrice,
      winningBasePricePriority: bestBasePricePriority,
      candidateDiscount: bestDiscount,
      candidateDiscountPriority: bestDiscountPriority,
      discountProtectionPassed: discountProtectionPassed,
      finalResult: finalResult,
    );

    return finalResult;
  }

  void _printFacilityMatrix({
    required String customerCode,
    required String bcgcod,
    required int? facilityFlag,
    required String sku,
    required double qty,
    required String todayStr,
    required List<Map<String, dynamic>> rawT40Rules,
    required Map<String, dynamic>? winningRule,
    required PricingResult finalResult,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('');
    buffer.writeln('========================================================================================================');
    buffer.writeln('                      [SAGE X3 PRICING ENGINE - CALCULATION MATRIX]');
    buffer.writeln('========================================================================================================');
    buffer.writeln(' CUSTOMER CONTEXT (INTER-SITE / FACILITY TRANSFER):');
    buffer.writeln('   * Customer Code : $customerCode');
    buffer.writeln('   * Category (BCG): $bcgcod');
    buffer.writeln('   * Facility Flag : ${facilityFlag ?? 1} (BETFCY = 2 or BCGCOD = INTER -> Bypass standard pricing)');
    buffer.writeln(' ITEM CONTEXT:');
    buffer.writeln('   * SKU (ITMREF)  : $sku');
    buffer.writeln('   * Order Qty     : $qty');
    buffer.writeln('   * Evaluation Dt : $todayStr');
    buffer.writeln('');
    buffer.writeln(' FACILITY RESOLUTION (STRICT T40 SEARCH):');
    if (winningRule != null) {
      final prio = winningRule['priority'];
      final bp = (winningRule['basePrice'] as num?)?.toDouble() ?? 0.0;
      final dp = (winningRule['discountPct'] as num?)?.toDouble() ?? 0.0;
      buffer.writeln('   * Matched T40 Rule    : PLI=T40 | Priority=$prio | BasePrice=Rs ${bp.toStringAsFixed(2)} | Disc=${dp.toStringAsFixed(1)}% | Status=[WINNING RULE]');
    } else {
      buffer.writeln('   * Matched T40 Rule    : NONE (No active/valid T40 price found for facility transfer)');
    }
    buffer.writeln('');
    buffer.writeln(' FINAL SELECTED OUTCOME:');
    buffer.writeln('   * Selected Price Code : ${finalResult.priceListCode.isEmpty ? "(None)" : finalResult.priceListCode}');
    buffer.writeln('   * Source Trace        : ${finalResult.source.isEmpty ? "(None)" : finalResult.source}');
    buffer.writeln('   * Base Unit Price     : Rs ${finalResult.basePrice.toStringAsFixed(2)}');
    buffer.writeln('   * Final Net Unit Price: Rs ${finalResult.basePrice.toStringAsFixed(2)} / unit');
    buffer.writeln('========================================================================================================');
    debugPrint(buffer.toString());
  }

  void _printCommercialMatrix({
    required String customerCode,
    required String bcgcod,
    required String tsccod,
    String? bpcsho,
    required int? facilityFlag,
    required String sku,
    required double qty,
    required String todayStr,
    required List<_CandidateRuleEval> evaluations,
    required PricingResult? winningBasePrice,
    required int? winningBasePricePriority,
    required PricingResult? candidateDiscount,
    required int? candidateDiscountPriority,
    required bool discountProtectionPassed,
    required PricingResult finalResult,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('');
    buffer.writeln('========================================================================================================');
    buffer.writeln('                      [SAGE X3 PRICING ENGINE - CALCULATION MATRIX]');
    buffer.writeln('========================================================================================================');
    buffer.writeln(' CUSTOMER CONTEXT:');
    buffer.writeln('   * Customer Code : $customerCode');
    buffer.writeln('   * Category (BCG): $bcgcod');
    buffer.writeln('   * Stat Group    : ${tsccod.isEmpty ? "(None)" : tsccod}');
    buffer.writeln('   * Short/Group   : ${(bpcsho != null && bpcsho.isNotEmpty) ? bpcsho : "(None)"} (BPCSHO)');
    buffer.writeln('   * Facility Flag : ${facilityFlag ?? 1} (Standard Commercial)');
    buffer.writeln(' ITEM CONTEXT:');
    buffer.writeln('   * SKU (ITMREF)  : $sku');
    buffer.writeln('   * Order Qty     : $qty');
    buffer.writeln('   * Evaluation Dt : $todayStr');
    buffer.writeln('');
    buffer.writeln(' CANDIDATE RULES EVALUATION:');
    buffer.writeln(' | PLI       | PRIO | TYPE | MATCH_KEY1           | MATCH_KEY2      | BASE_PRICE | DISC_% | DISC_AMT | VALID_FROM | VALID_TO   | EVALUATION STATUS');
    buffer.writeln(' |-----------|------|------|----------------------|-----------------|------------|--------|----------|------------|------------|----------------------------------------');
    
    if (evaluations.isEmpty) {
      buffer.writeln(' | (No eligible candidate rules returned from local database query)                                     |');
    } else {
      for (final ev in evaluations) {
        final pli = ev.pli.padRight(9);
        final prio = ev.priority.toString().padLeft(4);
        final type = (ev.ruleType == 2 ? 'PRICE' : (ev.ruleType == 1 ? 'DISC' : 'ANY')).padRight(4);
        final k1 = ev.matchKey1.padRight(20);
        final k2 = (ev.matchKey2.isEmpty ? '-' : ev.matchKey2).padRight(15);
        final bp = ev.basePrice.toStringAsFixed(2).padLeft(10);
        final dp = '${ev.discountPct.toStringAsFixed(1)}%'.padLeft(6);
        final da = ev.discountAmt.toStringAsFixed(2).padLeft(8);
        final vf = (ev.validFrom.isEmpty || ev.validFrom == '1753-01-01' || ev.validFrom == '1900-01-01' ? '          ' : ev.validFrom).padRight(10);
        final vt = (ev.validTo.isEmpty || ev.validTo == '1753-01-01' || ev.validTo == '1900-01-01' ? '(open)    ' : ev.validTo).padRight(10);
        buffer.writeln(' | $pli | $prio | $type | $k1 | $k2 | $bp | $dp | $da | $vf | $vt | ${ev.status}');
      }
    }

    buffer.writeln('');
    buffer.writeln(' PRECEDENCE RESOLUTION:');
    if (winningBasePrice != null) {
      buffer.writeln('   * Winning Base Price : ${winningBasePrice.priceListCode} (Price: Rs ${winningBasePrice.basePrice.toStringAsFixed(2)}, Priority: $winningBasePricePriority)');
    } else {
      buffer.writeln('   * Winning Base Price : NONE');
    }

    if (candidateDiscount != null && candidateDiscountPriority != null && winningBasePricePriority != null) {
      final discDesc = candidateDiscount.discountPct > 0
          ? '${candidateDiscount.discountPct.toStringAsFixed(1)}%'
          : 'Rs ${candidateDiscount.discountAmountFlat.toStringAsFixed(2)}';
      if (discountProtectionPassed) {
        buffer.writeln('   * Applied Discount   : ${candidateDiscount.priceListCode} ($discDesc) [PROTECTION PASSED: Prio $candidateDiscountPriority <= $winningBasePricePriority]');
      } else {
        buffer.writeln('   * Applied Discount   : REJECTED ${candidateDiscount.priceListCode} ($discDesc) [BLOCKED: Prio $candidateDiscountPriority > Winning Prio $winningBasePricePriority]');
      }
    } else if (winningBasePrice != null && winningBasePrice.discountPct > 0) {
      buffer.writeln('   * Applied Discount   : Inherited from ${winningBasePrice.priceListCode} (${winningBasePrice.discountPct.toStringAsFixed(1)}%)');
    } else {
      buffer.writeln('   * Applied Discount   : None');
    }

    if (finalResult.hasFoc) {
      buffer.writeln('   * FOC Awarded        : YES -> ${finalResult.focQuantity.toStringAsFixed(1)} x SKU: ${finalResult.focItemSku}');
    } else {
      buffer.writeln('   * FOC Awarded        : None');
    }

    buffer.writeln('');
    buffer.writeln(' FINAL SELECTED OUTCOME:');
    buffer.writeln('   * Selected Price Code : ${finalResult.priceListCode.isEmpty ? "(None)" : finalResult.priceListCode}');
    buffer.writeln('   * Source Trace        : ${finalResult.source.isEmpty ? "(None)" : finalResult.source}');
    buffer.writeln('   * Base Unit Price     : Rs ${finalResult.basePrice.toStringAsFixed(2)}');
    buffer.writeln('   * Discount            : ${finalResult.discountPct.toStringAsFixed(1)}% (Rs ${finalResult.discountAmountFlat.toStringAsFixed(2)})');
    
    double netPrice = finalResult.basePrice;
    if (finalResult.discountPct > 0) {
      netPrice = netPrice * (1.0 - (finalResult.discountPct / 100.0));
    }
    if (finalResult.discountAmountFlat > 0) {
      netPrice = (netPrice - finalResult.discountAmountFlat).clamp(0.0, double.infinity);
    }
    buffer.writeln('   * Final Net Unit Price: Rs ${netPrice.toStringAsFixed(2)} / unit');
    buffer.writeln('========================================================================================================');
    debugPrint(buffer.toString());
  }
}
