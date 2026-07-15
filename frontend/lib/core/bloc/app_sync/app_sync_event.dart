import 'package:equatable/equatable.dart';

abstract class AppSyncEvent extends Equatable {
  const AppSyncEvent();

  @override
  List<Object> get props => [];
}

class LoadAppSyncTimeEvent extends AppSyncEvent {}

class UpdateAppSyncTimeEvent extends AppSyncEvent {
  final String lastSyncTime;

  const UpdateAppSyncTimeEvent(this.lastSyncTime);

  @override
  List<Object> get props => [lastSyncTime];
}
