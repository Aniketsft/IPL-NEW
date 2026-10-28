import 'package:intl/intl.dart';

/// Centralized Currency and Number Formatting Utility for Enterprise Mobile Sales.
/// Enforces standard currency prefix 'Rs', thousands & millions comma separation,
/// and strict 2 decimal places precision across all UI screens and PDF reports.
class CurrencyFormatter {
  CurrencyFormatter._();

  static const String currencySymbol = 'Rs';

  static final NumberFormat _numberFormat = NumberFormat('#,##0.00', 'en_US');

  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'Rs ',
    decimalDigits: 2,
  );

  /// Returns numeric amount formatted with commas and 2 decimals.
  /// Example: 1234567.8 -> "1,234,567.80"
  static String formatNumber(num? value) {
    if (value == null) return '0.00';
    return _numberFormat.format(value);
  }

  /// Returns standard formatted currency amount: e.g. "Rs 1,234,567.80".
  /// If negative: "-Rs 1,234.50".
  /// If [explicitSign] is true and positive: "+Rs 1,234.50".
  static String format(num? value, {bool explicitSign = false}) {
    if (value == null) return 'Rs 0.00';
    final val = value.toDouble();
    if (val < -0.0001) {
      return '-Rs ${_numberFormat.format(val.abs())}';
    } else if (val > 0.0001 && explicitSign) {
      return '+Rs ${_numberFormat.format(val)}';
    }
    return 'Rs ${_numberFormat.format(val)}';
  }

  /// Returns standard discount or credit deduction formatting: e.g. "-Rs 250.00".
  static String formatDiscount(num? value) {
    if (value == null || value == 0) return 'Rs 0.00';
    final val = value.toDouble().abs();
    return '-Rs ${_numberFormat.format(val)}';
  }

  static NumberFormat get numberFormat => _numberFormat;
  static NumberFormat get currencyFormat => _currencyFormat;
}
