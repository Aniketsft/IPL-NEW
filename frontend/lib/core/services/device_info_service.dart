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

  String _deviceInfo = 'UnknownDevice';
  String _macAddress = '';
  String? _assignedLocation;
  String? _assignedWarehouse;
  String? _assignedSite;

  String get deviceInfo => _deviceInfo;
  String get deviceId => _deviceInfo;
  String get macAddress => _macAddress;
  String? get assignedLocation => _assignedLocation;
  String? get assignedWarehouse => _assignedWarehouse;
  String? get assignedSite => _assignedSite;

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
        _deviceInfo = '$model ($configuredName)';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        final name   = iosInfo.name;
        final model  = iosInfo.model;
        _deviceInfo  = '$model ($name)';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfoPlugin.windowsInfo;
        _deviceInfo = 'Windows (${windowsInfo.computerName})';
      } else {
        _deviceInfo = 'Platform: ${Platform.operatingSystem}';
      }
      debugPrint('DeviceInfoService: Resolved device info: $_deviceInfo');
    } catch (e) {
      debugPrint('DeviceInfoService: Failed to resolve device info: $e');
      _deviceInfo = 'Terminal-${Platform.operatingSystem}-${DateTime.now().millisecondsSinceEpoch}';
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _macAddress = prefs.getString('device_mac_address') ?? '';
      _assignedSite = prefs.getString('device_assigned_site');
      _assignedWarehouse = prefs.getString('device_assigned_warehouse');
      _assignedLocation = prefs.getString('device_assigned_location');
    } catch (e) {
      debugPrint('DeviceInfoService: Failed to load cached location/mac: $e');
    }
  }

  Future<void> setMacAddress(String mac) async {
    _macAddress = mac;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_mac_address', mac);
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
}
