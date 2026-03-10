import 'package:equatable/equatable.dart';

abstract class ManufacturingEvent extends Equatable {
  const ManufacturingEvent();

  @override
  List<Object?> get props => [];
}

class LoadProductionTrackingRequested extends ManufacturingEvent {
  const LoadProductionTrackingRequested();

  @override
  List<Object?> get props => [];
}
