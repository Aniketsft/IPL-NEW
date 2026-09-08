class PricingResult {
  final double basePrice;
  final double discountPct;
  final double discountAmt;
  final double discountAmountFlat;
  final String source; // which pricelist matched
  final String priceListCode;
  final int reasonType;
  final bool hasFoc;
  final String focItemSku;
  final double focQuantity;

  const PricingResult({
    required this.basePrice,
    required this.discountPct,
    required this.discountAmt,
    this.discountAmountFlat = 0.0,
    required this.source,
    this.priceListCode = '',
    this.reasonType = 0,
    this.hasFoc = false,
    this.focItemSku = '',
    this.focQuantity = 0.0,
  });

  factory PricingResult.empty() => const PricingResult(
        basePrice: 0.0,
        discountPct: 0.0,
        discountAmt: 0.0,
        discountAmountFlat: 0.0,
        source: 'MANUAL',
        priceListCode: '',
        reasonType: 0,
      );
}
