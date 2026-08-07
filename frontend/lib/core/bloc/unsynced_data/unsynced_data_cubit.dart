import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sync_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sync_state.dart';

class UnsyncedDataCubit extends Cubit<bool> with WidgetsBindingObserver {
  final LocalDatabaseHelper _databaseHelper;
  final SyncBloc _syncBloc;
  
  Timer? _pollingTimer;
  late final StreamSubscription<SyncState> _syncSubscription;

  UnsyncedDataCubit({
    required LocalDatabaseHelper databaseHelper,
    required SyncBloc syncBloc,
  })  : _databaseHelper = databaseHelper,
        _syncBloc = syncBloc,
        super(false) {
    WidgetsBinding.instance.addObserver(this);
    
    // Initial check
    checkUnsyncedData();

    // Start 5 second polling
    _startTimer();

    // Listen to SyncBloc for immediate updates when sync finishes or fails
    _syncSubscription = _syncBloc.stream.listen((syncState) {
      if (syncState is SyncSuccess || syncState is SyncFailure) {
        // Give the DB a slight moment to settle after sync
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!isClosed) {
            checkUnsyncedData();
            _startTimer(); // Reset the timer so it starts counting from now
          }
        });
      }
    });
  }

  void _startTimer() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      checkUnsyncedData();
    });
  }

  Future<void> checkUnsyncedData() async {
    if (isClosed) return;
    try {
      final hasData = await _databaseHelper.hasUnsyncedData();
      if (!isClosed && state != hasData) {
        emit(hasData);
      }
    } catch (e) {
      debugPrint("Error in UnsyncedDataCubit: \$e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkUnsyncedData();
    }
  }

  @override
  Future<void> close() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    _syncSubscription.cancel();
    return super.close();
  }
}
