import 'db_helper.dart';
import 'barcode_processor.dart';

class ScanResult {
  final String barcode;
  final String itemCode;
  final String description;
  final double weight;
  final String? lotNumber;

  ScanResult({
    required this.barcode,
    required this.itemCode,
    required this.description,
    required this.weight,
    this.lotNumber,
  });
}

class OfflineBarcodeProcessor {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<ScanResult?> processBarcode(String rawBarcode) async {
    if (rawBarcode.isEmpty) return null;

    // 1. Initial Lookup to get metadata for calculation
    String lookupBarcode = rawBarcode.startsWith('2') ? '0$rawBarcode' : rawBarcode;
    final mapping = await _dbHelper.getMappingByBarcode(lookupBarcode);

    // 2. Process using specialized rules
    final model = BarcodeProcessor.process(
      barcode: rawBarcode,
      itemCode: mapping?.itemCode ?? 'UNKNOWN',
      unit: mapping?.unit ?? 'KG',
      standardWeight: mapping?.unitFactor ?? 1.0,
    );

    if (model.isValid) {
      return ScanResult(
        barcode: rawBarcode,
        itemCode: model.itemCode == 'BATCH' ? rawBarcode : model.itemCode,
        description: mapping?.description ?? 'Product ${model.itemCode}',
        weight: model.manufacturedQty,
        lotNumber: null, // Batch logic moved out
      );
    }

    // Exact Match Fallback
    final exactMatch = await _dbHelper.getMappingByBarcode(rawBarcode);
    if (exactMatch != null) {
      return ScanResult(
        barcode: rawBarcode,
        itemCode: exactMatch.itemCode,
        description: exactMatch.description,
        weight: 1.0,
      );
    }

    return null;
  }
}
