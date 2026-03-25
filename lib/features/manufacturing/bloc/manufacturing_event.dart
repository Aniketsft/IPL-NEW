import 'package:equatable/equatable.dart';

abstract class ManufacturingEvent extends Equatable {
  const ManufacturingEvent();

  @override
  List<Object?> get props => [];
}

class LoadProductionTrackingRequested extends ManufacturingEvent {
  final String? siteCode;

  const LoadProductionTrackingRequested({this.siteCode});

  @override
  List<Object?> get props => [siteCode];
}

class SiteFilterChanged extends ManufacturingEvent {
  final String? siteCode;

  const SiteFilterChanged(this.siteCode);

  @override
  List<Object?> get props => [siteCode];
}

class DashboardSearchChanged extends ManufacturingEvent {
  final String query;

  const DashboardSearchChanged(this.query);

  @override
  List<Object?> get props => [query];
}

class SyncDataRequested extends ManufacturingEvent {
  final String? siteCode;

  const SyncDataRequested({this.siteCode});

  @override
  List<Object?> get props => [siteCode];
}
class UpdateItemPreparationStatus extends ManufacturingEvent {
  final String soNumber;
  final String itemCode;
  final bool isPrepared;

  const UpdateItemPreparationStatus({
    required this.soNumber,
    required this.itemCode,
    required this.isPrepared,
  });

  @override
  List<Object?> get props => [soNumber, itemCode, isPrepared];
}
