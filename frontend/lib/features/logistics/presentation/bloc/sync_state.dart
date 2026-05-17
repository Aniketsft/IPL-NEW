import 'package:equatable/equatable.dart';

abstract class SyncState extends Equatable {
  const SyncState();

  @override
  List<Object?> get props => [];
}

class SyncInitial extends SyncState {}

class SyncInProgress extends SyncState {
  final double progress;
  final String message;

  const SyncInProgress(this.progress, this.message);

  @override
  List<Object?> get props => [progress, message];
}

class SyncSuccess extends SyncState {
  final String lastSync;

  const SyncSuccess(this.lastSync);

  @override
  List<Object?> get props => [lastSync];
}

class SyncFailure extends SyncState {
  final String error;

  const SyncFailure(this.error);

  @override
  List<Object?> get props => [error];
}
