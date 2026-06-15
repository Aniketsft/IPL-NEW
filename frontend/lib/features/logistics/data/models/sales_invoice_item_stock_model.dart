class SalesInvoiceItemStockModel {
  final String itemCode;
  final String itemName;
  final String lotNumber;
  final String warehouse;
  final String warehouseName;
  final String location;
  final String locationType;
  final double totalQty;
  final int isSynced;

  SalesInvoiceItemStockModel({
    required this.itemCode,
    this.itemName = '',
    required this.lotNumber,
    required this.warehouse,
    this.warehouseName = '',
    required this.location,
    this.locationType = '',
    this.totalQty = 0.0,
    this.isSynced = 1,
  });

  factory SalesInvoiceItemStockModel.fromJson(Map<String, dynamic> json) {
    return SalesInvoiceItemStockModel(
      itemCode: (json['itemCode'] ?? '').toString(),
      itemName: (json['itemName'] ?? '').toString(),
      lotNumber: (json['lotNumber'] ?? '').toString(),
      warehouse: (json['warehouse'] ?? '').toString(),
      warehouseName: (json['warehouseName'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      locationType: (json['locationType'] ?? '').toString(),
      totalQty: (json['totalQty'] as num?)?.toDouble() ?? 0.0,
    );
  }

  factory SalesInvoiceItemStockModel.fromSqlMap(Map<String, dynamic> map) {
    return SalesInvoiceItemStockModel(
      itemCode: map['itemCode'] as String,
      itemName: map['itemName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String,
      warehouse: map['warehouse'] as String,
      warehouseName: map['warehouseName'] as String? ?? '',
      location: map['location'] as String,
      locationType: map['locationType'] as String? ?? '',
      totalQty: (map['totalQty'] as num?)?.toDouble() ?? 0.0,
      isSynced: map['isSynced'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toSqlMap(String deviceId) {
    return {
      'itemCode': itemCode,
      'itemName': itemName,
      'lotNumber': lotNumber,
      'warehouse': warehouse,
      'warehouseName': warehouseName,
      'location': location,
      'locationType': locationType,
      'totalQty': totalQty,
      'isSynced': isSynced,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'deviceId': deviceId,
    };
  }
}
