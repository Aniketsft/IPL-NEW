import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
  }
}
