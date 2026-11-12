class SiteContext {
  /// The operational/physical lorry or warehouse shipping site (e.g. "SCG", "SCP", "SDA", "SFF").
  /// Used for: Physical stock details, truck inventory, and delivery routes.
  final String shippingSiteCode;

  /// The accounting/financial facility (e.g. "CGD", "POD", "DPD", "FFD", "IPL").
  /// Used for: Open invoices, debt history, VAT/tax, banks, and customer balances.
  final String financialSiteCode;

  /// The raw user-assigned or requested site code.
  final String rawSiteCode;

  /// Whether the user has global/multi-site access.
  final bool isMultiSiteAdmin;

  /// Legal company code (default: "INL").
  final String legalCompany;

  const SiteContext({
    required this.shippingSiteCode,
    required this.financialSiteCode,
    required this.rawSiteCode,
    this.isMultiSiteAdmin = false,
    this.legalCompany = 'INL',
  });

  @override
  String toString() =>
      'SiteContext(raw: $rawSiteCode, shipping: $shippingSiteCode, financial: $financialSiteCode, admin: $isMultiSiteAdmin)';
}

