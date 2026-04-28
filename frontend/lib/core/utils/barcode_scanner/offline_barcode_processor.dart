import 'barcode_processor.dart';
import '../../../../features/logistics/data/local/local_database_helper.dart';

class ScanResult {
  final String barcode;
  final String itemCode;
  final String description;
  final double weight;
  final double standardWeight;
  final String unit;
  final String? lotNumber;

  ScanResult({
    required this.barcode,
    required this.itemCode,
    required this.description,
    required this.weight,
    required this.standardWeight,
    required this.unit,
    this.lotNumber,
  });
}

class OfflineBarcodeProcessor {
  Future<ScanResult?> processBarcode(String rawBarcode) async {
    if (rawBarcode.isEmpty) return null;

    final db = await LocalDatabaseHelper.instance.database;
    Map<String, dynamic>? product;

    // 1. Identify Prefix and Prepare Lookup Key
    if (rawBarcode.startsWith('2')) {
      // Logic: Prefix 2, take first 6 digits and prepend '0' (Total 7 digits)
      final searchCode = "0${rawBarcode.substring(0, 6)}";
      
      final results = await db.query(
        LocalDatabaseHelper.tableProducts,
        where: '${LocalDatabaseHelper.colProdCode} = ? OR ${LocalDatabaseHelper.colProdBarcode} = ?',
        whereArgs: [searchCode, searchCode],
      );
      if (results.isNotEmpty) product = results.first;
      
    } else if (rawBarcode.startsWith('02') && rawBarcode.length >= 7) {
      // Logic: Prefix 02, those starting with 02 must map first 7 digits
      final searchCode = rawBarcode.substring(0, 7);
      
      final results = await db.query(
        LocalDatabaseHelper.tableProducts,
        where: '${LocalDatabaseHelper.colProdCode} = ? OR ${LocalDatabaseHelper.colProdBarcode} = ?',
        whereArgs: [searchCode, searchCode],
      );
      if (results.isNotEmpty) product = results.first;

    } else {
      // Logic: Full barcode search (Prefix 6 or other standard codes)
      final results = await db.query(
        LocalDatabaseHelper.tableProducts,
        where: '${LocalDatabaseHelper.colProdBarcode} = ? OR ${LocalDatabaseHelper.colProdCode} = ?',
        whereArgs: [rawBarcode, rawBarcode],
      );
      if (results.isNotEmpty) product = results.first;
    }

    // 2. Critical: If no product found in Master Table, fail here
    if (product == null) return null;

    final String itemCode = product[LocalDatabaseHelper.colProdCode] as String;
    final String unit = product[LocalDatabaseHelper.colProdSau] as String? ?? 'KG';
    final double stdWeight = (product[LocalDatabaseHelper.colProdStandardWeight] as num?)?.toDouble() ?? 1.0;
    final String description = product[LocalDatabaseHelper.colProdDesc] as String? ?? 'Product';

    // 3. Calculate weights/quantities using specialized business rules
    final model = BarcodeProcessor.process(
      barcode: rawBarcode,
      itemCode: itemCode,
      unit: unit,
      standardWeight: stdWeight,
    );

    if (model.isValid) {
      return ScanResult(
        barcode: rawBarcode,
        itemCode: model.itemCode == 'BATCH' ? rawBarcode : model.itemCode,
        description: description,
        weight: model.manufacturedQty,
        standardWeight: stdWeight,
        unit: unit,
        lotNumber: null,
      );
    }

    return null;
  }
}
