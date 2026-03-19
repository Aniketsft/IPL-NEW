import 'package:equatable/equatable.dart';
import '../../logistics/domain/entities/sales_order_detail.dart';

abstract class ManufacturingState extends Equatable {
  final String? currentSiteCode;
  final String dashboardSearchQuery;

  const ManufacturingState({
    this.currentSiteCode,
    this.dashboardSearchQuery = '',
  });

  @override
  List<Object?> get props => [currentSiteCode, dashboardSearchQuery];
}

class ManufacturingInitial extends ManufacturingState {
  const ManufacturingInitial() : super();
}

class ManufacturingLoadInProgress extends ManufacturingState {
  const ManufacturingLoadInProgress({
    super.currentSiteCode,
    super.dashboardSearchQuery,
  });
}

class ProductionTrackingLoaded extends ManufacturingState {
  final List<SalesOrderDetail> items;

  const ProductionTrackingLoaded({
    required this.items,
    super.currentSiteCode,
    super.dashboardSearchQuery,
  });

  @override
  List<Object?> get props => [items, currentSiteCode, dashboardSearchQuery];
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
