import 'package:equatable/equatable.dart';

abstract class SyncEvent extends Equatable {
  const SyncEvent();

  @override
  List<Object> get props => [];
}

class StartSyncRequested extends SyncEvent {}

class SyncProgressUpdated extends SyncEvent {
  final double progress;
  final String message;

  const SyncProgressUpdated(this.progress, this.message);

  @override
  List<Object> get props => [progress, message];
}
