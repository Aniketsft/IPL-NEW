import 'package:equatable/equatable.dart';
import '../../logistics/domain/entities/sales_order_detail.dart';

abstract class ManufacturingState extends Equatable {
  const ManufacturingState();

  @override
  List<Object?> get props => [];
}

class ManufacturingInitial extends ManufacturingState {}

class ManufacturingLoadInProgress extends ManufacturingState {}

class ProductionTrackingLoaded extends ManufacturingState {
  final List<SalesOrderDetail> items;

  const ProductionTrackingLoaded(this.items);

  @override
  List<Object?> get props => [items];
}

class ManufacturingFailure extends ManufacturingState {
  final String message;

  const ManufacturingFailure(this.message);

  @override
  List<Object?> get props => [message];
}
