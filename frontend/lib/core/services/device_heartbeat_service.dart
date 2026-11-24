import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../network_service.dart';
import '../secure_storage_service.dart';
import 'device_info_service.dart';
import '../../features/logistics/data/local/local_database_helper.dart';
import '../../features/logistics/data/repositories/sales_invoice_product_repository.dart';

/// Shared helper to synchronize device identity, assigned lorry scope, and
/// document sequences over the authenticated [NetworkService] Dio client.
class DeviceHeartbeatService {
  final NetworkService _networkService;
  final SecureStorageService _storageService;

  DeviceHeartbeatService({
    required NetworkService networkService,
    required SecureStorageService storageService,
  })  : _networkService = networkService,
        _storageService = storageService;

  Future<bool> syncDeviceLocation({
    String? siteCode,
    bool includeDocSequences = false,
  }) async {
    try {
      final deviceService = DeviceInfoService.instance;
      final devId = deviceService.deviceId;
      final db = LocalDatabaseHelper.instance;

      // 1. Warm local SQLite mapping if available for offline continuity
      Map<String, dynamic>? localMapping;
      if (devId.isNotEmpty) {
        localMapping = await db.getDeviceLocation(devId);
        if (localMapping != null && localMapping['locationCode'] != null) {
          await deviceService.setAssignedLocation(
            siteCode: localMapping['siteCode']?.toString() ??
                deviceService.resolveEffectiveSiteCode(siteCode),
            warehouseCode: localMapping['warehouseCode']?.toString(),
            locationCode: localMapping['locationCode'].toString(),
          );
        }
      }

      final token = await _storageService.getToken();
      if (token == null || token.isEmpty || token.startsWith('OFFLINE_SESSION_')) {
        return false;
      }

      final cleanRequestedSite = (siteCode ?? '').trim().toUpperCase();
      final effectiveRequestSite = (cleanRequestedSite.isNotEmpty && cleanRequestedSite != 'ALL')
          ? cleanRequestedSite
          : deviceService.resolveEffectiveSiteCode(siteCode);

      // 2. Online Heartbeat via Dio (inherits JWT, schema, device headers & dev TLS bypass)
      final resp = await _networkService.dio.post(
        'Devices/heartbeat',
        data: {
          'deviceId': devId,
          'deviceName': deviceService.deviceName,
          'hardwareModel': deviceService.hardwareModel,
          'hardwareIdentifier': deviceService.hardwareIdentifier,
          if (effectiveRequestSite.isNotEmpty) 'siteCode': effectiveRequestSite,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

      if (resp.statusCode == 200 && resp.data is Map) {
        final data = Map<String, dynamic>.from(resp.data as Map);
        if (data['deviceId'] == null) return false;

        final prevAssigned =
            (localMapping?['locationCode'] ?? deviceService.assignedLocation)
                ?.toString()
                .trim()
                .toUpperCase() ??
            '';
        final prevWrh =
            (localMapping?['warehouseCode'] ?? deviceService.assignedWarehouse)
                ?.toString()
                .trim()
                .toUpperCase() ??
            '';
        final loc = data['locationCode']?.toString() ?? '';
        final wrh = data['warehouseCode']?.toString();
        final rawRespSite = data['siteCode']?.toString().trim().toUpperCase() ?? '';
        final resolvedSite = (rawRespSite.isNotEmpty && rawRespSite != 'ALL')
            ? rawRespSite
            : effectiveRequestSite;
        final uuid = data['deviceId']?.toString() ?? '';
        final name = data['deviceName']?.toString() ?? deviceService.deviceName;
        final isLicensed = data['isLicensed'] == true;
        final licenseStatus = data['licenseStatus']?.toString() ?? 'VALID';
        final isLocked = data['isLocked'] == true;
        final hepProfile = data['hepProfileId']?.toString();

        if (DeviceInfoService.isValidUuid(uuid)) {
          await deviceService.setDeviceIdentity(
            uuid: uuid,
            name: name,
            hardwareIdentifier: data['hardwareIdentifier']?.toString() ?? deviceService.hardwareIdentifier,
            siteCode: resolvedSite,
            warehouseCode: wrh,
            locationCode: loc,
            isLicensed: isLicensed,
            licenseStatus: licenseStatus,
            isLocked: isLocked,
            hepProfileId: hepProfile,
            hepApiKey: data['hepApiKey']?.toString(),
          );
        }
        await db.insertOrUpdateDeviceLocation(data);

        final newAssigned = loc.trim().toUpperCase();
        final newWrh = (wrh ?? '').trim().toUpperCase();
        if (prevAssigned != newAssigned || prevWrh != newWrh) {
          await SalesInvoiceProductRepository.invalidateStockCache(
            clearLocalRows:
                (prevAssigned.isNotEmpty && prevAssigned != newAssigned) ||
                (prevWrh.isNotEmpty && prevWrh != newWrh),
          );
        }

        if (includeDocSequences && resolvedSite.isNotEmpty && resolvedSite != 'ALL') {
          try {
            final seqResp = await _networkService.dio.get(
              'SalesInvoice/document-sequences',
              queryParameters: {'siteCode': resolvedSite},
              options: Options(receiveTimeout: const Duration(seconds: 6)),
            );
            if (seqResp.statusCode == 200 && seqResp.data is List && (seqResp.data as List).isNotEmpty) {
              await db.syncDocumentSequencesHighWaterMark(seqResp.data as List);
            }
          } catch (seqErr) {
            debugPrint('DeviceHeartbeatService: Document sequence login sync skipped: $seqErr');
          }
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('DeviceHeartbeatService: Device location sync warning (offline fallback used): $e');
      return false;
    }
  }
}
