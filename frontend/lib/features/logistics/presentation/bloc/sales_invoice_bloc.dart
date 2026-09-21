import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repositories/i_sales_repository.dart';
import 'sales_invoice_event.dart';
import 'sales_invoice_state.dart';

class SalesInvoiceBloc extends Bloc<SalesInvoiceEvent, SalesInvoiceState> {
  final ISalesRepository repository;

  SalesInvoiceBloc({required this.repository}) : super(SalesInvoiceInitial()) {
    on<InitializeTransaction>(_onInitializeTransaction);
    on<PrepareReversalCreditNote>(_onPrepareReversalCreditNote);
    on<RestoreOriginalInvoice>(_onRestoreOriginalInvoice);
    on<SetCustomer>(_onSetCustomer);
    on<AddCartItem>(_onAddCartItem);
    on<RemoveCartItem>(_onRemoveCartItem);
    on<UpdateCartItem>(_onUpdateCartItem);
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
      emit(currentState.copyWith(
        transactionType: 'CREDIT_NOTE',
        originalDocumentId: event.originalInvoiceId,
        cartItems: event.items,
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
    emit(SalesInvoiceLoaded(
      transactionType: event.transactionType,
      originalDocumentId: event.originalDocumentId,
      config: event.config,
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

  void _onAddCartItem(AddCartItem event, Emitter<SalesInvoiceState> emit) {
    final currentState = state;
    if (currentState is SalesInvoiceLoaded) {
      final updatedCart = List.of(currentState.cartItems)..add(event.item);
      emit(currentState.copyWith(cartItems: updatedCart));
    }
  }

  void _onRemoveCartItem(RemoveCartItem event, Emitter<SalesInvoiceState> emit) {
    final currentState = state;
    if (currentState is SalesInvoiceLoaded) {
      final updatedCart = List.of(currentState.cartItems)..removeAt(event.index);
      emit(currentState.copyWith(cartItems: updatedCart));
    }
  }

  void _onUpdateCartItem(UpdateCartItem event, Emitter<SalesInvoiceState> emit) {
    final currentState = state;
    if (currentState is SalesInvoiceLoaded) {
      final updatedCart = List.of(currentState.cartItems);
      updatedCart[event.index] = event.item;
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
