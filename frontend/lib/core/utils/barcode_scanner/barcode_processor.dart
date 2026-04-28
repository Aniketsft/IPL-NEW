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
  static BarcodeModel process({
    required String barcode,
    required String itemCode,
    required String unit,
    required double standardWeight,
  }) {
    final String originalBarcode = barcode.trim();
    String processedBarcode = originalBarcode;

    // Strict Prefix Validation (Only allow 0, 2, 6)
    final bool isP0 = originalBarcode.startsWith('0');
    final bool isP2 = originalBarcode.startsWith('2');
    final bool isP6 = originalBarcode.startsWith('6');

    if (!isP0 && !isP2 && !isP6) {
      return BarcodeModel.invalid(originalBarcode);
    }

    if (isP2) {
      processedBarcode = '0$originalBarcode';
    }

    double manufacturedQty = 0.0;
    double scannedQty = 0.0;
    
    final String cleanUnit = unit.trim().toUpperCase();
    final bool isEA = cleanUnit == 'EA' || cleanUnit == 'PCS';

    // 1. Calculate Manufactured Quantity (Weight in KG)
    if (isP6) {
      // Fixed weight items use the standard weight from the master
      manufacturedQty = standardWeight;
    } else {
      // Variable weight items (0 or 2) extract from barcode
      if (originalBarcode.length >= 12) {
        final qtyStr = originalBarcode.substring(originalBarcode.length - 6, originalBarcode.length - 1);
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
        // For Prefix 0/2, pieces = weight / standard weight
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
