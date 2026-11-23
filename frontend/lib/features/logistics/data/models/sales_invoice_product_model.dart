class SalesInvoiceProductModel {
  final String sku;
  final String name;
  final double stockQty;
  final String warehouse;
  final String salesUnit;
  final String cce0;
  final String barcode;
  final String stockStatus;

  SalesInvoiceProductModel({
    required this.sku,
    required this.name,
    required this.stockQty,
    required this.warehouse,
    required this.salesUnit,
    this.cce0 = '',
    this.barcode = '',
    this.stockStatus = 'A',
  });

  factory SalesInvoiceProductModel.fromJson(Map<String, dynamic> json) {
    return SalesInvoiceProductModel(
      sku: (json['sku'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      stockQty: double.tryParse((json['stockQty'] ?? '0').toString()) ?? 0.0,
      warehouse: (json['warehouse'] ?? '').toString(),
      salesUnit: (json['salesUnit'] ?? '').toString(),
      cce0: (json['cce0'] ?? '').toString(),
      barcode: (json['barcode'] ?? '').toString(),
      stockStatus: (json['stockStatus'] ?? 'A').toString().trim().toUpperCase(),
    );
  }

  SalesInvoiceProductModel copyWith({
    String? sku,
    String? name,
    double? stockQty,
    String? warehouse,
    String? salesUnit,
    String? cce0,
    String? barcode,
    String? stockStatus,
  }) {
    return SalesInvoiceProductModel(
      sku: sku ?? this.sku,
      name: name ?? this.name,
      stockQty: stockQty ?? this.stockQty,
      warehouse: warehouse ?? this.warehouse,
      salesUnit: salesUnit ?? this.salesUnit,
      cce0: cce0 ?? this.cce0,
      barcode: barcode ?? this.barcode,
      stockStatus: stockStatus ?? this.stockStatus,
    );
  }
}
