import 'package:equatable/equatable.dart';
import 'sales_invoice_cart_cubit.dart'; // To reuse CartItem
import '../../domain/models/transaction_config.dart';

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
  final TransactionConfig config;

  SalesInvoiceLoaded({
    this.customer,
    this.cartItems = const [],
    this.transactionType = 'INVOICE',
    this.originalDocumentId,
    this.deliveryDate,
    TransactionConfig? config,
  }) : config = config ?? TransactionConfig.forType(transactionType);

  SalesInvoiceLoaded copyWith({
    Map<String, dynamic>? customer,
    List<CartItem>? cartItems,
    String? transactionType,
    String? originalDocumentId,
    DateTime? deliveryDate,
    TransactionConfig? config,
  }) {
    final newType = transactionType ?? this.transactionType;
    return SalesInvoiceLoaded(
      customer: customer ?? this.customer,
      cartItems: cartItems ?? this.cartItems,
      transactionType: newType,
      originalDocumentId: originalDocumentId ?? this.originalDocumentId,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      config: config ?? (transactionType != null ? TransactionConfig.forType(newType) : this.config),
    );
  }

  double get subtotal => cartItems.fold(0, (sum, item) => sum + (item.basePrice * item.quantity));
  double get totalDiscount => cartItems.fold(0, (sum, item) => sum + item.discountAmount);
  double get totalVat => cartItems.fold(0, (sum, item) => sum + item.vatAmount);
  double get grandTotal => cartItems.fold(0, (sum, item) => sum + item.total);
  double get totalAmount => grandTotal;

  @override
  List<Object?> get props => [customer, cartItems, transactionType, originalDocumentId, deliveryDate, config];
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
