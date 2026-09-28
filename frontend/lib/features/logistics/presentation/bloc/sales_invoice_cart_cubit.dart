import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/sales_invoice_product_model.dart';

// --- MODELS ---

class CartItem extends Equatable {
  final SalesInvoiceProductModel product;
  final double quantity;
  final String lotNumber;
  final String warehouse;
  final String warehouseName;
  final String location;
  final String locationType;
  final double basePrice;
  final double discountPercent;
  final double vatRatePercent;
  final String taxRule;
  final bool isFoc;
  final String? mainItemSku;
  /// The pricelist code(s) that were matched by the pricing engine for this item.
  final String pricingSource;
  final double discountAmountFlat;
  final String priceListCode;
  final int reasonType;

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
    this.taxRule = '',
    this.isFoc = false,
    this.mainItemSku,
    this.pricingSource = '',
    this.discountAmountFlat = 0.0,
    this.priceListCode = '',
    this.reasonType = 0,
  });

  double get discountAmount => (basePrice * quantity * (discountPercent / 100)) + discountAmountFlat;
  double get priceAfterDiscount => (basePrice * quantity) - discountAmount;
  double get vatAmount => priceAfterDiscount * (vatRatePercent / 100);
  double get total => priceAfterDiscount + vatAmount;

  CartItem copyWith({
    SalesInvoiceProductModel? product,
    double? quantity,
    String? lotNumber,
    String? warehouse,
    String? warehouseName,
    String? location,
    String? locationType,
    double? basePrice,
    double? discountPercent,
    double? vatRatePercent,
    String? taxRule,
    bool? isFoc,
    String? mainItemSku,
    String? pricingSource,
    double? discountAmountFlat,
    String? priceListCode,
    int? reasonType,
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
      taxRule: taxRule ?? this.taxRule,
      isFoc: isFoc ?? this.isFoc,
      mainItemSku: mainItemSku ?? this.mainItemSku,
      pricingSource: pricingSource ?? this.pricingSource,
      discountAmountFlat: discountAmountFlat ?? this.discountAmountFlat,
      priceListCode: priceListCode ?? this.priceListCode,
      reasonType: reasonType ?? this.reasonType,
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
        taxRule,
        isFoc,
        mainItemSku,
        pricingSource,
        discountAmountFlat,
        priceListCode,
        reasonType,
      ];
}

// --- STATE ---

class SalesInvoiceCartState extends Equatable {
  final Map<String, dynamic>? customer;
  final List<CartItem> items;
  final String transactionType;
  final int? sourceSalesOrderId;
  final DateTime? deliveryDate;

  const SalesInvoiceCartState({
    this.customer,
    this.items = const [],
    this.transactionType = 'INVOICE',
    this.sourceSalesOrderId,
    this.deliveryDate,
  });

  double get subtotal => items.fold(0, (sum, item) => sum + (item.basePrice * item.quantity));
  double get totalDiscount => items.fold(0, (sum, item) => sum + item.discountAmount);
  double get totalVat => items.fold(0, (sum, item) => sum + item.vatAmount);
  double get grandTotal => items.fold(0, (sum, item) => sum + item.total);

  SalesInvoiceCartState copyWith({
    Map<String, dynamic>? customer,
    List<CartItem>? items,
    String? transactionType,
    int? sourceSalesOrderId,
    DateTime? deliveryDate,
  }) {
    return SalesInvoiceCartState(
      customer: customer ?? this.customer,
      items: items ?? this.items,
      transactionType: transactionType ?? this.transactionType,
      sourceSalesOrderId: sourceSalesOrderId ?? this.sourceSalesOrderId,
      deliveryDate: deliveryDate ?? this.deliveryDate,
    );
  }

  @override
  List<Object?> get props => [customer, items, transactionType, sourceSalesOrderId, deliveryDate];
}

// --- CUBIT ---

class SalesInvoiceCartCubit extends Cubit<SalesInvoiceCartState> {
  SalesInvoiceCartCubit() : super(const SalesInvoiceCartState());

  void setTransactionType(String type) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    emit(state.copyWith(
      transactionType: type,
      deliveryDate: type == 'SI_SALES_ORDER' ? (state.deliveryDate ?? today) : state.deliveryDate,
    ));
  }

  void setDeliveryDate(DateTime date) {
    emit(state.copyWith(deliveryDate: date));
  }

  void setCustomer(Map<String, dynamic> customer) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    emit(state.copyWith(
      customer: customer,
      items: [],
      deliveryDate: state.transactionType == 'SI_SALES_ORDER' ? (state.deliveryDate ?? today) : state.deliveryDate,
    )); // Clear cart items when changing customer
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
      final itemToRemove = updatedItems[index];
      updatedItems.removeAt(index);
      
      // PHASE 1: FOC auto-remove logic removed for centralization.

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

  void updateItemQuantity(int index, double newQuantity) {
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

  void clearCart({String? transactionType, int? sourceSalesOrderId, DateTime? deliveryDate}) {
    emit(const SalesInvoiceCartState()); // Full reset first
    final type = transactionType ?? 'INVOICE';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final defaultDelivery = type == 'SI_SALES_ORDER' ? (deliveryDate ?? today) : null;
    emit(state.copyWith(
      items: [],
      transactionType: type,
      sourceSalesOrderId: sourceSalesOrderId,
      deliveryDate: defaultDelivery,
    ));
  }
}
