import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceInfoService {
  static final DeviceInfoService _instance = DeviceInfoService._internal();
  factory DeviceInfoService() => _instance;
  DeviceInfoService._internal();

  static DeviceInfoService get instance => _instance;

  String _hardwareModel = 'UnknownDevice';
  String _hardwareIdentifier = '';
  String _deviceUuid = '';
  String _deviceName = '';
  String? _assignedLocation;
  String? _assignedWarehouse;
  String? _assignedSite;
  String? _hepProfileId;
  String? _hepApiKey;
  String? _ebsCounterNo;
  bool _isLicensed = true;
  String _licenseStatus = 'VALID';
  bool _isLocked = true;

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool isValidUuid(String? id) => id != null && _uuidRegex.hasMatch(id.trim());

  static bool isHardwareOrLegacyName(String? name) {
    if (name == null || name.trim().isEmpty) return true;
    final lower = name.trim().toLowerCase();
    return lower.contains('infinix') ||
        lower.contains('android') ||
        lower.contains('samsung') ||
        lower.contains('windows') ||
        lower.contains('unknowndevice') ||
        lower.contains('platform:') ||
        lower.contains('terminal-');
  }

  String get hardwareModel => _hardwareModel;
  String get hardwareIdentifier => _hardwareIdentifier;
  String get deviceInfo => _hardwareModel;
  String get deviceUuid => _deviceUuid;
  String get deviceId => isValidUuid(_deviceUuid) ? _deviceUuid : '';
  String get deviceName => !isHardwareOrLegacyName(_deviceName) ? _deviceName : '';
  String? get assignedLocation => _assignedLocation;
  String? get assignedWarehouse => _assignedWarehouse;
  String? get assignedSite => _assignedSite;
  String? get hepProfileId => _hepProfileId;
  String? get hepApiKey => _hepApiKey;
  String get ebsCounterNo => (_ebsCounterNo != null && _ebsCounterNo!.trim().isNotEmpty) ? _ebsCounterNo!.trim() : '1';
  bool get isLicensed => _isLicensed;
  String get licenseStatus => _licenseStatus;
  bool get isLocked => _isLocked;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Resolve Hardware Model and Platform-Unique Hardware Identifier
    try {
      final deviceInfoPlugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        final model = androidInfo.model.trim();
        String configuredName = 'Unknown';
        String nativeHwId = '';
        try {
          const platform = MethodChannel('com.enterprise.auth/device_name');
          final String? devName = await platform.invokeMethod('getDeviceName');
          if (devName != null && devName.isNotEmpty) {
            configuredName = devName;
          }
          final String? hwId = await platform.invokeMethod('getHardwareIdentifier');
          if (hwId != null && hwId.isNotEmpty) {
            nativeHwId = hwId.trim();
          }
        } catch (e) {
          debugPrint('Failed to get Android configured device info: $e');
        }
        _hardwareModel = '$model ($configuredName)';
        _hardwareIdentifier = nativeHwId.isNotEmpty ? nativeHwId : (androidInfo.id.isNotEmpty ? androidInfo.id : '');
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        final name = iosInfo.name;
        final model = iosInfo.model;
        _hardwareModel = '$model ($name)';
        _hardwareIdentifier = iosInfo.identifierForVendor ?? '';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfoPlugin.windowsInfo;
        _hardwareModel = 'Windows (${windowsInfo.computerName})';
        _hardwareIdentifier = windowsInfo.deviceId.isNotEmpty ? windowsInfo.deviceId : windowsInfo.computerName;
      } else {
        _hardwareModel = 'Platform: ${Platform.operatingSystem}';
      }
      debugPrint('DeviceInfoService: Resolved hardware model: $_hardwareModel, identifier: $_hardwareIdentifier');
    } catch (e) {
      debugPrint('DeviceInfoService: Failed to resolve hardware model: $e');
      _hardwareModel = 'Terminal-${Platform.operatingSystem}-${DateTime.now().millisecondsSinceEpoch}';
    }

    // 2. Ensure Persistent Hardware Identifier (Fallback to generated seed if native unavailable)
    if (_hardwareIdentifier.isEmpty) {
      final savedHwId = prefs.getString('device_hardware_identifier') ?? '';
      if (savedHwId.isNotEmpty) {
        _hardwareIdentifier = savedHwId;
      } else {
        final newHwId = const Uuid().v4();
        _hardwareIdentifier = newHwId;
        await prefs.setString('device_hardware_identifier', newHwId);
      }
    } else {
      await prefs.setString('device_hardware_identifier', _hardwareIdentifier);
    }

    // 3. Load Cached Device Identity
    try {
      final savedUuid = prefs.getString('device_assigned_uuid') ?? '';
      _deviceUuid = isValidUuid(savedUuid) ? savedUuid.toLowerCase() : '';
      final savedName = prefs.getString('device_assigned_name') ?? '';
      _deviceName = !isHardwareOrLegacyName(savedName) ? savedName : '';
      _assignedSite = prefs.getString('device_assigned_site');
      _assignedWarehouse = prefs.getString('device_assigned_warehouse');
      _assignedLocation = prefs.getString('device_assigned_location');
      _hepProfileId = prefs.getString('device_hep_profile_id');
      _hepApiKey = prefs.getString('device_hep_api_key');
      _ebsCounterNo = prefs.getString('device_ebs_counter_no');
      _isLicensed = prefs.getBool('device_is_licensed') ?? true;
      _licenseStatus = prefs.getString('device_license_status') ?? 'VALID';
      _isLocked = prefs.getBool('device_is_locked') ?? true;
    } catch (e) {
      debugPrint('DeviceInfoService: Failed to load cached device identity: $e');
    }
  }

  Future<void> setDeviceIdentity({
    required String uuid,
    required String name,
    String? hardwareIdentifier,
    String? siteCode,
    String? warehouseCode,
    String? locationCode,
    String? hepProfileId,
    String? hepApiKey,
    String? ebsCounterNo,
    bool? isLicensed,
    String? licenseStatus,
    bool? isLocked,
  }) async {
    final cleanUuid = isValidUuid(uuid) ? uuid.toLowerCase() : '';
    final cleanName = !isHardwareOrLegacyName(name) ? name.trim() : '';
    _deviceUuid = cleanUuid;
    _deviceName = cleanName;
    if (hardwareIdentifier != null && hardwareIdentifier.isNotEmpty) {
      _hardwareIdentifier = hardwareIdentifier.trim();
    }
    if (siteCode != null) _assignedSite = siteCode;
    if (warehouseCode != null) _assignedWarehouse = warehouseCode;
    if (locationCode != null) _assignedLocation = locationCode;
    if (hepProfileId != null) _hepProfileId = hepProfileId;
    if (hepApiKey != null) _hepApiKey = hepApiKey;
    if (ebsCounterNo != null && ebsCounterNo.trim().isNotEmpty) _ebsCounterNo = ebsCounterNo.trim();
    if (isLicensed != null) _isLicensed = isLicensed;
    if (licenseStatus != null) _licenseStatus = licenseStatus;
    if (isLocked != null) _isLocked = isLocked;

    final prefs = await SharedPreferences.getInstance();
    if (cleanUuid.isNotEmpty) {
      await prefs.setString('device_assigned_uuid', cleanUuid);
    } else {
      await prefs.remove('device_assigned_uuid');
    }
    await prefs.setString('device_assigned_name', cleanName);
    if (_hardwareIdentifier.isNotEmpty) {
      await prefs.setString('device_hardware_identifier', _hardwareIdentifier);
    }
    if (siteCode != null) await prefs.setString('device_assigned_site', siteCode);
    if (warehouseCode != null) await prefs.setString('device_assigned_warehouse', warehouseCode);
    if (locationCode != null) await prefs.setString('device_assigned_location', locationCode);
    if (hepProfileId != null) await prefs.setString('device_hep_profile_id', hepProfileId);
    if (hepApiKey != null) await prefs.setString('device_hep_api_key', hepApiKey);
    if (ebsCounterNo != null && ebsCounterNo.trim().isNotEmpty) await prefs.setString('device_ebs_counter_no', ebsCounterNo.trim());
    if (isLicensed != null) await prefs.setBool('device_is_licensed', isLicensed);
    if (licenseStatus != null) await prefs.setString('device_license_status', licenseStatus);
    if (isLocked != null) await prefs.setBool('device_is_locked', isLocked);
  }

  Future<void> setAssignedLocation({
    required String siteCode,
    String? warehouseCode,
    required String locationCode,
  }) async {
    _assignedSite = siteCode;
    _assignedWarehouse = warehouseCode;
    _assignedLocation = locationCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_assigned_site', siteCode);
    if (warehouseCode != null) {
      await prefs.setString('device_assigned_warehouse', warehouseCode);
    }
    await prefs.setString('device_assigned_location', locationCode);
  }

  Future<void> setLicenseStatus({required bool isLicensed, required String status}) async {
    _isLicensed = isLicensed;
    _licenseStatus = status;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('device_is_licensed', isLicensed);
    await prefs.setString('device_license_status', status);
  }

  Future<void> setLockState(bool isLocked) async {
    _isLocked = isLocked;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('device_is_locked', isLocked);
  }

  /// Resolves a concrete operational site code from [preferredSiteCode] or cached
  /// device assignment, treating null/empty/`ALL` as unspecified.
  String resolveEffectiveSiteCode([String? preferredSiteCode]) {
    final cleanPreferred = (preferredSiteCode ?? '').trim().toUpperCase();
    if (cleanPreferred.isNotEmpty && cleanPreferred != 'ALL') {
      return cleanPreferred;
    }
    final cleanAssigned = (_assignedSite ?? '').trim().toUpperCase();
    if (cleanAssigned.isNotEmpty && cleanAssigned != 'ALL') {
      return cleanAssigned;
    }
    return '';
  }
}
