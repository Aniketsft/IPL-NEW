import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/local_repository.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/repositories/delivery_repository.dart';
import '../local/local_database_helper.dart';

class SyncManager {
  final LocalRepository _localRepository;
  final DeliveryRepository _deliveryRepository;
  final math.Random _random = math.Random();
  Timer? _syncTimer;
  bool _isSyncing = false;

  SyncManager({
    required LocalRepository localRepository,
    required DeliveryRepository deliveryRepository,
  }) : _localRepository = localRepository,
       _deliveryRepository = deliveryRepository;

  void startPeriodicSync({
    Duration interval = const Duration(minutes: 1),
    Duration maxJitter = const Duration(seconds: 15),
  }) {
    _syncTimer?.cancel();
    _scheduleNextSync(interval, maxJitter);
  }

  void _scheduleNextSync(Duration baseInterval, Duration maxJitter) {
    // Disperse sync times across devices by applying randomized jitter
    final jitterMillis = maxJitter.inMilliseconds > 0
        ? _random.nextInt(maxJitter.inMilliseconds * 2) - maxJitter.inMilliseconds
        : 0;
    final delay = Duration(
      milliseconds: math.max(10000, baseInterval.inMilliseconds + jitterMillis),
    );

    _syncTimer = Timer(delay, () async {
      await syncNow();
      _scheduleNextSync(baseInterval, maxJitter);
    });
  }

  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
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

      // Group scans by site
      final Map<String, List<Map<String, dynamic>>> groupedScans = {};
      for (var scan in unsyncedScans) {
        final site = scan[LocalDatabaseHelper.columnSite] as String? ?? 'IPL';
        groupedScans.putIfAbsent(site, () => []).add(scan);
      }

      for (var site in groupedScans.keys) {
        final scans = groupedScans[site]!;
        
        if (kDebugMode) {
          print('Starting sync for ${scans.length} scans at site $site...');
        }

        // Try to send to API
        await _deliveryRepository.syncScans(scans, siteCode: site);

        // If successful, mark as synced
        final ids = scans.map((s) => s['id'] as int).toList();
        await _localRepository.markScansAsSynced(ids);

        if (kDebugMode) {
          print('Successfully synced ${ids.length} scans for site $site.');
        }
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
