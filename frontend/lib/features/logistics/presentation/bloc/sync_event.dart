import 'package:equatable/equatable.dart';

abstract class SyncEvent extends Equatable {
  const SyncEvent();

  @override
  List<Object> get props => [];
}

class StartSyncRequested extends SyncEvent {
  final String? siteCode;

  const StartSyncRequested({this.siteCode});

  @override
  List<Object> get props => [siteCode ?? ''];
}

class SyncProgressUpdated extends SyncEvent {
  final double progress;
  final String message;

  const SyncProgressUpdated(this.progress, this.message);

  @override
  List<Object> get props => [progress, message];
}

class ResetSyncRequested extends SyncEvent {
  const ResetSyncRequested();

  @override
  List<Object> get props => [];
}

class StartX3SoapExportRequested extends SyncEvent {
  final Future<dynamic> Function() exportAction;
  final String message;

  const StartX3SoapExportRequested({
    required this.exportAction,
    this.message = 'Exporting data to Sage X3...',
  });

  @override
  List<Object> get props => [message];
}

