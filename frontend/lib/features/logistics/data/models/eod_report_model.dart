/// Model classes for the End-of-Day (Day-end Closing) report.
library;

class EodReportModel {
  final String reportDate;
  final String reportTime;
  final String operatorName;
  final String registerId;

  // Sales totals
  final int salesCount;
  final double salesGross;
  final double totalVat;
  final double totalDiscount;

  // Returns / Credit Notes
  final int returnsCount;
  final double returnsGross;

  // Cancelled (reversed) receipts
  final List<EodCancelledReceipt> cancelledReceipts;

  // Cash balance
  final EodCashBalance cashBalance;

  // VAT breakdown per tax rate
  final List<EodVatSummary> vatSummaries;

  // Payment method totals
  final List<EodPaymentSummary> paymentSummaries;

  // ── New Granular Breakdown Lists (Industrial EOD) ─────────────────────────
  /// Invoices fully/partially settled immediately (Cash, Cheque, Juice, Card)
  final List<EodInvoiceItem> cashInvoices;

  /// Invoices issued on credit terms (CH30, 30D, unpaid at delivery)
  final List<EodInvoiceItem> creditInvoices;

  /// Debt collections against previous open invoices
  final List<EodOpenInvoiceCollectionItem> openInvoiceCollections;

  /// Itemized list of all cheques collected today (from sales & open invoices)
  final List<EodChequeDetail> chequeList;

  /// Physical cash refunded to customers on returns today
  final double cashRefundedOnReturns;

  // ── Computed Convenience Totals ───────────────────────────────────────────
  double get totalNetSales => salesGross - totalVat;
  double get totalGrossSales => salesGross;
  double get netReturns => returnsGross - (returnsGross > 0 ? (returnsGross * totalVat / (salesGross == 0 ? 1 : salesGross)) : 0);

  double get totalCashInvoicesAmount =>
      cashInvoices.fold(0.0, (sum, i) => sum + i.grandTotal);

  double get totalCreditInvoicesAmount =>
      creditInvoices.fold(0.0, (sum, i) => sum + i.grandTotal);

  double get totalOpenCollectionsAmount =>
      openInvoiceCollections.fold(0.0, (sum, c) => sum + c.amount);

  /// Cash received from today's spot cash sales
  double get physicalCashFromInvoices =>
      cashInvoices.fold(0.0, (sum, i) => sum + i.cashAmount);

  /// Cash received from open invoices debt collections
  double get physicalCashFromCollections => openInvoiceCollections
      .where((c) => c.paymentMethod.toUpperCase() == 'CASH')
      .fold(0.0, (sum, c) => sum + c.amount);

  /// Exact physical cash that must be physically present in the bag / cash box
  double get netPhysicalCashInHand =>
      (physicalCashFromInvoices + physicalCashFromCollections - cashRefundedOnReturns)
          .clamp(0.0, double.infinity);

  /// Total value of all physical cheques collected today
  double get totalChequesAmount =>
      chequeList.fold(0.0, (sum, c) => sum + c.amount);

  /// Digital payments (Juice, Blink, Card, Bank Transfer) from today's invoices
  double get digitalFromSales =>
      cashInvoices.fold(0.0, (sum, i) => sum + i.digitalAmount);

  /// Digital payments from open collections
  double get digitalFromOpenCollections => openInvoiceCollections
      .where((c) => [
            'JUICE',
            'BLINK',
            'MYT MONEY',
            'CARD',
            'BANK_TRANSFER',
            'ONLINE'
          ].contains(c.paymentMethod.toUpperCase()))
      .fold(0.0, (sum, c) => sum + c.amount);

  /// Grand total digital receipts
  double get totalDigitalAmount => digitalFromSales + digitalFromOpenCollections;

  /// Total turnover invoiced today (Cash sales + Credit sales)
  double get grandTotalTurnover => totalCashInvoicesAmount + totalCreditInvoicesAmount;

  /// Grand total money/settlements physically or digitally collected today
  double get grandTotalFundsCollected =>
      netPhysicalCashInHand + totalChequesAmount + totalDigitalAmount;

  const EodReportModel({
    required this.reportDate,
    required this.reportTime,
    required this.operatorName,
    required this.registerId,
    required this.salesCount,
    required this.salesGross,
    required this.totalVat,
    required this.totalDiscount,
    required this.returnsCount,
    required this.returnsGross,
    required this.cancelledReceipts,
    required this.cashBalance,
    required this.vatSummaries,
    required this.paymentSummaries,
    this.cashInvoices = const [],
    this.creditInvoices = const [],
    this.openInvoiceCollections = const [],
    this.chequeList = const [],
    this.cashRefundedOnReturns = 0.0,
  });
}

/// Itemized invoice model for EOD Cash & Credit invoice listings.
class EodInvoiceItem {
  final String invoiceId;
  final String customerCode;
  final String customerName;
  final double grandTotal;
  final String paymentTerm;
  final String tenderSummary;
  final double cashAmount;
  final double chequeAmount;
  final double digitalAmount;
  final double creditAmount;
  final String createdAt;
  final bool isCredit;

  const EodInvoiceItem({
    required this.invoiceId,
    required this.customerCode,
    required this.customerName,
    required this.grandTotal,
    required this.paymentTerm,
    required this.tenderSummary,
    this.cashAmount = 0.0,
    this.chequeAmount = 0.0,
    this.digitalAmount = 0.0,
    this.creditAmount = 0.0,
    required this.createdAt,
    required this.isCredit,
  });
}

/// Itemized model for debt collection against open invoices.
class EodOpenInvoiceCollectionItem {
  final String paymentId;
  final String documentNo;
  final String customerNo;
  final String customerName;
  final double amount;
  final String paymentMethod;
  final String bankCode;
  final String bankName;
  final String chequeNumber;
  final String chequeDate;
  final String qrTransactionRef;
  final String createdAt;
  final bool isSynced;

  const EodOpenInvoiceCollectionItem({
    required this.paymentId,
    required this.documentNo,
    required this.customerNo,
    required this.customerName,
    required this.amount,
    required this.paymentMethod,
    this.bankCode = '',
    this.bankName = '',
    this.chequeNumber = '',
    this.chequeDate = '',
    this.qrTransactionRef = '',
    required this.createdAt,
    this.isSynced = false,
  });
}

/// Itemized cheque detail for cashier deposit slip.
class EodChequeDetail {
  final String chequeNumber;
  final String bankName;
  final String customerName;
  final String source; // 'INVOICE' or 'OPEN_COLLECTION'
  final double amount;
  final String date;

  const EodChequeDetail({
    required this.chequeNumber,
    required this.bankName,
    required this.customerName,
    required this.source,
    required this.amount,
    this.date = '',
  });
}

class EodCancelledReceipt {
  final String invoiceId;
  final String reason; // customer name used as reason
  final double net;
  final double gross;

  const EodCancelledReceipt({
    required this.invoiceId,
    required this.reason,
    required this.net,
    required this.gross,
  });
}

class EodCashBalance {
  final double previousBalance;  // Always 0.00 (not tracked)
  final double cashGrossSales;   // From tbl_si_payments where method='CASH'
  final double deposits;         // Always 0.00 (not tracked)
  final double withdrawals;      // Always 0.00 (not tracked)
  final double changeForNonCash; // Always 0.00 (not tracked)
  final double tip;              // Always 0.00 (not tracked)

  double get expectedBalance =>
      previousBalance + cashGrossSales + deposits - withdrawals + changeForNonCash + tip;

  const EodCashBalance({
    this.previousBalance = 0.0,
    required this.cashGrossSales,
    this.deposits = 0.0,
    this.withdrawals = 0.0,
    this.changeForNonCash = 0.0,
    this.tip = 0.0,
  });
}

class EodVatSummary {
  final String taxCode;
  final double taxRatePercent; // e.g. 15.0
  final double net;
  final double tax;

  double get gross => net + tax;

  const EodVatSummary({
    required this.taxCode,
    required this.taxRatePercent,
    required this.net,
    required this.tax,
  });
}

class EodPaymentSummary {
  final String method;
  final double amount;

  const EodPaymentSummary({
    required this.method,
    required this.amount,
  });
}
