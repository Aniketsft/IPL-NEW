import 'package:equatable/equatable.dart';
import 'sales_invoice_cart_cubit.dart'; // To reuse CartItem
import '../../domain/models/transaction_config.dart';

abstract class SalesInvoiceEvent extends Equatable {
  const SalesInvoiceEvent();

  @override
  List<Object?> get props => [];
}

class InitializeTransaction extends SalesInvoiceEvent {
  final String transactionType;
  final String? originalDocumentId;
  final TransactionConfig? config;

  const InitializeTransaction({
    required this.transactionType,
    this.originalDocumentId,
    this.config,
  });

  @override
  List<Object?> get props => [transactionType, originalDocumentId, config];
}

class PrepareReversalCreditNote extends SalesInvoiceEvent {
  final List<CartItem> items;
  final String originalInvoiceId;

  const PrepareReversalCreditNote({
    required this.items,
    required this.originalInvoiceId,
  });

  @override
  List<Object?> get props => [items, originalInvoiceId];
}

class SetCustomer extends SalesInvoiceEvent {
  final Map<String, dynamic> customer;
  const SetCustomer(this.customer);

  @override
  List<Object?> get props => [customer];
}

class AddCartItem extends SalesInvoiceEvent {
  final CartItem item;
  const AddCartItem(this.item);

  @override
  List<Object?> get props => [item];
}

class RemoveCartItem extends SalesInvoiceEvent {
  final int index;
  const RemoveCartItem(this.index);

  @override
  List<Object?> get props => [index];
}

class UpdateCartItem extends SalesInvoiceEvent {
  final int index;
  final CartItem item;
  const UpdateCartItem(this.index, this.item);

  @override
  List<Object?> get props => [index, item];
}

class SetDeliveryDate extends SalesInvoiceEvent {
  final DateTime date;
  const SetDeliveryDate(this.date);

  @override
  List<Object?> get props => [date];
}

class ConvertToCreditNote extends SalesInvoiceEvent {}

class ClearCart extends SalesInvoiceEvent {}

class SubmitTransaction extends SalesInvoiceEvent {
  final String paymentMode; // Cash, Credit, etc.
  final String? deliveryDate; // For Sales Orders

  const SubmitTransaction({required this.paymentMode, this.deliveryDate});

  @override
  List<Object?> get props => [paymentMode, deliveryDate];
}

class RestoreOriginalInvoice extends SalesInvoiceEvent {
  final List<CartItem> cartItems;
  final String transactionType;
  final TransactionConfig config;
  final String? originalDocumentId;

  const RestoreOriginalInvoice({
    required this.cartItems,
    required this.transactionType,
    required this.config,
    this.originalDocumentId,
  });

  @override
  List<Object?> get props => [cartItems, transactionType, config, originalDocumentId];
}
