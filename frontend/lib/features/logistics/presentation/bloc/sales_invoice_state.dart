import 'package:equatable/equatable.dart';
import 'sales_invoice_cart_cubit.dart'; // To reuse CartItem

abstract class SalesInvoiceState extends Equatable {
  const SalesInvoiceState();

  @override
  List<Object?> get props => [];
}

class SalesInvoiceInitial extends SalesInvoiceState {}

class SalesInvoiceLoading extends SalesInvoiceState {}

class SalesInvoiceLoaded extends SalesInvoiceState {
  final Map<String, dynamic>? customer;
  final List<CartItem> cartItems;
  final String transactionType; // 'INVOICE', 'SALES_ORDER', 'CREDIT_NOTE', etc.
  final String? originalDocumentId; // Used when reversing or loading from existing
  final DateTime? deliveryDate;

  const SalesInvoiceLoaded({
    this.customer,
    this.cartItems = const [],
    this.transactionType = 'INVOICE',
    this.originalDocumentId,
    this.deliveryDate,
  });

  SalesInvoiceLoaded copyWith({
    Map<String, dynamic>? customer,
    List<CartItem>? cartItems,
    String? transactionType,
    String? originalDocumentId,
    DateTime? deliveryDate,
  }) {
    return SalesInvoiceLoaded(
      customer: customer ?? this.customer,
      cartItems: cartItems ?? this.cartItems,
      transactionType: transactionType ?? this.transactionType,
      originalDocumentId: originalDocumentId ?? this.originalDocumentId,
      deliveryDate: deliveryDate ?? this.deliveryDate,
    );
  }

  double get subtotal => cartItems.fold(0, (sum, item) => sum + (item.basePrice * item.quantity));
  double get totalDiscount => cartItems.fold(0, (sum, item) => sum + item.discountAmount);
  double get totalVat => cartItems.fold(0, (sum, item) => sum + item.vatAmount);
  double get grandTotal => cartItems.fold(0, (sum, item) => sum + item.total);
  double get totalAmount => grandTotal;

  @override
  List<Object?> get props => [customer, cartItems, transactionType, originalDocumentId, deliveryDate];
}

class SalesInvoiceError extends SalesInvoiceState {
  final String message;
  const SalesInvoiceError(this.message);

  @override
  List<Object?> get props => [message];
}

class SalesInvoiceSuccess extends SalesInvoiceState {
  final String message;
  const SalesInvoiceSuccess(this.message);

  @override
  List<Object?> get props => [message];
}
