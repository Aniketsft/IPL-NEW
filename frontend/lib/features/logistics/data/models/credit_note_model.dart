import 'dart:convert';

class CreditNoteType {
  static const String reversal = 'REVERSAL';
  static const String standalone = 'STANDALONE';
  static const String amountOnly = 'AMOUNT_ONLY';
  static const String cashOnly = 'AMOUNT_ONLY';
}

class CreditNoteRefundMethod {
  static const String cash = 'CASH';
  static const String credit = 'CREDIT';
  static const String cheque = 'CHEQUE';
}

class CreditNoteModel {
  final String creditNoteId;
  final String creditNoteType;
  final String x3CreditNoteType;
  final String salesSite;
  final String customerCode;
  final String customerName;
  final String currency;
  final double grandTotal;
  final String? originalInvoiceId;
  final List<String> linkedInvoiceIds;
  final String settlementType;
  final String? reference;
  final int isSynced;
  final String? x3DocumentId;
  final String createdAt;
  final String createdBy;
  final String? deviceId;
  final List<CreditNoteLineModel> lines;
  final List<CreditNoteRefundModel> refunds;

  CreditNoteModel({
    required this.creditNoteId,
    required this.creditNoteType,
    this.x3CreditNoteType = 'CRN',
    required this.salesSite,
    required this.customerCode,
    required this.customerName,
    this.currency = 'MUR',
    required this.grandTotal,
    this.originalInvoiceId,
    this.linkedInvoiceIds = const [],
    required this.settlementType,
    this.reference,
    this.isSynced = 0,
    this.x3DocumentId,
    required this.createdAt,
    required this.createdBy,
    this.deviceId,
    this.lines = const [],
    this.refunds = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'creditNoteId': creditNoteId,
      'creditNoteType': creditNoteType,
      'x3CreditNoteType': x3CreditNoteType,
      'salesSite': salesSite,
      'customerCode': customerCode,
      'customerName': customerName,
      'currency': currency,
      'grandTotal': grandTotal,
      'originalInvoiceId': originalInvoiceId,
      'linkedInvoiceIds': linkedInvoiceIds.isNotEmpty ? jsonEncode(linkedInvoiceIds) : null,
      'settlementType': settlementType,
      'reference': reference,
      'isSynced': isSynced,
      'x3DocumentId': x3DocumentId,
      'createdAt': createdAt,
      'createdBy': createdBy,
      'deviceId': deviceId,
    };
  }

  factory CreditNoteModel.fromMap(
    Map<String, dynamic> map, {
    List<CreditNoteLineModel> lines = const [],
    List<CreditNoteRefundModel> refunds = const [],
  }) {
    List<String> linked = [];
    if (map['linkedInvoiceIds'] != null) {
      try {
        final decoded = jsonDecode(map['linkedInvoiceIds'] as String);
        if (decoded is List) {
          linked = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {
        linked = (map['linkedInvoiceIds'] as String).split(',').map((e) => e.trim()).toList();
      }
    }

    return CreditNoteModel(
      creditNoteId: map['creditNoteId'] ?? '',
      creditNoteType: map['creditNoteType'] ?? CreditNoteType.reversal,
      x3CreditNoteType: map['x3CreditNoteType'] ?? 'CRN',
      salesSite: map['salesSite'] ?? '',
      customerCode: map['customerCode'] ?? '',
      customerName: map['customerName'] ?? '',
      currency: map['currency'] ?? 'MUR',
      grandTotal: (map['grandTotal'] as num?)?.toDouble() ?? 0.0,
      originalInvoiceId: map['originalInvoiceId'],
      linkedInvoiceIds: linked,
      settlementType: map['settlementType'] ?? CreditNoteRefundMethod.cash,
      reference: map['reference'],
      isSynced: map['isSynced'] ?? 0,
      x3DocumentId: map['x3DocumentId'],
      createdAt: map['createdAt'] ?? '',
      createdBy: map['createdBy'] ?? '',
      deviceId: map['deviceId'],
      lines: lines,
      refunds: refunds,
    );
  }
}

class CreditNoteLineModel {
  final int? lineId;
  final String creditNoteId;
  final int lineNo;
  final double quantity;

  // Lean references for Reversal / Cash Only
  final String? originInvoiceId;
  final int? originLineNo;

  // Standalone fields
  final String? standaloneSku;
  final String? standaloneName;
  final String? standaloneSalesUnit;
  final double? standalonePrice;
  final String? standaloneTaxRule;
  final String? standaloneLot;
  final String? standaloneWarehouse;
  final String? standaloneCce0;

  // Merged / Resolved values
  final String? resolvedSku;
  final String? resolvedName;
  final String? resolvedSalesUnit;
  final double? resolvedPrice;
  final String? resolvedTaxRule;
  final String? resolvedLot;
  final String? resolvedWarehouse;
  final String? resolvedCce0;

  CreditNoteLineModel({
    this.lineId,
    required this.creditNoteId,
    required this.lineNo,
    required this.quantity,
    this.originInvoiceId,
    this.originLineNo,
    this.standaloneSku,
    this.standaloneName,
    this.standaloneSalesUnit,
    this.standalonePrice,
    this.standaloneTaxRule,
    this.standaloneLot,
    this.standaloneWarehouse,
    this.standaloneCce0,
    this.resolvedSku,
    this.resolvedName,
    this.resolvedSalesUnit,
    this.resolvedPrice,
    this.resolvedTaxRule,
    this.resolvedLot,
    this.resolvedWarehouse,
    this.resolvedCce0,
  });

  String get sku => resolvedSku ?? standaloneSku ?? '';
  String get name => resolvedName ?? standaloneName ?? '';
  String get salesUnit => resolvedSalesUnit ?? standaloneSalesUnit ?? 'EA';
  double get price => resolvedPrice ?? standalonePrice ?? 0.0;
  String get taxRule => resolvedTaxRule ?? standaloneTaxRule ?? '';
  String get lot => resolvedLot ?? standaloneLot ?? '';
  String get warehouse => resolvedWarehouse ?? standaloneWarehouse ?? '';
  String get cce0 => resolvedCce0 ?? standaloneCce0 ?? '';

  Map<String, dynamic> toMap() {
    return {
      if (lineId != null) 'lineId': lineId,
      'creditNoteId': creditNoteId,
      'lineNo': lineNo,
      'quantity': quantity,
      'originInvoiceId': originInvoiceId,
      'originLineNo': originLineNo,
      'standaloneSku': standaloneSku,
      'standaloneName': standaloneName,
      'standaloneSalesUnit': standaloneSalesUnit,
      'standalonePrice': standalonePrice,
      'standaloneTaxRule': standaloneTaxRule,
      'standaloneLot': standaloneLot,
      'standaloneWarehouse': standaloneWarehouse,
      'standaloneCce0': standaloneCce0,
    };
  }

  factory CreditNoteLineModel.fromMap(Map<String, dynamic> map) {
    return CreditNoteLineModel(
      lineId: map['lineId'],
      creditNoteId: map['creditNoteId'] ?? '',
      lineNo: map['lineNo'] ?? 0,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      originInvoiceId: map['originInvoiceId'],
      originLineNo: map['originLineNo'],
      standaloneSku: map['standaloneSku'],
      standaloneName: map['standaloneName'],
      standaloneSalesUnit: map['standaloneSalesUnit'],
      standalonePrice: (map['standalonePrice'] as num?)?.toDouble(),
      standaloneTaxRule: map['standaloneTaxRule'],
      standaloneLot: map['standaloneLot'],
      standaloneWarehouse: map['standaloneWarehouse'],
      standaloneCce0: map['standaloneCce0'],
      resolvedSku: map['sku'],
      resolvedName: map['name'],
      resolvedSalesUnit: map['salesUnit'],
      resolvedPrice: (map['basePrice'] as num?)?.toDouble() ?? (map['price'] as num?)?.toDouble(),
      resolvedTaxRule: map['taxRule'],
      resolvedLot: map['lotNumber'] ?? map['lot'],
      resolvedWarehouse: map['warehouse'],
      resolvedCce0: map['cce0'],
    );
  }
}

class CreditNoteRefundModel {
  final int? refundId;
  final String creditNoteId;
  final String method;
  final double amount;
  final String? bankCode;
  final String? bankName;
  final String? chequeNumber;
  final String? chequeDate;

  CreditNoteRefundModel({
    this.refundId,
    required this.creditNoteId,
    required this.method,
    required this.amount,
    this.bankCode,
    this.bankName,
    this.chequeNumber,
    this.chequeDate,
  });

  Map<String, dynamic> toMap() {
    return {
      if (refundId != null) 'refundId': refundId,
      'creditNoteId': creditNoteId,
      'method': method,
      'amount': amount,
      'bankCode': bankCode,
      'bankName': bankName,
      'chequeNumber': chequeNumber,
      'chequeDate': chequeDate,
    };
  }

  factory CreditNoteRefundModel.fromMap(Map<String, dynamic> map) {
    return CreditNoteRefundModel(
      refundId: map['refundId'],
      creditNoteId: map['creditNoteId'] ?? '',
      method: map['method'] ?? CreditNoteRefundMethod.cash,
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      bankCode: map['bankCode'],
      bankName: map['bankName'],
      chequeNumber: map['chequeNumber'],
      chequeDate: map['chequeDate'],
    );
  }
}
