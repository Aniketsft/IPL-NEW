import 'package:equatable/equatable.dart';

abstract class ManufacturingEvent extends Equatable {
  const ManufacturingEvent();

  @override
  List<Object?> get props => [];
}

class LoadProductionTrackingRequested extends ManufacturingEvent {
  final String? location;

  const LoadProductionTrackingRequested({this.location});

  @override
  List<Object?> get props => [location];
}
