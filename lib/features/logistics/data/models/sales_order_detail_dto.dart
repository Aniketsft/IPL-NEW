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
  final double remainingQuantity;
  final double manufactured;
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
    required this.remainingQuantity,
    required this.manufactured,
    this.salesMan1,
    this.salesMan2,
  });

  factory SalesOrderDetailDto.fromJson(Map<String, dynamic> json) {
    return SalesOrderDetailDto(
      soNumber: json['soNumber'] ?? '',
      poNumber: json['poNumber']?.toString(),
      customerCode: json['customerCode']?.toString(),
      customerName: json['customerName']?.toString(),
      deliveryDate: json['deliveryDate']?.toString(),
      productCode: json['productCode']?.toString(),
      productDescription: json['productDescription']?.toString(),
      barcodeType: json['barcodeType']?.toString(),
      orderedQuantity: (json['orderedQuantity'] as num?)?.toDouble() ?? 0.0,
      remainingQuantity: (json['remainingQuantity'] as num?)?.toDouble() ?? 0.0,
      manufactured: (json['manufactured'] as num?)?.toDouble() ?? 0.0,
      salesMan1: json['salesMan1']?.toString(),
      salesMan2: json['salesMan2']?.toString(),
    );
  }
}
