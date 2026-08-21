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
  final double scannedQuantity;
  final double manufacturedQuantity;
  final double eaScannedQuantity;
  final bool isPrepared; // Manufacturing "Prepared"
  final bool isValidated; // Logistics "Validated for Shipment"
  final bool isFpp; // Indicates if this specific product is FPP
  final String unit;

  // Header level statuses from JOIN
  final bool headerIsClosed;
  final bool headerIsPreparedForShipment;

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
    required this.scannedQuantity,
    required this.manufacturedQuantity,
    this.eaScannedQuantity = 0.0,
    this.isPrepared = false,
    this.isValidated = false,
    this.isFpp = false,
    this.unit = 'KG',
    this.headerIsClosed = false,
    this.headerIsPreparedForShipment = false,
  });

  // CB orders: quantity=0, manufactured grows freely. Show 100% if any production happened.
  double get progress {
    final bool isEA = unit.toUpperCase() == 'EA' || unit.toUpperCase() == 'PCS';
    final double produced = isEA ? eaScannedQuantity : manufacturedQuantity;
    return quantity > 0
        ? produced / quantity
        : (produced > 0 ? 1.0 : 0.0);
  }

  String formatQuantity(double value) {
    if (unit == 'EA' || unit == 'PCS') {
      return value.toStringAsFixed(2);
    }
    return value.toStringAsFixed(3);
  }

  String get remainingDisplay {
    if (remaining < 0) {
      return '+${formatQuantity(remaining.abs())}';
    }
    return formatQuantity(remaining);
  }

  SalesOrderDetail copyWith({
    String? soNumber,
    String? poNumber,
    String? customerCode,
    String? customerName,
    DateTime? deliveryDate,
    String? salesMan1,
    String? salesMan2,
    String? site,
    String? location,
    String? lot,
    String? warehouse,
    String? warehouseName,
    String? locationType,
    String? locationTypeName,
    String? itemCode,
    String? description,
    String? barcodeType,
    double? quantity,
    double? remaining,
    double? scannedQuantity,
    double? manufacturedQuantity,
    double? eaScannedQuantity,
    bool? isPrepared,
    bool? isValidated,
    bool? isFpp,
    String? unit,
    bool? headerIsClosed,
    bool? headerIsPreparedForShipment,
  }) {
    return SalesOrderDetail(
      soNumber: soNumber ?? this.soNumber,
      poNumber: poNumber ?? this.poNumber,
      customerCode: customerCode ?? this.customerCode,
      customerName: customerName ?? this.customerName,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      salesMan1: salesMan1 ?? this.salesMan1,
      salesMan2: salesMan2 ?? this.salesMan2,
      site: site ?? this.site,
      location: location ?? this.location,
      lot: lot ?? this.lot,
      warehouse: warehouse ?? this.warehouse,
      warehouseName: warehouseName ?? this.warehouseName,
      locationType: locationType ?? this.locationType,
      locationTypeName: locationTypeName ?? this.locationTypeName,
      itemCode: itemCode ?? this.itemCode,
      description: description ?? this.description,
      barcodeType: barcodeType ?? this.barcodeType,
      quantity: quantity ?? this.quantity,
      remaining: remaining ?? this.remaining,
      scannedQuantity: scannedQuantity ?? this.scannedQuantity,
      manufacturedQuantity: manufacturedQuantity ?? this.manufacturedQuantity,
      eaScannedQuantity: eaScannedQuantity ?? this.eaScannedQuantity,
      isPrepared: isPrepared ?? this.isPrepared,
      isValidated: isValidated ?? this.isValidated,
      isFpp: isFpp ?? this.isFpp,
      unit: unit ?? this.unit,
      headerIsClosed: headerIsClosed ?? this.headerIsClosed,
      headerIsPreparedForShipment:
          headerIsPreparedForShipment ?? this.headerIsPreparedForShipment,
    );
  }
}

