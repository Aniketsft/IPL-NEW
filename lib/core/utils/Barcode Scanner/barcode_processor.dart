import 'package:intl/intl.dart';

class BarcodeProcessor {
  /// Processes a 13-digit barcode according to business rules (priority order):
  /// 1. If barcode starts with '0':
  ///    - Take last 5 digits and divide by 10000.
  ///    - This is the catch weight (manufactured quantity), displayed to 3 decimal places.
  /// 2. If packingUnit is 'KG' (and barcode does NOT start with '0'):
  ///    - Each scan = 1.0 (scan count = manufactured quantity).
  /// 3. If packingUnit is 'EA' (and barcode does NOT start with '0'):
  ///    - manufactured quantity = standardWeight (weight per piece × 1 scan).
  static double calculateQuantity({
    required String barcode,
    required String packingUnit,
    required double standardWeight,
  }) {
    // Rule 1: Catch weight — prefix '0' (Scenario 1)
    if (barcode.startsWith('0') && barcode.length == 13) {
      final weightStr = barcode.substring(8, 13); // Indices 8 to 12
      final weight = (int.tryParse(weightStr) ?? 0) / 1000.0;
      return double.parse(weight.toStringAsFixed(3));
    }

    // Handle Innodis EAN prefix '6091001'
    if (barcode.startsWith('6091001') && barcode.length == 13) {
      return 1.0;
    }

    // Handle other Variable Weight (VW) prefix '20'
    if (barcode.startsWith('20') && barcode.length == 13) {
      final weightStr = barcode.substring(7, 12);
      final weight = (int.tryParse(weightStr) ?? 0) / 1000.0;
      return double.parse(weight.toStringAsFixed(3));
    }

    // Rule 2: KG unit — if not catch weight, default to 1.0 per scan
    if (packingUnit.toUpperCase() == 'KG') {
      return 1.0;
    }

    // Rule 3: EA unit — standardWeight × 1 (weight per piece)
    if (packingUnit.toUpperCase() == 'EA') {
      return standardWeight;
    }

    // Fallback: treat as 1.0
    return 1.0;
  }

  static String formatQuantity(double quantity) {
    final formatter = NumberFormat("0.00");
    return formatter.format(quantity);
  }

  static bool isValidBarcode(String barcode) {
    return barcode.length == 13;
  }
}
