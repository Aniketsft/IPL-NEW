class SalesOrderDto {
  final String soNumber;
  final String customerCode;
  final String customerName;
  final String deliveryDate;
  final String orderDate;
  final String? rep0;
  final String? rep1;
  final String? site;
  final int? status;
  final String? source;
  final String? statusLabel;
  final String? poNo;

  SalesOrderDto({
    required this.soNumber,
    required this.customerCode,
    required this.customerName,
    required this.deliveryDate,
    required this.orderDate,
    this.rep0,
    this.rep1,
    this.site,
    this.status,
    this.source,
    this.statusLabel,
    this.poNo,
  });

  factory SalesOrderDto.fromJson(Map<String, dynamic> json) {
    return SalesOrderDto(
      soNumber: json['sohNum'] ?? json['soNo'] ?? json['soNumber'] ?? '',
      customerCode: json['customerCode'] ?? json['oriSoCustCode'] ?? '',
      customerName: json['customerName'] ?? json['oriSoCustName'] ?? '',
      deliveryDate: json['deliveryDate'] ?? json['soDeliveryDate'] ?? '',
      orderDate:
          json['orderDate'] ??
          json['soDeliveryDate'] ??
          '', // Fallback to delivery date
      rep0: json['rep0'] ?? json['soSalesman'],
      rep1: json['rep1']?.toString(),
      site: json['site']?.toString(),
      status: json['status'] as int?,
      source: json['source']?.toString(),
      statusLabel: json['statusLabel']?.toString(),
      poNo: json['poNo'] ?? json['poNumber'],
    );
  }

  Map<String, dynamic> toSqlMap() {
    return {
      'sohNum': soNumber,
      'poNo': poNo,
      'orderDate': orderDate,
      'deliveryDate': deliveryDate,
      'customerCode': customerCode,
      'customerName': customerName,
      'rep0': rep0,
      'rep1': rep1,
      'site': site,
      'status': status,
      'source': source,
      'statusLabel': statusLabel,
      'isSynced': 1, // Server-provided data is officially synced
    };
  }
}
