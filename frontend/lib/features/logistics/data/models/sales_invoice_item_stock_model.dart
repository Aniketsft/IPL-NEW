class SalesInvoiceItemStockModel {
  final String itemCode;
  final String itemName;
  final String lotNumber;
  final String warehouse;
  final String warehouseName;
  final String location;
  final String locationType;
  final double totalQty;
  final String taxLevel;
  final String cce0;
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
    this.taxLevel = '',
    this.cce0 = '',
    this.isSynced = 1,
  });

  SalesInvoiceItemStockModel copyWith({
    String? itemCode,
    String? itemName,
    String? lotNumber,
    String? warehouse,
    String? warehouseName,
    String? location,
    String? locationType,
    double? totalQty,
    String? taxLevel,
    String? cce0,
    int? isSynced,
  }) {
    return SalesInvoiceItemStockModel(
      itemCode: itemCode ?? this.itemCode,
      itemName: itemName ?? this.itemName,
      lotNumber: lotNumber ?? this.lotNumber,
      warehouse: warehouse ?? this.warehouse,
      warehouseName: warehouseName ?? this.warehouseName,
      location: location ?? this.location,
      locationType: locationType ?? this.locationType,
      totalQty: totalQty ?? this.totalQty,
      taxLevel: taxLevel ?? this.taxLevel,
      cce0: cce0 ?? this.cce0,
      isSynced: isSynced ?? this.isSynced,
    );
  }

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
      taxLevel: (json['taxLevel'] ?? '').toString(),
      cce0: (json['cce0'] ?? '').toString(),
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
      taxLevel: map['taxLevel'] as String? ?? '',
      cce0: map['cce0'] as String? ?? '',
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
      'taxLevel': taxLevel,
      'cce0': cce0,
      'isSynced': isSynced,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'deviceId': deviceId,
    };
  }
}
