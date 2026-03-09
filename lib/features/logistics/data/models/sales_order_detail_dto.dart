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
  final double manufactured;
  final String? salesMan1;
  final String? salesMan2;
  final String? site;
  final String? location;
  final String? lot;

  SalesOrderDetailDto({
    required this.soNumber,
    this.poNumber,
    this.customerCode,
    this.customerName,
    this.deliveryDate,
    this.itemCode,
    this.description,
    this.barcodeType,
    required this.quantity,
    required this.remaining,
    required this.manufactured,
    this.salesMan1,
    this.salesMan2,
    this.site,
    this.location,
    this.lot,
  });

  factory SalesOrderDetailDto.fromJson(Map<String, dynamic> json) {
    return SalesOrderDetailDto(
      soNumber: json['soNumber'] ?? '',
      poNumber: json['poNumber']?.toString(),
      customerCode: json['customerCode']?.toString(),
      customerName: json['customerName']?.toString(),
      deliveryDate: json['deliveryDate']?.toString(),
      itemCode: json['itemCode']?.toString(),
      description: json['description']?.toString(),
      barcodeType: json['barcodeType']?.toString(),
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      remaining: (json['remaining'] as num?)?.toDouble() ?? 0.0,
      manufactured: (json['manufactured'] as num?)?.toDouble() ?? 0.0,
      salesMan1: json['salesMan1']?.toString(),
      salesMan2: json['salesMan2']?.toString(),
      site: json['site']?.toString(),
      location: json['location']?.toString(),
      lot: json['lot']?.toString(),
    );
  }
}
