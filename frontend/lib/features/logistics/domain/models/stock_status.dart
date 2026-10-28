/// Global Stock Status Parameter (Sage X3 STOCK.STA_0 mapping)
/// - A: Approved / Prime Sellable Stock (Strictly available for sales invoices)
/// - Q: Quarantine / Returned Goods (Customer returns awaiting quality check/inspection)
/// - R: Rejected / Issue in Stock (Damaged, expired, or defective goods)
enum StockStatus {
  approved('A', 'Approved / Sellable', 'Prime sellable inventory'),
  quarantine('Q', 'Returned (Quarantine)', 'Customer returns under inspection'),
  rejected('R', 'Issue in Stock', 'Damaged or defective inventory');

  final String code;
  final String label;
  final String description;

  const StockStatus(this.code, this.label, this.description);

  static StockStatus fromCode(String? code) {
    if (code == null || code.trim().isEmpty) return StockStatus.approved;
    final normalized = code.trim().toUpperCase();
    for (final status in StockStatus.values) {
      if (status.code == normalized) return status;
    }
    return StockStatus.approved;
  }

  bool get isSellable => this == StockStatus.approved;

  static const String codeApproved = 'A';
  static const String codeQuarantine = 'Q';
  static const String codeRejected = 'R';
}
