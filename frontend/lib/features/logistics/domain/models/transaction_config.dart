import 'package:flutter/material.dart';

/// Global Transaction Workflow Mode with explicit integer flags:
/// 1: INVOICE (Sales Invoice creation)
/// 2: DIRECT_CREDIT_NOTE (Standalone / Open Credit Note, not tied to an invoice)
/// 3: LINKED_CREDIT_NOTE (Reversal / Credit Note tied to a specific origin invoice ID)
/// 4: RETURN (Customer Goods Return)
/// 5: PAYMENT (Direct Payment / Settlement)
/// 6: PREVIEW_INVOICE (Viewing confirmed invoice from History)
/// 7: PREVIEW_CREDIT_NOTE (Viewing confirmed credit note from History)
/// 8: SALES_ORDER (Sales Order)
enum AppTransactionMode {
  invoice(1, 'INV', 'Invoice'),
  directCreditNote(2, 'DIRECT_CN', 'Direct Credit Note'),
  linkedCreditNote(3, 'LINKED_CN', 'Linked Credit Note'),
  customerReturn(4, 'RETURN', 'Customer Return'),
  payment(5, 'PAYMENT', 'Payment Settlement'),
  previewInvoice(6, 'PREVIEW_INV', 'Preview Invoice'),
  previewCreditNote(7, 'PREVIEW_CN', 'Preview Credit Note'),
  salesOrder(8, 'SO', 'Sales Order');

  final int flag;
  final String code;
  final String displayName;
  const AppTransactionMode(this.flag, this.code, this.displayName);

  bool get isCreditNote =>
      this == directCreditNote ||
      this == linkedCreditNote ||
      this == previewCreditNote;

  bool get isInvoice =>
      this == invoice ||
      this == previewInvoice;

  bool get isLinkedToInvoice =>
      this == linkedCreditNote;

  /// Sage X3 SOAP ZSCRWEB Header Position 17 flag:
  /// "1" for Direct Credit Note (no origin invoice)
  /// "4" for Linked Credit Note (linked to specific origin invoice in Position 16)
  String get x3SoapTransactionMode => isLinkedToInvoice ? '4' : '1';
}

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
  final AppTransactionMode mode;
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
    this.mode = AppTransactionMode.invoice,
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

  bool get isInvoiceMode => mode.isInvoice;
  bool get isCreditNoteMode => mode.isCreditNote;
  bool get isLinkedReversal => mode.isLinkedToInvoice;

  static TransactionConfig forType(String type) {
    switch (type) {
      case 'PREVIEW_INVOICE':
        return const TransactionConfig(
          transactionType: 'PREVIEW_INVOICE',
          category: TransactionTypeCategory.previewInvoice,
          mode: AppTransactionMode.previewInvoice,
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
          isReturnOrCreditNote: false, // Invoice preview is NOT a credit note
        );
      case 'CUSTOMER_RETURN':
      case 'RETURN':
        return const TransactionConfig(
          transactionType: 'CUSTOMER_RETURN',
          category: TransactionTypeCategory.customerReturn,
          mode: AppTransactionMode.customerReturn,
          screenTitle: 'Order Summary',
          abbreviation: 'RTN',
          badgeColor: Color(0xFFE53935), // Red
          confirmButtonText: 'Process Return',
          confirmIcon: Icons.assignment_return,
          enforceOriginalQtyLimit: true,
          canRemoveItems: true,
          allowCatalogProductAddition: false,
          isReturnOrCreditNote: true,
        );
      case 'CREDIT_NOTE':
        return const TransactionConfig(
          transactionType: 'CREDIT_NOTE',
          category: TransactionTypeCategory.creditNote,
          mode: AppTransactionMode.linkedCreditNote,
          screenTitle: 'Order Summary',
          abbreviation: 'CN',
          badgeColor: Color(0xFFFFA000), // Amber / Orange
          confirmButtonText: 'Confirm Reversal',
          confirmIcon: Icons.assignment_return,
          enforceOriginalQtyLimit: true,
          canRemoveItems: true,
          allowCatalogProductAddition: false,
          isReturnOrCreditNote: true,
        );
      case 'STANDALONE_CREDIT_NOTE':
        return const TransactionConfig(
          transactionType: 'STANDALONE_CREDIT_NOTE',
          category: TransactionTypeCategory.creditNote,
          mode: AppTransactionMode.directCreditNote,
          screenTitle: 'Order Summary',
          abbreviation: 'CN',
          badgeColor: Color(0xFFFFA000), // Amber / Orange
          confirmButtonText: 'Confirm Credit Note',
          confirmIcon: Icons.assignment_return,
          enforceOriginalQtyLimit: false,
          canRemoveItems: true,
          allowCatalogProductAddition: true,
          isReturnOrCreditNote: true,
        );
      case 'PREVIEW_CREDIT_NOTE':
        return const TransactionConfig(
          transactionType: 'PREVIEW_CREDIT_NOTE',
          category: TransactionTypeCategory.previewCreditNote,
          mode: AppTransactionMode.previewCreditNote,
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
          mode: AppTransactionMode.salesOrder,
          screenTitle: 'Order Summary',
          abbreviation: 'SO',
          badgeColor: Color(0xFF1976D2), // Blue
          confirmButtonText: 'Save Sales Order',
          confirmIcon: Icons.save,
          canRemoveItems: true,
          isReturnOrCreditNote: false,
        );
      case 'VIEW_SI_SALES_ORDER':
        return const TransactionConfig(
          transactionType: 'VIEW_SI_SALES_ORDER',
          category: TransactionTypeCategory.salesOrder,
          mode: AppTransactionMode.salesOrder,
          screenTitle: 'Order Summary',
          abbreviation: 'SO',
          badgeColor: Color(0xFF1976D2),
          confirmButtonText: 'Convert to Invoice',
          confirmIcon: Icons.transform,
          canRemoveItems: false,
          allowCatalogProductAddition: false,
          isReturnOrCreditNote: false,
        );
      case 'INVOICE':
      default:
        return const TransactionConfig(
          transactionType: 'INVOICE',
          category: TransactionTypeCategory.invoice,
          mode: AppTransactionMode.invoice,
          screenTitle: 'Order Summary',
          abbreviation: 'INV',
          badgeColor: Color(0xFF4CAF50), // Green
          confirmButtonText: 'Proceed to Payment',
          confirmIcon: Icons.check_circle,
          canRemoveItems: true,
          allowCatalogProductAddition: true,
          isReturnOrCreditNote: false,
        );
    }
  }
}
