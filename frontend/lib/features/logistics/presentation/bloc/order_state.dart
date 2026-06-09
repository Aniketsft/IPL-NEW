import 'package:equatable/equatable.dart';

import '../../domain/entities/sales_order_detail.dart';
import '../../domain/entities/site.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/sales_rep.dart';

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
  final List<Site> sites;
  final List<Customer> customers;
  final List<SalesRep> salesReps;
  final DateTime? selectedDate;
  final String? selectedSite;
  final String? selectedCustomer;
  final String? selectedSalesRep;

  const SalesOrderItemsLoaded({
    required this.items,
    this.sites = const [],
    this.customers = const [],
    this.salesReps = const [],
    this.selectedDate,
    this.selectedSite,
    this.selectedCustomer,
    this.selectedSalesRep,
  });

  @override
  List<Object?> get props => [
        items,
        sites,
        customers,
        salesReps,
        selectedDate,
        selectedSite,
        selectedCustomer,
        selectedSalesRep,
      ];

  SalesOrderItemsLoaded copyWith({
    List<SalesOrderDetail>? items,
    List<Site>? sites,
    List<Customer>? customers,
    List<SalesRep>? salesReps,
    DateTime? selectedDate,
    String? selectedSite,
    String? selectedCustomer,
    String? selectedSalesRep,
  }) {
    return SalesOrderItemsLoaded(
      items: items ?? this.items,
      sites: sites ?? this.sites,
      customers: customers ?? this.customers,
      salesReps: salesReps ?? this.salesReps,
      selectedDate: selectedDate ?? this.selectedDate,
      selectedSite: selectedSite ?? this.selectedSite,
      selectedCustomer: selectedCustomer ?? this.selectedCustomer,
      selectedSalesRep: selectedSalesRep ?? this.selectedSalesRep,
    );
  }
}
