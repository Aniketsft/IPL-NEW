import '../local/local_database_helper.dart';

class SalesOrderDetailDto {
  final String soNumber;
  final String? poNumber;
  final String? customerCode;
  final String? customerName;
  final String? deliveryDate;
  final String? itemCode;
  final String? description;
  final String? barcodeType;
  final double quantity;
  final double remaining;
  final double scannedQuantity;
  final String? salesMan1;
  final String? salesMan2;
  final String? site;
  final String? location;
  final String? lot;
  final String? warehouse;
  final String? warehouseName;
  final String? locationType;
  final String? locationTypeName;
  final bool isPrepared;
  final String unit;

  SalesOrderDetailDto({
    required this.soNumber,
    this.poNumber,
    this.customerCode,
    this.customerName,
    this.deliveryDate,
    this.salesMan1,
    this.salesMan2,
    this.site,
    this.location,
    this.lot,
    this.warehouse,
    this.warehouseName,
    this.locationType,
    this.locationTypeName,
    required this.itemCode,
    required this.description,
    required this.barcodeType,
    required this.quantity,
    required this.remaining,
    required this.scannedQuantity,
    this.isPrepared = false,
    this.unit = 'KG',
  });

  factory SalesOrderDetailDto.fromJson(Map<String, dynamic> json) {
    return SalesOrderDetailDto(
      soNumber: json['soNumber'] ?? '',
      poNumber: json['poNumber']?.toString(),
      customerCode: json['customerCode']?.toString(),
      customerName: json['customerName']?.toString(),
      deliveryDate: json['deliveryDate']?.toString(),
      salesMan1: json['salesMan1']?.toString(),
      salesMan2: json['salesMan2']?.toString(),
      site: json['site']?.toString(),
      location: json['location']?.toString(),
      lot: json['lot']?.toString(),
      warehouse: json['warehouse']?.toString(),
      warehouseName: json['warehouseName']?.toString(),
      locationType: json['locationType']?.toString(),
      locationTypeName: json['locationTypeName']?.toString(),
      itemCode: json['itemCode']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      barcodeType: json['barcodeType']?.toString() ?? 'Variable Weight',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      remaining: (json['remaining'] as num?)?.toDouble() ?? 0.0,
      scannedQuantity: (json['manufactured'] as num?)?.toDouble() ?? 0.0,
      isPrepared: json['isPrepared'] == 1 || json['isPrepared'] == true,
      unit: json['unit']?.toString() ?? 'KG',
    );
  }

  Map<String, dynamic> toSqlMap() {
    return {
      'soNumber': soNumber,
      'itemCode': itemCode,
      'description': description,
      'barcodeType': barcodeType,
      'quantity': quantity,
      'scanned': scannedQuantity,
      'remaining': remaining,
      'site': site,
      'location': location,
      'lot': lot,
      'warehouse': warehouse,
      'warehouseName': warehouseName,
      'locationType': locationType,
      'locationTypeName': locationTypeName,
      LocalDatabaseHelper.colDetIsPrepared: isPrepared ? 1 : 0,
      LocalDatabaseHelper.colDetUnit: unit,
    };
  }
}
