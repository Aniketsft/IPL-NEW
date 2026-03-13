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

enum SyncPhase { idle, pushing, pulling, success }

class ManufacturingSyncProgress extends ManufacturingState {
  final SyncPhase phase;
  final double progress; // 0.0 to 1.0
  final String message;

  const ManufacturingSyncProgress({
    required this.phase,
    required this.progress,
    required this.message,
  });

  @override
  List<Object?> get props => [phase, progress, message];
}
