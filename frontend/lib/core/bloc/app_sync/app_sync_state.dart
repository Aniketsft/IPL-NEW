import 'package:equatable/equatable.dart';

class AppSyncState extends Equatable {
  final String? lastSyncTime;
  // We use this to distinguish from a null default when passing it around, but null usually means 'Never'.
  // However, we want to allow setting it to null to clear it if needed.
  // Actually copyWith semantics need to be handled nicely.
  
  const AppSyncState({this.lastSyncTime});

  AppSyncState copyWith({String? lastSyncTime}) {
    return AppSyncState(
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }

  // Allow explicit clearing if needed, though usually not needed.
  AppSyncState copyWithClearSync() {
    return const AppSyncState(lastSyncTime: null);
  }

  @override
  List<Object?> get props => [lastSyncTime];
}
