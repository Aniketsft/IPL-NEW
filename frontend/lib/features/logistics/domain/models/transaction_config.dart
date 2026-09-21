import 'package:flutter/material.dart';

enum TransactionTypeCategory {
  invoice,
  previewInvoice,
  creditNote,
  customerReturn,
  salesOrder,
  previewCreditNote,
}

class TransactionConfig {
  final String transactionType;
  final TransactionTypeCategory category;
  final String screenTitle;
  final String abbreviation; // 'INV', 'CN', 'RTN', 'SO'
  final Color badgeColor;
  final String confirmButtonText;
  final IconData confirmIcon;

  // Business logic & validation flags
  final bool enforceOriginalQtyLimit; // Limit against original purchase qty
  final bool allowNegativePricing;
  final bool canRemoveItems; // False for confirmed invoices
  final bool allowCatalogProductAddition; // True for new draft invoices
  final bool showReprintButton; // True for confirmed invoices
  final bool requireItemSelectionForAction; // True: action button hidden until >= 1 item selected
  final bool isReturnOrCreditNote;

  const TransactionConfig({
    required this.transactionType,
    required this.category,
    required this.screenTitle,
    required this.abbreviation,
    required this.badgeColor,
    required this.confirmButtonText,
    required this.confirmIcon,
    this.enforceOriginalQtyLimit = false,
    this.allowNegativePricing = false,
    this.canRemoveItems = true,
    this.allowCatalogProductAddition = true,
    this.showReprintButton = false,
    this.requireItemSelectionForAction = false,
    this.isReturnOrCreditNote = false,
  });

  static TransactionConfig forType(String type) {
    switch (type) {
      case 'PREVIEW_INVOICE':
        return const TransactionConfig(
          transactionType: 'PREVIEW_INVOICE',
          category: TransactionTypeCategory.previewInvoice,
          screenTitle: 'Order Summary',
          abbreviation: 'INV',
          badgeColor: Color(0xFF4CAF50), // Green
          confirmButtonText: 'Reverse Invoice',
          confirmIcon: Icons.assignment_return,
          enforceOriginalQtyLimit: true,
          canRemoveItems: false, // Confirmed invoice: cannot remove items!
          allowCatalogProductAddition: false,
          showReprintButton: true,
          requireItemSelectionForAction: true, // Hidden until item selected
          isReturnOrCreditNote: true,
        );
      case 'CUSTOMER_RETURN':
      case 'RETURN':
        return const TransactionConfig(
          transactionType: 'CUSTOMER_RETURN',
          category: TransactionTypeCategory.customerReturn,
          screenTitle: 'Order Summary',
          abbreviation: 'RTN',
          badgeColor: Color(0xFFE53935), // Red
          confirmButtonText: 'Process Return',
          confirmIcon: Icons.assignment_return,
          enforceOriginalQtyLimit: true,
          canRemoveItems: true,
          isReturnOrCreditNote: true,
        );
      case 'CREDIT_NOTE':
      case 'STANDALONE_CREDIT_NOTE':
        return const TransactionConfig(
          transactionType: 'CREDIT_NOTE',
          category: TransactionTypeCategory.creditNote,
          screenTitle: 'Order Summary',
          abbreviation: 'CN',
          badgeColor: Color(0xFFFFA000), // Amber / Orange
          confirmButtonText: 'Confirm Reversal',
          confirmIcon: Icons.assignment_return,
          enforceOriginalQtyLimit: true,
          canRemoveItems: true,
          isReturnOrCreditNote: true,
        );
      case 'PREVIEW_CREDIT_NOTE':
        return const TransactionConfig(
          transactionType: 'PREVIEW_CREDIT_NOTE',
          category: TransactionTypeCategory.previewCreditNote,
          screenTitle: 'Order Summary',
          abbreviation: 'CN',
          badgeColor: Color(0xFFFFA000),
          confirmButtonText: 'View Payment & Print',
          confirmIcon: Icons.receipt_long,
          enforceOriginalQtyLimit: true,
          canRemoveItems: false,
          allowCatalogProductAddition: false,
          showReprintButton: true,
          isReturnOrCreditNote: true,
        );
      case 'SI_SALES_ORDER':
        return const TransactionConfig(
          transactionType: 'SI_SALES_ORDER',
          category: TransactionTypeCategory.salesOrder,
          screenTitle: 'Order Summary',
          abbreviation: 'SO',
          badgeColor: Color(0xFF1976D2), // Blue
          confirmButtonText: 'Save Sales Order',
          confirmIcon: Icons.save,
          canRemoveItems: true,
        );
      case 'VIEW_SI_SALES_ORDER':
        return const TransactionConfig(
          transactionType: 'VIEW_SI_SALES_ORDER',
          category: TransactionTypeCategory.salesOrder,
          screenTitle: 'Order Summary',
          abbreviation: 'SO',
          badgeColor: Color(0xFF1976D2),
          confirmButtonText: 'Convert to Invoice',
          confirmIcon: Icons.transform,
          canRemoveItems: false,
          allowCatalogProductAddition: false,
        );
      case 'INVOICE':
      default:
        return const TransactionConfig(
          transactionType: 'INVOICE',
          category: TransactionTypeCategory.invoice,
          screenTitle: 'Order Summary',
          abbreviation: 'INV',
          badgeColor: Color(0xFF4CAF50), // Green
          confirmButtonText: 'Proceed to Payment',
          confirmIcon: Icons.check_circle,
          canRemoveItems: true,
          allowCatalogProductAddition: true,
        );
    }
  }
}
