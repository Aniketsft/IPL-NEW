import 'package:intl/intl.dart';

class BarcodeModel {
  final String itemCode;
  final double scannedQty;
  final double manufacturedQty;
  final String originalBarcode;
  final String processedBarcode;
  final bool isValid;

  BarcodeModel({
    required this.itemCode,
    this.scannedQty = 0.0,
    this.manufacturedQty = 0.0,
    required this.originalBarcode,
    required this.processedBarcode,
    this.isValid = true,
  });

  factory BarcodeModel.invalid(String barcode) => BarcodeModel(
    itemCode: '',
    originalBarcode: barcode,
    processedBarcode: barcode,
    isValid: false,
  );
}

class BarcodeProcessor {
  /// Processes a barcode according to complex business rules for prefixes 2 and 6.
  /// Standardizes output into scanned vs manufactured quantities.
  static BarcodeModel process({
    required String barcode,
    required String itemCode,
    required String unit,
    required double standardWeight,
  }) {
    String originalBarcode = barcode;
    String processedBarcode = barcode;

    // Rule: if prefix starts with 2, add a 0 at the start of the barcode
    if (barcode.startsWith('2')) {
      processedBarcode = '0$barcode';
    }

    double scannedQty = 0.0;
    double manufacturedQty = 0.0;
    final isKG = unit.toUpperCase() == 'KG';
    final isEA = unit.toUpperCase() == 'EA';

    // Case 1 & 2 (Prefix 2 or Prefix 0)
    if (barcode.startsWith('2') || barcode.startsWith('0')) {
      if (isKG) {
        // Case 1: ignore last digit (check digit) take last 4 digit indices 9 10 11 12 divide by 1000
        // User probably means indices 9-12 based on 1-based indexing for a 13 digit barcode.
        // In 0-indexed: index 8, 9, 10, 11 if barcode is length 13.
        // If it starts with '0' (already padded), we adjust the logic slightly or use the same indices.
        if (barcode.length >= 12) {
          // Rule: Ignore the very last check digit (at length-1) and take the 5 preceding digits.
          final qtyStr = barcode.substring(barcode.length - 6, barcode.length - 1);
          scannedQty = (double.tryParse(qtyStr) ?? 0.0) / 1000.0;
          manufacturedQty = scannedQty; // Default for KG
        } else {
          scannedQty = 1.0;
          manufacturedQty = 1.0;
        }
      } else if (isEA) {
        // Case 2: scanned qty = number of scans (1 for individual scan).
        // manufactured qty = standard weight of product x no of scan.
        scannedQty = 1.0;
        manufacturedQty = standardWeight;
      }
    } else if (barcode.startsWith('6')) {
      // Case 3 & 4 (Prefix 6)
      if (isKG) {
        // Case 3: scanned qty = standard weight x no of scan.
        scannedQty = standardWeight;
        manufacturedQty = standardWeight;
      } else if (isEA) {
        // Case 4: scanned qty = number of scans.
        // manufactured qty = standard weight of product x no of scan.
        scannedQty = 1.0;
        manufacturedQty = standardWeight;
      }
    } else {
      // Fallback/Legacy Logic
      if (isKG) {
        scannedQty = 1.0;
        manufacturedQty = 1.0;
      } else {
        scannedQty = 1.0;
        manufacturedQty = standardWeight;
      }
    }

    return BarcodeModel(
      itemCode: itemCode,
      scannedQty: scannedQty,
      manufacturedQty: manufacturedQty,
      originalBarcode: originalBarcode,
      processedBarcode: processedBarcode,
    );
  }

  static String formatQuantity(double quantity, String unit) {
    if (unit.toUpperCase() == 'EA') {
      return quantity.toInt().toString();
    }
    final formatter = NumberFormat("0.000");
    return formatter.format(quantity);
  }

  static bool isValidBarcode(String barcode) {
    // Basic validation: at least 7 chars
    return barcode.trim().length >= 7;
  }
}
