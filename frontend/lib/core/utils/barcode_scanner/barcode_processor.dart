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
  static String cleanBarcode(String raw) {
    String cleaned = raw.trim();

    // 1. Remove AIM Identifiers (e.g., ]C1, ]E0, ]G1, ]e0)
    // AIM identifiers follow the format ]Xy (3 characters)
    if (cleaned.startsWith(']') && cleaned.length > 3) {
      cleaned = cleaned.substring(3);
    }

    // 2. Remove common GS1 prefixes like 00 (SSCC) or 01 (GTIN) if barcode is long
    // This is optional depending on business rules, but cleaning AIM is critical.

    // 3. Remove non-printable characters
    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), '');

    return cleaned;
  }

  static BarcodeModel process({
    required String barcode,
    required String itemCode,
    required String unit,
    required double standardWeight,
  }) {
    final String originalBarcode = barcode;
    final String cleanedBarcode = cleanBarcode(barcode);
    String processedBarcode = cleanedBarcode;

    // Detect GS1-128 Weight AI (3103 - KG with 3 decimals)
    double? gs1Weight;
    if (cleanedBarcode.contains('3103') && cleanedBarcode.length >= cleanedBarcode.indexOf('3103') + 10) {
      final startIndex = cleanedBarcode.indexOf('3103') + 4;
      final weightStr = cleanedBarcode.substring(startIndex, startIndex + 6);
      gs1Weight = (double.tryParse(weightStr) ?? 0.0) / 1000.0;
    }

    // Strict Prefix Validation (Only allow 0, 2, 6)
    final bool isP0 = cleanedBarcode.startsWith('0');
    final bool isP2 = cleanedBarcode.startsWith('2');
    final bool isP6 = cleanedBarcode.startsWith('6');

    // If it's a GS1 barcode that doesn't start with 0/2/6, we still allow it if we found a weight
    if (!isP0 && !isP2 && !isP6 && gs1Weight == null) {
      return BarcodeModel.invalid(originalBarcode);
    }

    if (isP2) {
      processedBarcode = '0$cleanedBarcode';
    }

    double manufacturedQty = 0.0;
    double scannedQty = 0.0;
    
    final String cleanUnit = unit.trim().toUpperCase();
    final bool isEA = cleanUnit == 'EA' || cleanUnit == 'PCS';

    // 1. Calculate Manufactured Quantity (Weight in KG)
    if (gs1Weight != null) {
      manufacturedQty = gs1Weight;
    } else if (isP6) {
      // Fixed weight items use the standard weight from the master
      manufacturedQty = standardWeight;
    } else {
      // Variable weight items (0 or 2) extract from barcode
      // Typically 12 or 13 digits. Last digit is checksum.
      if (cleanedBarcode.length >= 12) {
        // Extract 5 digits before the checksum
        final qtyStr = cleanedBarcode.substring(cleanedBarcode.length - 6, cleanedBarcode.length - 1);
        manufacturedQty = (double.tryParse(qtyStr) ?? 0.0) / 1000.0;
      } else {
        manufacturedQty = standardWeight;
      }
    }

    // 2. Calculate Scanned Quantity (Piece count for EA, Weight for KG)
    if (isEA) {
      if (isP6) {
        // As per requirement: Prefix 6 EA quantity = no of scans (1.0)
        scannedQty = 1.0;
      } else {
        // For Prefix 0/2 or GS1, pieces = weight / standard weight
        if (standardWeight > 0) {
          scannedQty = manufacturedQty / standardWeight;
        } else {
          scannedQty = 1.0;
        }
      }
    } else {
      // For KG units, scanned qty is the weight
      scannedQty = manufacturedQty;
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
    final String cleanUnit = unit.trim().toUpperCase();
    if (cleanUnit == 'EA' || cleanUnit == 'PCS') {
      return quantity.toStringAsFixed(2);
    }
    return NumberFormat("0.000").format(quantity);
  }

  static bool isValidBarcode(String barcode) {
    final b = barcode.trim();
    if (b.length != 13) return false;
    if (!RegExp(r'^[0-9]+$').hasMatch(b)) return false;
    return b.startsWith('0') || b.startsWith('2') || b.startsWith('6');
  }
}
