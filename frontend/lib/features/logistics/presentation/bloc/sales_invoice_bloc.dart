import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repositories/i_sales_repository.dart';
import '../../domain/models/stock_status.dart';
import '../../domain/models/transaction_config.dart';
import 'sales_invoice_event.dart';
import 'sales_invoice_state.dart';
import 'sales_invoice_cart_cubit.dart';

class SalesInvoiceBloc extends Bloc<SalesInvoiceEvent, SalesInvoiceState> {
  final ISalesRepository repository;

  SalesInvoiceBloc({required this.repository}) : super(SalesInvoiceInitial()) {
    on<InitializeTransaction>(_onInitializeTransaction);
    on<PrepareReversalCreditNote>(_onPrepareReversalCreditNote);
    on<RestoreOriginalInvoice>(_onRestoreOriginalInvoice);
    on<SetCustomer>(_onSetCustomer);
    on<AddCartItem>(_onAddCartItem);
    on<RemoveCartItem>(_onRemoveCartItem);
    on<RemoveLinkedFocItem>(_onRemoveLinkedFocItem);
    on<UpdateCartItem>(_onUpdateCartItem);
    on<UpsertProductLotCartItems>(_onUpsertProductLotCartItems);
    on<SetDeliveryDate>(_onSetDeliveryDate);
    on<ConvertToCreditNote>(_onConvertToCreditNote);
    on<ClearCart>(_onClearCart);
    on<SubmitTransaction>(_onSubmitTransaction);
  }

  void _onConvertToCreditNote(ConvertToCreditNote event, Emitter<SalesInvoiceState> emit) {
    final currentState = state;
    if (currentState is SalesInvoiceLoaded) {
      if (currentState.transactionType == 'PREVIEW_INVOICE') {
        emit(currentState.copyWith(transactionType: 'CREDIT_NOTE'));
      }
    }
  }

  void _onPrepareReversalCreditNote(PrepareReversalCreditNote event, Emitter<SalesInvoiceState> emit) {
    final currentState = state;
    if (currentState is SalesInvoiceLoaded) {
      final isReturn = event.isReturn || event.category == 3;
      final txType = isReturn ? 'RETURN' : 'CREDIT_NOTE';
      final resolvedCondition = isReturn
          ? (event.returnCondition ?? currentState.returnCondition ?? 'NORMAL')
          : null;
      final resolvedStatus = isReturn
          ? StockStatus.fromCode(
              event.returnStockStatus ??
                  currentState.returnStockStatus ??
                  ReturnCondition.fromId(resolvedCondition).stockStatus,
            ).code
          : null;
      final updatedItems = isReturn && resolvedStatus != null
          ? event.items
              .map(
                (item) => item.copyWith(
                  stockStatus: resolvedStatus,
                  product: item.product.copyWith(stockStatus: resolvedStatus),
                ),
              )
              .toList()
          : event.items;

      emit(currentState.copyWith(
        transactionType: txType,
        originalDocumentId: event.originalInvoiceId,
        cartItems: updatedItems,
        config: TransactionConfig.forType(txType),
        returnCondition: resolvedCondition,
        returnStockStatus: resolvedStatus,
      ));
    }
  }

  void _onRestoreOriginalInvoice(RestoreOriginalInvoice event, Emitter<SalesInvoiceState> emit) {
    final currentState = state;
    if (currentState is SalesInvoiceLoaded) {
      emit(currentState.copyWith(
        transactionType: event.transactionType,
        originalDocumentId: event.originalDocumentId,
        config: event.config,
        cartItems: event.cartItems,
      ));
    }
  }

  void _onInitializeTransaction(InitializeTransaction event, Emitter<SalesInvoiceState> emit) {
    final currentCustomer = state is SalesInvoiceLoaded ? (state as SalesInvoiceLoaded).customer : null;
    final currentCart = state is SalesInvoiceLoaded ? (state as SalesInvoiceLoaded).cartItems : const <CartItem>[];
    emit(SalesInvoiceLoaded(
      customer: event.customer ?? currentCustomer,
      cartItems: event.cartItems ?? currentCart,
      transactionType: event.transactionType,
      originalDocumentId: event.originalDocumentId,
      config: event.config,
      returnCondition: event.returnCondition,
      returnStockStatus: event.returnStockStatus,
    ));
  }

  void _onSetCustomer(SetCustomer event, Emitter<SalesInvoiceState> emit) {
    final currentState = state;
    if (currentState is SalesInvoiceLoaded) {
      emit(currentState.copyWith(customer: event.customer));
    } else {
      emit(SalesInvoiceLoaded(customer: event.customer));
    }
  }

  bool _canAddOrUpdateCartItem(SalesInvoiceLoaded state, CartItem item) {
    if (!item.isFoc && (item.basePrice <= 0.0001 || item.total <= 0.0001)) {
      return false;
    }
    if (!state.config.isReturnOrCreditNote && !StockStatus.isRawSellable(item.stockStatus)) {
      return false;
    }
    return true;
  }

  void _onAddCartItem(AddCartItem event, Emitter<SalesInvoiceState> emit) {
    final currentState = state;
    if (currentState is SalesInvoiceLoaded) {
      if (!_canAddOrUpdateCartItem(currentState, event.item)) {
        return;
      }
      final updatedCart = List.of(currentState.cartItems)..add(event.item);
      emit(currentState.copyWith(cartItems: updatedCart));
    }
  }

  void _onRemoveCartItem(RemoveCartItem event, Emitter<SalesInvoiceState> emit) {
    final currentState = state;
    if (currentState is SalesInvoiceLoaded) {
      if (event.index < 0 || event.index >= currentState.cartItems.length) return;
      final itemToRemove = currentState.cartItems[event.index];

      // CRITICAL: Direct deletion of an FOC item is strictly forbidden.
      // FOC items can only be removed when their parent promotion product is removed or adjusted.
      if (itemToRemove.isFoc) {
        return;
      }

      final updatedCart = List<CartItem>.from(currentState.cartItems)..removeAt(event.index);

      // Cascade remove any linked FOC promotion lines caused by this main product
      updatedCart.removeWhere((item) => item.isFoc && item.mainItemSku == itemToRemove.product.sku);

      emit(currentState.copyWith(cartItems: updatedCart));
    }
  }

  void _onRemoveLinkedFocItem(RemoveLinkedFocItem event, Emitter<SalesInvoiceState> emit) {
    final currentState = state;
    if (currentState is SalesInvoiceLoaded) {
      final updatedCart = List<CartItem>.from(currentState.cartItems)
        ..removeWhere((item) => item.isFoc && item.mainItemSku == event.mainItemSku);
      emit(currentState.copyWith(cartItems: updatedCart));
    }
  }

  void _onUpdateCartItem(UpdateCartItem event, Emitter<SalesInvoiceState> emit) {
    final currentState = state;
    if (currentState is SalesInvoiceLoaded) {
      if (!_canAddOrUpdateCartItem(currentState, event.item)) {
        return;
      }
      final updatedCart = List.of(currentState.cartItems);
      updatedCart[event.index] = event.item;
      emit(currentState.copyWith(cartItems: updatedCart));
    }
  }

  void _onUpsertProductLotCartItems(
    UpsertProductLotCartItems event,
    Emitter<SalesInvoiceState> emit,
  ) {
    final currentState = state;
    if (currentState is! SalesInvoiceLoaded) return;

    for (final item in event.paidItems) {
      if (!_canAddOrUpdateCartItem(currentState, item)) return;
    }
    for (final foc in event.focItems) {
      if (!_canAddOrUpdateCartItem(currentState, foc)) return;
    }

    final updatedCart = List<CartItem>.from(currentState.cartItems);
    int? insertIndex;

    if (event.replaceAllForSku) {
      for (int i = updatedCart.length - 1; i >= 0; i--) {
        if (!updatedCart[i].isFoc && updatedCart[i].product.sku == event.sku) {
          insertIndex = i;
          updatedCart.removeAt(i);
        }
      }
    } else if (event.editingIndex != null &&
        event.editingIndex! >= 0 &&
        event.editingIndex! < updatedCart.length &&
        !updatedCart[event.editingIndex!].isFoc) {
      insertIndex = event.editingIndex!;
      updatedCart.removeAt(event.editingIndex!);
    }

    // Remove existing FOC lines linked to this SKU before inserting updated FOC items.
    for (int i = updatedCart.length - 1; i >= 0; i--) {
      final item = updatedCart[i];
      if (item.isFoc && item.mainItemSku == event.sku) {
        if (insertIndex != null && i < insertIndex) {
          insertIndex--;
        }
        updatedCart.removeAt(i);
      }
    }

    final targetIndex = (insertIndex != null && insertIndex >= 0 && insertIndex <= updatedCart.length)
        ? insertIndex
        : updatedCart.length;
    final combinedInsert = <CartItem>[...event.paidItems, ...event.focItems];
    updatedCart.insertAll(targetIndex, combinedInsert);

    if (event.convertToCreditNote && currentState.transactionType == 'PREVIEW_INVOICE') {
      emit(currentState.copyWith(
        transactionType: 'CREDIT_NOTE',
        cartItems: updatedCart,
      ));
    } else {
      emit(currentState.copyWith(cartItems: updatedCart));
    }
  }

  void _onSetDeliveryDate(SetDeliveryDate event, Emitter<SalesInvoiceState> emit) {
    final currentState = state;
    if (currentState is SalesInvoiceLoaded) {
      emit(currentState.copyWith(deliveryDate: event.date));
    }
  }

  void _onClearCart(ClearCart event, Emitter<SalesInvoiceState> emit) {
    final currentState = state;
    if (currentState is SalesInvoiceLoaded) {
      emit(currentState.copyWith(cartItems: []));
    }
  }

  Future<void> _onSubmitTransaction(SubmitTransaction event, Emitter<SalesInvoiceState> emit) async {
    final currentState = state;
    if (currentState is! SalesInvoiceLoaded) return;
    
    if (currentState.customer == null || currentState.cartItems.isEmpty) {
      emit(const SalesInvoiceError("Customer and items are required."));
      emit(currentState); // Re-emit loaded state after showing error
      return;
    }

    emit(SalesInvoiceLoading());

    try {
      if (currentState.transactionType == 'SALES_ORDER') {
        await repository.saveSalesOrder(
          customer: currentState.customer!,
          items: currentState.cartItems,
          totalAmount: currentState.totalAmount,
          deliveryDate: event.deliveryDate ?? '',
        );
        emit(const SalesInvoiceSuccess("Sales Order created successfully."));
      } else if (currentState.transactionType == 'INVOICE') {
        await repository.saveInvoice(
          customer: currentState.customer!,
          items: currentState.cartItems,
          totalAmount: currentState.totalAmount,
          originalSalesOrderNumber: currentState.originalDocumentId,
          paymentMode: event.paymentMode,
        );
        // If it was derived from an SO, we'd mark the SO as converted
        if (currentState.originalDocumentId != null) {
          // This would ideally require the ID, but for now we skip complex logic
        }
        emit(const SalesInvoiceSuccess("Invoice created successfully."));
      } else if (currentState.transactionType == 'CREDIT_NOTE') {
        // Filter out items with 0 return quantity for credit notes
        final itemsToReverse = currentState.cartItems.where((i) => i.quantity > 0).toList();
        
        if (itemsToReverse.isEmpty) {
          emit(const SalesInvoiceError("No items to return."));
          emit(currentState);
          return;
        }

        // If it has an original ID, it's a reversed invoice. Otherwise open CN.
        if (currentState.originalDocumentId != null) {
          await repository.reverseInvoice(
            originalInvoiceId: int.parse(currentState.originalDocumentId!),
            itemsToReverse: itemsToReverse,
          );
        } else {
          await repository.createStandaloneCreditNote(
            customer: currentState.customer!,
            items: itemsToReverse,
            totalAmount: itemsToReverse.fold(0.0, (sum, i) => sum + i.total),
            refundMethod: event.paymentMode,
          );
        }
        emit(const SalesInvoiceSuccess("Credit Note created successfully."));
      }
    } catch (e) {
      emit(SalesInvoiceError(e.toString()));
      emit(currentState);
    }
  }
}
