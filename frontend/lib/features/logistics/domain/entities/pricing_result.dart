class PricingResult {
  final double basePrice;
  final double discountPct;
  final double discountAmt;
  final String source; // which pricelist matched
  final bool hasFoc;
  final String focItemSku;
  final double focQuantity;

  const PricingResult({
    required this.basePrice,
    required this.discountPct,
    required this.discountAmt,
    required this.source,
    this.hasFoc = false,
    this.focItemSku = '',
    this.focQuantity = 0.0,
  });

  factory PricingResult.empty() => const PricingResult(
        basePrice: 0.0,
        discountPct: 0.0,
        discountAmt: 0.0,
        source: 'MANUAL',
      );
}
