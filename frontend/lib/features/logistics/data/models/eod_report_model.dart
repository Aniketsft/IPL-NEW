/// Model classes for the End-of-Day (Day-end Closing) report.

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

  // Computed convenience fields
  double get totalNetSales => salesGross - totalVat;
  double get totalGrossSales => salesGross;
  double get netReturns => returnsGross - (returnsGross > 0 ? (returnsGross * totalVat / (salesGross == 0 ? 1 : salesGross)) : 0);

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
