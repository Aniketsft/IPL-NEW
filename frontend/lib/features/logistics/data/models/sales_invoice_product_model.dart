class SalesInvoiceProductModel {
  final String sku;
  final String name;
  final double stockQty;
  final String warehouse;
  final String salesUnit;
  final String cce0;

  SalesInvoiceProductModel({
    required this.sku,
    required this.name,
    required this.stockQty,
    required this.warehouse,
    required this.salesUnit,
    this.cce0 = '',
  });

  factory SalesInvoiceProductModel.fromJson(Map<String, dynamic> json) {
    return SalesInvoiceProductModel(
      sku: (json['sku'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      stockQty: double.tryParse((json['stockQty'] ?? '0').toString()) ?? 0.0,
      warehouse: (json['warehouse'] ?? '').toString(),
      salesUnit: (json['salesUnit'] ?? '').toString(),
      cce0: (json['cce0'] ?? '').toString(),
    );
  }
}
