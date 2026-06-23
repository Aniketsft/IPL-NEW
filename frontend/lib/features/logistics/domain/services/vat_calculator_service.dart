import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';

class VatCalculatorService {
  /// Resolves the VAT percentage for a given customer and product tax level.
  /// 
  /// Uses the offline SQLite tables to:
  /// 1. Find the resulting TaxCode from tbl_tax_matrix where customerTaxRule = customerRule AND itemTaxLevel = itemLevel
  /// 2. If a TaxCode is found, look up the rate in tbl_tax_rates
  /// 3. Returns the taxRatePercent or 0.0 if not found
  Future<({double rate, String code})> resolveVatDetails(String customerRule, String itemLevel) async {
    if (customerRule.isEmpty || itemLevel.isEmpty) return (rate: 0.0, code: '');

    final db = await LocalDatabaseHelper.instance.database;
    
    // DEBUG: dump table contents
    final allEntries = await db.query(LocalDatabaseHelper.tableTaxMatrix, limit: 5);
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM ${LocalDatabaseHelper.tableTaxMatrix}'));
    debugPrint('VAT Calc: Total rows in tbl_tax_matrix=$count. First 5: $allEntries');

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
      return (rate: 0.0, code: '');
    }

    final taxCode = matrixResult.first[LocalDatabaseHelper.colTaxMatrixTaxCode] as String?;
    debugPrint('VAT Calc: Matrix gave taxCode=$taxCode');

    if (taxCode == null || taxCode.isEmpty) {
      return (rate: 0.0, code: '');
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
      return (rate: 0.0, code: taxCode);
    }

    final rate = (rateResult.first[LocalDatabaseHelper.colTaxRatePercent] as num?)?.toDouble() ?? 0.0;
    debugPrint('VAT Calc: Found final rate=$rate for code=$taxCode');
    return (rate: rate, code: taxCode);
  }
}
