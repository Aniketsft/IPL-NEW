import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/local_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/delivery_repository.dart';

class SyncManager {
  final LocalRepository _localRepository;
  final DeliveryRepository _deliveryRepository;
  Timer? _syncTimer;
  bool _isSyncing = false;

  SyncManager({
    required LocalRepository localRepository,
    required DeliveryRepository deliveryRepository,
  }) : _localRepository = localRepository,
       _deliveryRepository = deliveryRepository;

  void startPeriodicSync({Duration interval = const Duration(minutes: 1)}) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(interval, (_) => syncNow());
  }

  void stopPeriodicSync() {
    _syncTimer?.cancel();
  }

  Future<void> syncNow() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final unsyncedScans = await _localRepository.getUnsyncedScans();

      if (unsyncedScans.isEmpty) {
        _isSyncing = false;
        return;
      }

      if (kDebugMode) {
        print('Starting sync for ${unsyncedScans.length} scans...');
      }

      // Try to send to API
      await _deliveryRepository.syncScans(unsyncedScans);

      // If successful, mark as synced
      final ids = unsyncedScans.map((s) => s['id'] as int).toList();
      await _localRepository.markScansAsSynced(ids);

      if (kDebugMode) {
        print('Successfully synced ${ids.length} scans.');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Sync failed: $e. Will retry later.');
      }
    } finally {
      _isSyncing = false;
    }
  }
}
