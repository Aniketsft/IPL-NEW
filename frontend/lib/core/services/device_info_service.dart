import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class DeviceInfoService {
  static final DeviceInfoService _instance = DeviceInfoService._internal();
  factory DeviceInfoService() => _instance;
  DeviceInfoService._internal();

  static DeviceInfoService get instance => _instance;

  String _deviceInfo = 'UnknownDevice';

  String get deviceInfo => _deviceInfo;

  Future<void> init() async {
    try {
      final deviceInfoPlugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        final brand  = androidInfo.brand.trim();
        final model  = androidInfo.model.trim();
        // Prefer hardware serial number (unique per device, auto-granted on
        // MDM-enrolled Zebra terminals). Falls back to androidInfo.id if the
        // serial is unavailable or reported as 'unknown'.
        final serial = androidInfo.serialNumber.trim();
        final identifier = (serial.isNotEmpty && serial.toLowerCase() != 'unknown')
            ? 'SN: $serial'
            : 'ID: ${androidInfo.id}';
        _deviceInfo = '$brand $model ($identifier)';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        final name   = iosInfo.name;
        final model  = iosInfo.model;
        final id     = iosInfo.identifierForVendor ?? 'unknown-ios';
        _deviceInfo  = 'Apple $model ($name, ID: $id)';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfoPlugin.windowsInfo;
        _deviceInfo = 'Windows: ${windowsInfo.computerName}';
      } else {
        _deviceInfo = 'Platform: ${Platform.operatingSystem}';
      }
      debugPrint('DeviceInfoService: Resolved device info: $_deviceInfo');
    } catch (e) {
      debugPrint('DeviceInfoService: Failed to resolve device info: $e');
      _deviceInfo = 'Terminal-${Platform.operatingSystem}-${DateTime.now().millisecondsSinceEpoch}';
    }
  }
}
