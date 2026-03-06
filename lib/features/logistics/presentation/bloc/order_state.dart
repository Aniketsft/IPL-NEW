import 'package:equatable/equatable.dart';

import '../../domain/entities/sales_order_detail.dart';

abstract class OrderState extends Equatable {
  const OrderState();

  @override
  List<Object?> get props => [];
}

class OrderInitial extends OrderState {}

class OrderLoadInProgress extends OrderState {}

class OrderFailure extends OrderState {
  final String message;

  const OrderFailure(this.message);

  @override
  List<Object?> get props => [message];
}

class SalesOrderItemsLoaded extends OrderState {
  final List<SalesOrderDetail> items;

  const SalesOrderItemsLoaded(this.items);

  @override
  List<Object?> get props => [items];
}
