class OpenInvoiceModel {
  final int? id;
  final String documentNo;
  final String customerNo;
  final String customerName;
  final String dueDate;
  final String site;
  final String company;
  final String docType; // 'INV' or 'CN'
  final double remainingAmtLCY;
  final double allocatedAmount;
  final bool isPaid;
  final String? lastSyncAt;

  OpenInvoiceModel({
    this.id,
    required this.documentNo,
    required this.customerNo,
    this.customerName = '',
    required this.dueDate,
    required this.site,
    required this.company,
    required this.docType,
    required this.remainingAmtLCY,
    this.allocatedAmount = 0.0,
    this.isPaid = false,
    this.lastSyncAt,
  });

  bool get isCreditNote => docType.toUpperCase() == 'CN' || remainingAmtLCY < 0;
  bool get isInvoice => !isCreditNote;

  factory OpenInvoiceModel.fromMap(Map<String, dynamic> map) {
    return OpenInvoiceModel(
      id: map['id'] as int?,
      documentNo: (map['documentNo'] ?? map['DocumentNo'] ?? '').toString().trim(),
      customerNo: (map['customerNo'] ?? map['CustomerNo'] ?? '').toString().trim(),
      customerName: (map['customerName'] ?? map['CustomerName'] ?? '').toString().trim(),
      dueDate: (map['dueDate'] ?? map['DueDate'] ?? '').toString().trim(),
      site: (map['site'] ?? map['Site'] ?? '').toString().trim(),
      company: (map['company'] ?? map['Company'] ?? '').toString().trim(),
      docType: (map['docType'] ?? map['DocType'] ?? 'INV').toString().trim(),
      remainingAmtLCY: (map['remainingAmtLCY'] ?? map['RemainingAmtLCY'] as num?)?.toDouble() ?? 0.0,
      allocatedAmount: (map['allocatedAmount'] as num?)?.toDouble() ?? 0.0,
      isPaid: (map['isPaid'] ?? 0) == 1,
      lastSyncAt: map['lastSyncAt'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'documentNo': documentNo,
      'customerNo': customerNo,
      'customerName': customerName,
      'dueDate': dueDate,
      'site': site,
      'company': company,
      'docType': docType,
      'remainingAmtLCY': remainingAmtLCY,
      'allocatedAmount': allocatedAmount,
      'isPaid': isPaid ? 1 : 0,
      'lastSyncAt': lastSyncAt,
    };
  }

  OpenInvoiceModel copyWith({
    int? id,
    String? documentNo,
    String? customerNo,
    String? customerName,
    String? dueDate,
    String? site,
    String? company,
    String? docType,
    double? remainingAmtLCY,
    double? allocatedAmount,
    bool? isPaid,
    String? lastSyncAt,
  }) {
    return OpenInvoiceModel(
      id: id ?? this.id,
      documentNo: documentNo ?? this.documentNo,
      customerNo: customerNo ?? this.customerNo,
      customerName: customerName ?? this.customerName,
      dueDate: dueDate ?? this.dueDate,
      site: site ?? this.site,
      company: company ?? this.company,
      docType: docType ?? this.docType,
      remainingAmtLCY: remainingAmtLCY ?? this.remainingAmtLCY,
      allocatedAmount: allocatedAmount ?? this.allocatedAmount,
      isPaid: isPaid ?? this.isPaid,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }
}
