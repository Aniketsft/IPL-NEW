class SalesInvoiceProductModel {
  final String sku;
  final String name;
  final double stockQty;
  final String warehouse;
  final String stockUnit;

  SalesInvoiceProductModel({
    required this.sku,
    required this.name,
    required this.stockQty,
    required this.warehouse,
    required this.stockUnit,
  });

  factory SalesInvoiceProductModel.fromJson(Map<String, dynamic> json) {
    return SalesInvoiceProductModel(
      sku: (json['sku'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      stockQty: double.tryParse((json['stockQty'] ?? '0').toString()) ?? 0.0,
      warehouse: (json['warehouse'] ?? '').toString(),
      stockUnit: (json['stockUnit'] ?? '').toString(),
    );
  }
}
