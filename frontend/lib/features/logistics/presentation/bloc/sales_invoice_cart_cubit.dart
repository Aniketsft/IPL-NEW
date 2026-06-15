import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/sales_invoice_product_model.dart';

// --- MODELS ---

class CartItem extends Equatable {
  final SalesInvoiceProductModel product;
  final int quantity;
  final String lotNumber;
  final String warehouse;
  final String warehouseName;
  final String location;
  final String locationType;
  final double basePrice;
  final double discountPercent;
  final double vatRatePercent;

  const CartItem({
    required this.product,
    required this.quantity,
    this.lotNumber = '',
    this.warehouse = '',
    this.warehouseName = '',
    this.location = '',
    this.locationType = '',
    required this.basePrice,
    this.discountPercent = 0.0,
    this.vatRatePercent = 0.0,
  });

  double get discountAmount => basePrice * quantity * (discountPercent / 100);
  double get priceAfterDiscount => (basePrice * quantity) - discountAmount;
  double get vatAmount => priceAfterDiscount * (vatRatePercent / 100);
  double get total => priceAfterDiscount + vatAmount;

  CartItem copyWith({
    SalesInvoiceProductModel? product,
    int? quantity,
    String? lotNumber,
    String? warehouse,
    String? warehouseName,
    String? location,
    String? locationType,
    double? basePrice,
    double? discountPercent,
    double? vatRatePercent,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      lotNumber: lotNumber ?? this.lotNumber,
      warehouse: warehouse ?? this.warehouse,
      warehouseName: warehouseName ?? this.warehouseName,
      location: location ?? this.location,
      locationType: locationType ?? this.locationType,
      basePrice: basePrice ?? this.basePrice,
      discountPercent: discountPercent ?? this.discountPercent,
      vatRatePercent: vatRatePercent ?? this.vatRatePercent,
    );
  }

  @override
  List<Object?> get props => [
        product,
        quantity,
        lotNumber,
        warehouse,
        warehouseName,
        location,
        locationType,
        basePrice,
        discountPercent,
        vatRatePercent,
      ];
}

// --- STATE ---

class SalesInvoiceCartState extends Equatable {
  final Map<String, dynamic>? customer;
  final List<CartItem> items;

  const SalesInvoiceCartState({
    this.customer,
    this.items = const [],
  });

  double get subtotal => items.fold(0, (sum, item) => sum + (item.basePrice * item.quantity));
  double get totalDiscount => items.fold(0, (sum, item) => sum + item.discountAmount);
  double get totalVat => items.fold(0, (sum, item) => sum + item.vatAmount);
  double get grandTotal => items.fold(0, (sum, item) => sum + item.total);

  SalesInvoiceCartState copyWith({
    Map<String, dynamic>? customer,
    List<CartItem>? items,
  }) {
    return SalesInvoiceCartState(
      customer: customer ?? this.customer,
      items: items ?? this.items,
    );
  }

  @override
  List<Object?> get props => [customer, items];
}

// --- CUBIT ---

class SalesInvoiceCartCubit extends Cubit<SalesInvoiceCartState> {
  SalesInvoiceCartCubit() : super(const SalesInvoiceCartState());

  void setCustomer(Map<String, dynamic> customer) {
    emit(state.copyWith(customer: customer, items: [])); // Clear cart when changing customer
  }

  void addItem(CartItem item) {
    final updatedItems = List<CartItem>.from(state.items);
    // For now, allow multiple entries of same item if they have different lot/discount. 
    // Otherwise, just append it.
    updatedItems.add(item);
    emit(state.copyWith(items: updatedItems));
  }

  void removeItem(int index) {
    final updatedItems = List<CartItem>.from(state.items);
    if (index >= 0 && index < updatedItems.length) {
      updatedItems.removeAt(index);
      emit(state.copyWith(items: updatedItems));
    }
  }

  void updateItem(int index, CartItem newItem) {
    if (newItem.quantity <= 0) {
      removeItem(index);
      return;
    }
    final updatedItems = List<CartItem>.from(state.items);
    if (index >= 0 && index < updatedItems.length) {
      updatedItems[index] = newItem;
      emit(state.copyWith(items: updatedItems));
    }
  }

  void updateItemQuantity(int index, int newQuantity) {
    if (newQuantity <= 0) {
      removeItem(index);
      return;
    }
    final updatedItems = List<CartItem>.from(state.items);
    if (index >= 0 && index < updatedItems.length) {
      updatedItems[index] = updatedItems[index].copyWith(quantity: newQuantity);
      emit(state.copyWith(items: updatedItems));
    }
  }

  void clearCart() {
    emit(state.copyWith(items: []));
  }
}
