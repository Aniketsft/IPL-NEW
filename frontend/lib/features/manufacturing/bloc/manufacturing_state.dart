import 'package:equatable/equatable.dart';
import '../../logistics/domain/entities/sales_order_detail.dart';

abstract class ManufacturingState extends Equatable {
  final String? currentSiteCode;
  final String dashboardSearchQuery;
  final DateTime? selectedDate;
  final String selectedSchema;

  const ManufacturingState({
    this.currentSiteCode,
    this.dashboardSearchQuery = '',
    this.selectedDate,
    this.selectedSchema = 'INLPROD',
  });

  @override
  List<Object?> get props => [currentSiteCode, dashboardSearchQuery, selectedDate, selectedSchema];
}

class ManufacturingInitial extends ManufacturingState {
  const ManufacturingInitial({super.selectedSchema}) : super(selectedDate: null);
}

class ManufacturingLoadInProgress extends ManufacturingState {
  const ManufacturingLoadInProgress({
    super.currentSiteCode,
    super.dashboardSearchQuery,
    super.selectedDate,
    super.selectedSchema,
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
    super.selectedSchema,
  });

  @override
  List<Object?> get props => [items, excessPools, currentSiteCode, dashboardSearchQuery, selectedDate, selectedSchema];
}

class ManufacturingFailure extends ManufacturingState {
  final String message;

  const ManufacturingFailure(
    this.message, {
    super.currentSiteCode,
    super.dashboardSearchQuery,
    super.selectedDate,
    super.selectedSchema,
  });

  @override
  List<Object?> get props => [message, currentSiteCode, dashboardSearchQuery, selectedDate, selectedSchema];
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
    super.selectedSchema,
  });

  @override
  List<Object?> get props => [phase, progress, message, currentSiteCode, dashboardSearchQuery, selectedDate, selectedSchema];
}
