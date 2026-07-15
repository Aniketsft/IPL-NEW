import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'app_sync_event.dart';
import 'app_sync_state.dart';

class AppSyncBloc extends Bloc<AppSyncEvent, AppSyncState> {
  static const String _syncKey = 'last_sync_timestamp';

  AppSyncBloc() : super(const AppSyncState()) {
    on<LoadAppSyncTimeEvent>(_onLoadAppSyncTime);
    on<UpdateAppSyncTimeEvent>(_onUpdateAppSyncTime);
  }

  Future<void> _onLoadAppSyncTime(
    LoadAppSyncTimeEvent event,
    Emitter<AppSyncState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    String? lastSync = prefs.getString(_syncKey);

    if (lastSync == null) {
      try {
        final history = await LocalDatabaseHelper.instance.getSyncHistory();
        if (history.isNotEmpty) {
          final last = history.firstWhere(
            (h) => h[LocalDatabaseHelper.colSyncStatus] == 'Success',
            orElse: () => history.first,
          );
          if (last[LocalDatabaseHelper.colSyncStatus] == 'Success') {
            final timestampStr = last[LocalDatabaseHelper.colSyncTimestamp] as String;
            final timestamp = DateTime.tryParse(timestampStr);
            if (timestamp != null) {
              lastSync = DateFormat('yyyy-MM-dd HH:mm').format(timestamp);
              await prefs.setString(_syncKey, lastSync);
            }
          }
        }
      } catch (e) {
        // ignore
      }
    }

    emit(AppSyncState(lastSyncTime: lastSync));
  }

  Future<void> _onUpdateAppSyncTime(
    UpdateAppSyncTimeEvent event,
    Emitter<AppSyncState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_syncKey, event.lastSyncTime);
    emit(AppSyncState(lastSyncTime: event.lastSyncTime));
  }
}
