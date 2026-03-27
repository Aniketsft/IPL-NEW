class BarcodeMapping {
  final String itemCode;
  final String barcode;
  final String description;
  final String barcodeType;
  final double unitFactor;
  final String expectedPrefix;
  final String unit;

  BarcodeMapping({
    required this.itemCode,
    required this.barcode,
    required this.description,
    required this.barcodeType,
    required this.unitFactor,
    required this.expectedPrefix,
    required this.unit,
  });

  factory BarcodeMapping.fromMap(Map<String, dynamic> map) {
    return BarcodeMapping(
      itemCode: map['itemCode'] ?? '',
      barcode: map['barcode'] ?? '',
      description: map['description'] ?? '',
      barcodeType: map['barcodeType'] ?? '',
      unitFactor: (map['unitFactor'] ?? 1.0).toDouble(),
      expectedPrefix: map['expectedPrefix'] ?? '',
      unit: map['unit'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'itemCode': itemCode,
      'barcode': barcode,
      'description': description,
      'barcodeType': barcodeType,
      'unitFactor': unitFactor,
      'expectedPrefix': expectedPrefix,
      'unit': unit,
    };
  }
}
