class SalesOrderDetail {
  final String soNumber;
  final String? poNumber;
  final String? customerCode;
  final String? customerName;
  final DateTime? deliveryDate;
  final String? salesMan1;
  final String? salesMan2;

  final String productCode;
  final String productDescription;
  final String barcodeType;
  final double orderedQuantity;
  final double remainingQuantity;
  final double manufacturedQuantity;

  SalesOrderDetail({
    required this.soNumber,
    this.poNumber,
    this.customerCode,
    this.customerName,
    this.deliveryDate,
    this.salesMan1,
    this.salesMan2,
    required this.productCode,
    required this.productDescription,
    required this.barcodeType,
    required this.orderedQuantity,
    required this.remainingQuantity,
    required this.manufacturedQuantity,
  });

  double get progress =>
      orderedQuantity > 0 ? manufacturedQuantity / orderedQuantity : 0.0;
}
