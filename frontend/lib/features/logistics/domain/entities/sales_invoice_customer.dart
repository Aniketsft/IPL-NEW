class SalesInvoiceCustomer {
  final String code;
  final String name;
  final String? paymentTerm;
  final double? creditLimit;
  final int? statusFlag;
  final int isSynced;

  SalesInvoiceCustomer({
    required this.code,
    required this.name,
    this.paymentTerm,
    this.creditLimit,
    this.statusFlag,
    this.isSynced = 1,
  });

  factory SalesInvoiceCustomer.fromJson(Map<String, dynamic> json) {
    return SalesInvoiceCustomer(
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      paymentTerm: json['paymentTerm'],
      creditLimit: json['creditLimit'] != null ? (json['creditLimit'] as num).toDouble() : null,
      statusFlag: json['statusFlag'] != null ? int.tryParse(json['statusFlag'].toString()) : null,
      isSynced: json['isSynced'] ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'paymentTerm': paymentTerm,
      'creditLimit': creditLimit,
      'statusFlag': statusFlag,
      'isSynced': isSynced,
    };
  }
}
