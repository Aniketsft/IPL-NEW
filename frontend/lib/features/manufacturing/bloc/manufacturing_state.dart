import 'package:equatable/equatable.dart';
import '../../logistics/domain/entities/sales_order_detail.dart';

abstract class ManufacturingState extends Equatable {
  final String? currentSiteCode;
  final String dashboardSearchQuery;
  final DateTime? selectedDate;

  const ManufacturingState({
    this.currentSiteCode,
    this.dashboardSearchQuery = '',
    this.selectedDate,
  });

  @override
  List<Object?> get props => [currentSiteCode, dashboardSearchQuery, selectedDate];
}

class ManufacturingInitial extends ManufacturingState {
  ManufacturingInitial() : super(selectedDate: DateTime.now());
}

class ManufacturingLoadInProgress extends ManufacturingState {
  const ManufacturingLoadInProgress({
    super.currentSiteCode,
    super.dashboardSearchQuery,
    super.selectedDate,
  });
}

class ProductionTrackingLoaded extends ManufacturingState {
  final List<SalesOrderDetail> items;
  final Map<String, double> excessPools;

  const ProductionTrackingLoaded({
    required this.items,
    this.excessPools = const {},
    super.currentSiteCode,
    super.dashboardSearchQuery,
    super.selectedDate,
  });

  @override
  List<Object?> get props => [items, excessPools, currentSiteCode, dashboardSearchQuery, selectedDate];
}

class ManufacturingFailure extends ManufacturingState {
  final String message;

  const ManufacturingFailure(
    this.message, {
    super.currentSiteCode,
    super.dashboardSearchQuery,
    super.selectedDate,
  });

  @override
  List<Object?> get props => [message, currentSiteCode, dashboardSearchQuery, selectedDate];
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
    super.currentSiteCode,
    super.dashboardSearchQuery,
    super.selectedDate,
  });

  @override
  List<Object?> get props => [phase, progress, message, currentSiteCode, dashboardSearchQuery, selectedDate];
}
