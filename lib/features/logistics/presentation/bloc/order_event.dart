import 'package:equatable/equatable.dart';

abstract class OrderEvent extends Equatable {
  const OrderEvent();

  @override
  List<Object?> get props => [];
}

class LoadSalesOrderItemsRequested extends OrderEvent {
  final DateTime? date;

  const LoadSalesOrderItemsRequested({this.date});

  @override
  List<Object?> get props => [date];
}
