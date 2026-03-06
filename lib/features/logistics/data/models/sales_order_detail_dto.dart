class SalesOrderDetailDto {
  final String soNumber;
  final String? poNumber;
  final String? customerCode;
  final String? customerName;
  final String? deliveryDate;
  final String? productCode;
  final String? productDescription;
  final String? barcodeType;
  final double orderedQuantity;
  final String? remainingQuantity;
  final String? manufactured;
  final String? salesMan1;
  final String? salesMan2;

  SalesOrderDetailDto({
    required this.soNumber,
    this.poNumber,
    this.customerCode,
    this.customerName,
    this.deliveryDate,
    this.productCode,
    this.productDescription,
    this.barcodeType,
    required this.orderedQuantity,
    this.remainingQuantity,
    this.manufactured,
    this.salesMan1,
    this.salesMan2,
  });

  factory SalesOrderDetailDto.fromJson(Map<String, dynamic> json) {
    return SalesOrderDetailDto(
      soNumber: json['soNumber'] ?? '',
      poNumber: json['poNumber'],
      customerCode: json['customerCode'],
      customerName: json['customerName'],
      deliveryDate: json['deliveryDate'],
      productCode: json['productCode'],
      productDescription: json['productDescription'],
      barcodeType: json['barcodeType'],
      orderedQuantity: (json['orderedQuantity'] as num?)?.toDouble() ?? 0.0,
      remainingQuantity: json['remainingQuantity']?.toString(),
      manufactured: json['manufactured']?.toString(),
      salesMan1: json['salesMan1']?.toString(),
      salesMan2: json['salesMan2']?.toString(),
    );
  }
}
