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
  final String stockStatus;

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
    this.stockStatus = 'A',
  });

  double get discountAmount => double.parse(((basePrice * quantity * (discountPercent / 100)) + discountAmountFlat).toStringAsFixed(2));
  double get priceAfterDiscount => double.parse(((basePrice * quantity) - discountAmount).toStringAsFixed(2));
  double get vatAmount => double.parse((priceAfterDiscount * (vatRatePercent / 100)).toStringAsFixed(2));
  double get total => double.parse((priceAfterDiscount + vatAmount).toStringAsFixed(2));

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
    String? stockStatus,
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
      stockStatus: stockStatus ?? this.stockStatus,
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
        stockStatus,
      ];
}

/// Consolidated product projection across multiple lots for Order Summary,
/// PDF Preview, and Thermal Print while keeping underlying per-lot [CartItem]s intact.
class ConsolidatedCartGroup {
  final CartItem displayItem;
  final List<int> sourceIndices;
  final double totalDiscountAmount;
  final double totalVatAmount;
  final double totalAmount;

  const ConsolidatedCartGroup({
    required this.displayItem,
    required this.sourceIndices,
    required this.totalDiscountAmount,
    required this.totalVatAmount,
    required this.totalAmount,
  });

  int get primaryIndex => sourceIndices.first;
  bool get hasMultipleLots => sourceIndices.length > 1;
}

/// Consolidates multiple lot lines belonging to the same product into one
/// display/print row without modifying raw per-lot cart items.
List<ConsolidatedCartGroup> consolidateCartItemsForDisplay(List<CartItem> items) {
  if (items.isEmpty) return const [];

  final Map<String, List<({int index, CartItem item})>> buckets = {};
  final List<String> order = [];

  for (int i = 0; i < items.length; i++) {
    final item = items[i];
    final key = [
      item.product.sku.trim().toUpperCase(),
      item.isFoc ? '1' : '0',
      item.basePrice.toStringAsFixed(4),
      item.taxRule.trim().toUpperCase(),
      item.stockStatus.trim().toUpperCase(),
      (item.mainItemSku ?? '').trim().toUpperCase(),
    ].join('|');

    final list = buckets[key];
    if (list == null) {
      order.add(key);
      buckets[key] = [(index: i, item: item)];
    } else {
      list.add((index: i, item: item));
    }
  }

  return order.map((key) {
    final entries = buckets[key]!;
    final first = entries.first.item;
    final indices = entries.map((e) => e.index).toList();

    final sumQty = entries.fold<double>(0.0, (s, e) => s + e.item.quantity);
    final sumDisc = double.parse(
      entries.fold<double>(0.0, (s, e) => s + e.item.discountAmount).toStringAsFixed(2),
    );
    final sumVat = double.parse(
      entries.fold<double>(0.0, (s, e) => s + e.item.vatAmount).toStringAsFixed(2),
    );
    final sumTotal = double.parse(
      entries.fold<double>(0.0, (s, e) => s + e.item.total).toStringAsFixed(2),
    );
    final sumFlatDisc = double.parse(
      entries.fold<double>(0.0, (s, e) => s + e.item.discountAmountFlat).toStringAsFixed(2),
    );
    final gross = first.basePrice * sumQty;
    final double effectivePct;
    final double effectiveFlat;
    if (entries.every(
      (e) => (e.item.discountPercent - first.discountPercent).abs() < 0.0001,
    )) {
      effectivePct = first.discountPercent;
      effectiveFlat = sumFlatDisc;
    } else if (gross > 0.0001 && sumFlatDisc <= 0.0001) {
      effectivePct = (sumDisc / gross) * 100.0;
      effectiveFlat = 0.0;
    } else {
      effectivePct = 0.0;
      effectiveFlat = sumDisc;
    }

    final display = first.copyWith(
      quantity: sumQty,
      lotNumber: '',
      discountPercent: effectivePct,
      discountAmountFlat: effectiveFlat,
    );

    return ConsolidatedCartGroup(
      displayItem: display,
      sourceIndices: indices,
      totalDiscountAmount: sumDisc,
      totalVatAmount: sumVat,
      totalAmount: sumTotal,
    );
  }).toList();
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

  double get subtotal => double.parse(items.fold<double>(0.0, (sum, item) => sum + (item.basePrice * item.quantity)).toStringAsFixed(2));
  double get totalDiscount => double.parse(items.fold<double>(0.0, (sum, item) => sum + item.discountAmount).toStringAsFixed(2));
  double get totalVat => double.parse(items.fold<double>(0.0, (sum, item) => sum + item.vatAmount).toStringAsFixed(2));
  double get grandTotal => double.parse(items.fold<double>(0.0, (sum, item) => sum + item.total).toStringAsFixed(2));

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
    if (!item.isFoc && (item.basePrice <= 0 || item.total <= 0)) {
      return; // Defensive guard: block adding zero-amount items
    }
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

      // FOC items cannot be deleted directly - only via the parent product
      if (itemToRemove.isFoc) {
        return;
      }

      updatedItems.removeAt(index);
      
      // Cascade remove any linked FOC promotion lines
      updatedItems.removeWhere((item) => item.isFoc && item.mainItemSku == itemToRemove.product.sku);

      emit(state.copyWith(items: updatedItems));
    }
  }

  void removeLinkedFocItem(String mainItemSku) {
    final updatedItems = List<CartItem>.from(state.items)
      ..removeWhere((item) => item.isFoc && item.mainItemSku == mainItemSku);
    emit(state.copyWith(items: updatedItems));
  }

  void updateItem(int index, CartItem newItem) {
    if (newItem.quantity <= 0) {
      removeItem(index);
      return;
    }
    if (!newItem.isFoc && (newItem.basePrice <= 0 || newItem.total <= 0)) {
      return; // Defensive guard: block updating item to zero amount
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
