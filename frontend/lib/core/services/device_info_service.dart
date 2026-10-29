import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceInfoService {
  static final DeviceInfoService _instance = DeviceInfoService._internal();
  factory DeviceInfoService() => _instance;
  DeviceInfoService._internal();

  static DeviceInfoService get instance => _instance;

  String _hardwareModel = 'UnknownDevice';
  String _deviceUuid = '';
  String _deviceName = '';
  String? _assignedLocation;
  String? _assignedWarehouse;
  String? _assignedSite;
  String? _hepProfileId;
  String? _hepApiKey;
  bool _isLicensed = true;
  String _licenseStatus = 'VALID';
  bool _isLocked = true;

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool isValidUuid(String? id) => id != null && _uuidRegex.hasMatch(id.trim());

  String get hardwareModel => _hardwareModel;
  String get deviceInfo => _hardwareModel;
  String get deviceUuid => _deviceUuid;
  String get deviceId => isValidUuid(_deviceUuid) ? _deviceUuid : '';
  String get deviceName => _deviceName.isNotEmpty ? _deviceName : _hardwareModel;
  String? get assignedLocation => _assignedLocation;
  String? get assignedWarehouse => _assignedWarehouse;
  String? get assignedSite => _assignedSite;
  String? get hepProfileId => _hepProfileId;
  String? get hepApiKey => _hepApiKey;
  bool get isLicensed => _isLicensed;
  String get licenseStatus => _licenseStatus;
  bool get isLocked => _isLocked;

  Future<void> init() async {
    try {
      final deviceInfoPlugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        final model = androidInfo.model.trim();
        String configuredName = 'Unknown';
        try {
          const platform = MethodChannel('com.enterprise.auth/device_name');
          final String? result = await platform.invokeMethod('getDeviceName');
          if (result != null && result.isNotEmpty) {
            configuredName = result;
          }
        } catch (e) {
          debugPrint('Failed to get Android configured device name: $e');
        }
        _hardwareModel = '$model ($configuredName)';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        final name = iosInfo.name;
        final model = iosInfo.model;
        _hardwareModel = '$model ($name)';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfoPlugin.windowsInfo;
        _hardwareModel = 'Windows (${windowsInfo.computerName})';
      } else {
        _hardwareModel = 'Platform: ${Platform.operatingSystem}';
      }
      debugPrint('DeviceInfoService: Resolved hardware model: $_hardwareModel');
    } catch (e) {
      debugPrint('DeviceInfoService: Failed to resolve hardware model: $e');
      _hardwareModel = 'Terminal-${Platform.operatingSystem}-${DateTime.now().millisecondsSinceEpoch}';
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUuid = prefs.getString('device_assigned_uuid') ?? '';
      _deviceUuid = isValidUuid(savedUuid) ? savedUuid.toLowerCase() : '';
      _deviceName = prefs.getString('device_assigned_name') ?? '';
      _assignedSite = prefs.getString('device_assigned_site');
      _assignedWarehouse = prefs.getString('device_assigned_warehouse');
      _assignedLocation = prefs.getString('device_assigned_location');
      _hepProfileId = prefs.getString('device_hep_profile_id');
      _hepApiKey = prefs.getString('device_hep_api_key');
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
    String? siteCode,
    String? warehouseCode,
    String? locationCode,
    String? hepProfileId,
    String? hepApiKey,
    bool? isLicensed,
    String? licenseStatus,
    bool? isLocked,
  }) async {
    final cleanUuid = isValidUuid(uuid) ? uuid.toLowerCase() : '';
    _deviceUuid = cleanUuid;
    _deviceName = name;
    if (siteCode != null) _assignedSite = siteCode;
    if (warehouseCode != null) _assignedWarehouse = warehouseCode;
    if (locationCode != null) _assignedLocation = locationCode;
    if (hepProfileId != null) _hepProfileId = hepProfileId;
    if (hepApiKey != null) _hepApiKey = hepApiKey;
    if (isLicensed != null) _isLicensed = isLicensed;
    if (licenseStatus != null) _licenseStatus = licenseStatus;
    if (isLocked != null) _isLocked = isLocked;

    final prefs = await SharedPreferences.getInstance();
    if (cleanUuid.isNotEmpty) {
      await prefs.setString('device_assigned_uuid', cleanUuid);
    } else {
      await prefs.remove('device_assigned_uuid');
    }
    await prefs.setString('device_assigned_name', name);
    if (siteCode != null) await prefs.setString('device_assigned_site', siteCode);
    if (warehouseCode != null) await prefs.setString('device_assigned_warehouse', warehouseCode);
    if (locationCode != null) await prefs.setString('device_assigned_location', locationCode);
    if (hepProfileId != null) await prefs.setString('device_hep_profile_id', hepProfileId);
    if (hepApiKey != null) await prefs.setString('device_hep_api_key', hepApiKey);
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
}
