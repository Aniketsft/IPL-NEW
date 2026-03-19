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
