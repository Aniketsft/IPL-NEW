import 'package:intl/intl.dart';

class BarcodeModel {
  final String itemCode;
  final double weight;
  final String? batchId;
  final bool isValid;

  BarcodeModel({
    required this.itemCode,
    required this.weight,
    this.batchId,
    this.isValid = true,
  });

  factory BarcodeModel.invalid() => BarcodeModel(
        itemCode: '',
        weight: 0.0,
        isValid: false,
      );
}

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
    if (barcode.startsWith('0') && barcode.length >= 13) {
      final weightStr = barcode.substring(barcode.length - 5); // Take last 5 digits
      final weight = (int.tryParse(weightStr) ?? 0) / 1000.0;
      return double.parse(weight.toStringAsFixed(3));
    }

    // Handle Innodis EAN prefix '6091001'
    if (barcode.startsWith('6091001') && barcode.length >= 13) {
      return 1.0;
    }

    // Handle other Variable Weight (VW) prefix '20'
    if (barcode.startsWith('20') && barcode.length >= 13) {
      final weightStr = barcode.substring(barcode.length - 6, barcode.length - 1);
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
    // 1. Check for standard Retail Barcodes (EAN/UPC)
    final validLengths = [8, 12, 13, 14];
    if (validLengths.contains(barcode.length)) return true;

    // 2. Check for Batch/Lot ID (21/22 prefix)
    if (barcode.startsWith('21') || barcode.startsWith('22')) {
      return barcode.length >= 10;
    }

    return false;
  }

  BarcodeModel process(String barcode) {
    if (!isValidBarcode(barcode)) return BarcodeModel.invalid();

    // Priority 1: GS1-128 Batch/Lot (21/22)
    if (barcode.startsWith('21') || barcode.startsWith('22')) {
      final batchId = barcode.substring(2);
      return BarcodeModel(
        itemCode: 'BATCH', // Generic code for batch scans
        weight: 1.0,
        batchId: batchId,
      );
    }

    // Priority 2: Variable Weight (VW) - Prefix "20"
    if (barcode.startsWith('20') && barcode.length == 13) {
      final itemCode = barcode.substring(2, 7);
      final weightStr = barcode.substring(7, 12);
      final weight = (int.tryParse(weightStr) ?? 0) / 1000.0;
      return BarcodeModel(
        itemCode: itemCode,
        weight: weight,
      );
    }

    // Priority 3: Fixed Weight (FW) - Prefix "10"
    if (barcode.startsWith('10') && barcode.length >= 7) {
      final itemCode = barcode.substring(2, 7);
      return BarcodeModel(
        itemCode: itemCode,
        weight: 1.0,
      );
    }

    // Priority 4: Standard EAN-13 (Starts with 0 - Catch Weight)
    if (barcode.startsWith('0') && barcode.length >= 13) {
      final weightStr = barcode.substring(barcode.length - 5);
      final weight = (int.tryParse(weightStr) ?? 0) / 1000.0;
      return BarcodeModel(
        itemCode: barcode.substring(1, 7), // Example extraction
        weight: weight,
      );
    }

    // Default: Generic mapping
    return BarcodeModel(
      itemCode: barcode,
      weight: 1.0,
    );
  }
}

