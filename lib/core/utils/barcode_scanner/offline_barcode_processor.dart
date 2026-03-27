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
  final BarcodeProcessor _processor = BarcodeProcessor();

  Future<ScanResult?> processBarcode(String rawBarcode) async {
    if (rawBarcode.isEmpty) return null;

    final model = _processor.process(rawBarcode);

    if (model.isValid) {
      // Look up description in local DB
      final mapping = await _dbHelper.getMappingByItemCode(model.itemCode);
      
      return ScanResult(
        barcode: rawBarcode,
        itemCode: model.itemCode == 'BATCH' ? rawBarcode : model.itemCode,
        description: mapping?.description ?? 'Product ${model.itemCode}',
        weight: model.weight,
        lotNumber: model.batchId,
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
