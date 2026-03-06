class SalesOrderDto {
  final String soNumber;
  final String customerCode;
  final String customerName;
  final String deliveryDate;
  final String? salesman;
  final String? deliveryFrom;
  final String? deliveryNo;
  final String? deliveryLorry;
  final String? deliverySalesman;
  final String? soLorry;
  final String? oriSoLorry;
  final String? poNumber;

  SalesOrderDto({
    required this.soNumber,
    required this.customerCode,
    required this.customerName,
    required this.deliveryDate,
    this.salesman,
    this.deliveryFrom,
    this.deliveryNo,
    this.deliveryLorry,
    this.deliverySalesman,
    this.soLorry,
    this.oriSoLorry,
    this.poNumber,
  });

  factory SalesOrderDto.fromJson(Map<String, dynamic> json) {
    return SalesOrderDto(
      soNumber: json['soNo'] ?? json['soNumber'] ?? '',
      customerCode: json['oriSoCustCode'] ?? json['customerCode'] ?? '',
      customerName: json['oriSoCustName'] ?? json['customerName'] ?? '',
      deliveryDate: json['soDeliveryDate'] ?? json['deliveryDate'] ?? '',
      salesman: json['soSalesman'] ?? json['salesman'],
      deliveryFrom: json['deliveryFrom'],
      deliveryNo: json['deliveryNo'],
      deliveryLorry: json['deliveryLorry'],
      deliverySalesman: json['deliverySalesman'],
      soLorry: json['soLorry'],
      oriSoLorry: json['oriSoLorry'],
      poNumber: json['poNo'] ?? json['poNumber'],
    );
  }
}
