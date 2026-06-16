class AuditMetadata {
  final String? createdByUserId;
  final String? createdByUserName;
  final String? deviceId;
  final String? appVersion;

  const AuditMetadata({
    this.createdByUserId,
    this.createdByUserName,
    this.deviceId,
    this.appVersion,
  });

  factory AuditMetadata.fromJson(Map<String, dynamic> json) {
    return AuditMetadata(
      createdByUserId: json['createdByUserId'],
      createdByUserName: json['createdByUserName'],
      deviceId: json['deviceId'],
      appVersion: json['appVersion'],
    );
  }
}

class TransactionModel {
  final String id;
  final String type; // 'INVOICE', 'CREDIT_NOTE', 'RETURN'
  final String customerCode;
  final String customerName;
  final double grandTotal;
  final String createdAt;
  final String status;
  final int isSynced;
  final AuditMetadata auditMetadata;

  const TransactionModel({
    required this.id,
    required this.type,
    required this.customerCode,
    required this.customerName,
    required this.grandTotal,
    required this.createdAt,
    required this.status,
    required this.isSynced,
    required this.auditMetadata,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['invoiceId'] ?? '',
      type: json['transactionType'] ?? 'INVOICE',
      customerCode: json['customerCode'] ?? '',
      customerName: json['customerName'] ?? '',
      grandTotal: (json['grandTotal'] ?? 0.0).toDouble(),
      createdAt: json['createdAt'] ?? '',
      status: json['status'] ?? '',
      isSynced: json['isSynced'] ?? 0,
      auditMetadata: AuditMetadata.fromJson(json),
    );
  }
}
