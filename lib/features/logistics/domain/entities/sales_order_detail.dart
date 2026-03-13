class SalesOrderDetail {
  final String soNumber;
  final String? poNumber;
  final String? customerCode;
  final String? customerName;
  final DateTime? deliveryDate;
  final String? salesMan1;
  final String? salesMan2;

  final String? site;
  final String? location;
  final String? lot;
  final String? warehouse;
  final String? warehouseName;
  final String? locationType;
  final String? locationTypeName;

  final String itemCode;
  final String description;
  final String barcodeType;
  final double quantity;
  final double remaining;
  final double manufacturedQuantity;

  SalesOrderDetail({
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
    required this.manufacturedQuantity,
  });

  // CB orders: quantity=0, manufactured grows freely. Show 100% if any production happened.
  double get progress => quantity > 0
      ? manufacturedQuantity / quantity
      : (manufacturedQuantity > 0 ? 1.0 : 0.0);

  String get remainingDisplay {
    if (remaining < 0) {
      return '+${remaining.abs().toStringAsFixed(2)}';
    }
    return remaining.toStringAsFixed(2);
  }
}
