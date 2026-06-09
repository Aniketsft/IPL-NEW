import 'package:equatable/equatable.dart';

abstract class OrderEvent extends Equatable {
  const OrderEvent();

  @override
  List<Object?> get props => [];
}

class LoadSalesOrderItemsRequested extends OrderEvent {
  final DateTime? date;
  final String? site;
  final String? customerCode;
  final String? salesRepCode;

  const LoadSalesOrderItemsRequested({
    this.date,
    this.site,
    this.customerCode,
    this.salesRepCode,
  });

  @override
  List<Object?> get props => [date, site, customerCode, salesRepCode];
}

class LoadFiltersRequested extends OrderEvent {
  const LoadFiltersRequested();
}
