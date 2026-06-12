class SalesInvoiceItemStockModel {
  final String itemCode;
  final String lotNumber;
  final String warehouse;
  final String location;
  final String locationType;
  final int isSynced;

  SalesInvoiceItemStockModel({
    required this.itemCode,
    required this.lotNumber,
    required this.warehouse,
    required this.location,
    this.locationType = '',
    this.isSynced = 1,
  });

  factory SalesInvoiceItemStockModel.fromJson(Map<String, dynamic> json) {
    return SalesInvoiceItemStockModel(
      itemCode: (json['itemCode'] ?? '').toString(),
      lotNumber: (json['lotNumber'] ?? '').toString(),
      warehouse: (json['warehouse'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      locationType: (json['locationType'] ?? '').toString(),
    );
  }

  factory SalesInvoiceItemStockModel.fromSqlMap(Map<String, dynamic> map) {
    return SalesInvoiceItemStockModel(
      itemCode: map['itemCode'] as String,
      lotNumber: map['lotNumber'] as String,
      warehouse: map['warehouse'] as String,
      location: map['location'] as String,
      locationType: map['locationType'] as String,
      isSynced: map['isSynced'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toSqlMap(String deviceId) {
    return {
      'itemCode': itemCode,
      'lotNumber': lotNumber,
      'warehouse': warehouse,
      'location': location,
      'locationType': locationType,
      'isSynced': isSynced,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'deviceId': deviceId,
    };
  }
}
