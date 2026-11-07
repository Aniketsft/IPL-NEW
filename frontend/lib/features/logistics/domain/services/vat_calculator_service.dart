import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';

class VatCalculatorService {
  static final Map<String, ({double rate, String code})> _cache = {};

  static void clearCache() => _cache.clear();
  /// Resolves the VAT percentage for a given customer and product tax level.
  /// 
  /// Uses the offline SQLite tables to:
  /// 1. Find the resulting TaxCode from tbl_tax_matrix where customerTaxRule = customerRule AND itemTaxLevel = itemLevel
  /// 2. If a TaxCode is found, look up the rate in tbl_tax_rates
  /// 3. Returns the taxRatePercent or 0.0 if not found
  Future<({double rate, String code})> resolveVatDetails(String customerRule, String itemLevel) async {
    if (customerRule.isEmpty || itemLevel.isEmpty) return (rate: 0.0, code: '');

    final cacheKey = '$customerRule|$itemLevel';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    final db = await LocalDatabaseHelper.instance.database;

    // 1. Get TaxCode from Matrix
    final matrixResult = await db.query(
      LocalDatabaseHelper.tableTaxMatrix,
      columns: [LocalDatabaseHelper.colTaxMatrixTaxCode],
      where: '${LocalDatabaseHelper.colTaxMatrixCustomerRule} = ? AND ${LocalDatabaseHelper.colTaxMatrixItemLevel} = ?',
      whereArgs: [customerRule, itemLevel],
      limit: 1,
    );

    if (matrixResult.isEmpty) {
      debugPrint('VAT Calc: No matrix entry found for $customerRule and $itemLevel');
      final res = (rate: 0.0, code: '');
      _cache[cacheKey] = res;
      return res;
    }

    final taxCode = matrixResult.first[LocalDatabaseHelper.colTaxMatrixTaxCode] as String?;
    if (taxCode == null || taxCode.isEmpty) {
      final res = (rate: 0.0, code: '');
      _cache[cacheKey] = res;
      return res;
    }

    // 2. Lookup Tax Rate
    final rateResult = await db.query(
      LocalDatabaseHelper.tableTaxRates,
      columns: [LocalDatabaseHelper.colTaxRatePercent],
      where: '${LocalDatabaseHelper.colTaxRateTaxCode} = ?',
      whereArgs: [taxCode],
      limit: 1,
    );

    if (rateResult.isEmpty) {
      debugPrint('VAT Calc: No rate found for taxCode=$taxCode');
      final res = (rate: 0.0, code: taxCode);
      _cache[cacheKey] = res;
      return res;
    }

    final rate = (rateResult.first[LocalDatabaseHelper.colTaxRatePercent] as num?)?.toDouble() ?? 0.0;
    debugPrint('VAT Calc: Resulting Rate=$rate, Code=$taxCode');
    final res = (rate: rate, code: taxCode);
    _cache[cacheKey] = res;
    return res;
  }
}
