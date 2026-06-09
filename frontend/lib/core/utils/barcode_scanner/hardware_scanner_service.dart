import 'dart:async';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_datawedge/flutter_datawedge.dart';
import 'package:sunmi_scanner/sunmi_scanner.dart';

enum ScannerType { sunmi, zebra, unknown }

class HardwareScannerService {
  static final HardwareScannerService _instance = HardwareScannerService._internal();
  factory HardwareScannerService() => _instance;
  HardwareScannerService._internal();

  final _scannedDataController = StreamController<String>.broadcast();
  Stream<String> get onScan => _scannedDataController.stream;

  ScannerType _type = ScannerType.unknown;
  FlutterDataWedge? _zebraScanner;
  StreamSubscription? _sunmiSubscription;
  StreamSubscription? _zebraSubscription;

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final manufacturer = androidInfo.manufacturer.toUpperCase();

      debugPrint('HardwareScannerService: Detected manufacturer: $manufacturer');

      if (manufacturer.contains('SUNMI')) {
        _type = ScannerType.sunmi;
        _initSunmi();
      } else if (manufacturer.contains('ZEBRA') || 
                 manufacturer.contains('MOTOROLA') || 
                 manufacturer.contains('SYMBOL')) {
        _type = ScannerType.zebra;
        await _initZebra();
      } else {
        _type = ScannerType.unknown;
        debugPrint('HardwareScannerService: Unsupported hardware scanner for $manufacturer');
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('HardwareScannerService: Failed to initialize: $e');
    }
  }

  void _initSunmi() {
    try {
      _sunmiSubscription = SunmiScanner.onBarcodeScanned().listen((barcode) {
        _scannedDataController.add(barcode);
      });
      debugPrint('HardwareScannerService: Sunmi scanner initialized');
    } catch (e) {
      debugPrint('HardwareScannerService: Failed to init Sunmi scanner: $e');
    }
  }

  Future<void> _initZebra() async {
    try {
      _zebraScanner = FlutterDataWedge();
      
      // Initialize Zebra DataWedge profile
      // This will attempt to create or use a profile named 'FlutterDataWedge'
      await _zebraScanner!.initialize();
      
      _zebraSubscription = _zebraScanner!.onScanResult.listen((result) {
        debugPrint('HardwareScannerService: Raw Zebra Scan - Data: "${result.data}", Type: "${result.labelType}"');
        if (result.data.isNotEmpty) {
          _scannedDataController.add(result.data);
        }
      });

      debugPrint('HardwareScannerService: Zebra DataWedge initialized and listening');
    } catch (e) {
      debugPrint('HardwareScannerService: Failed to init Zebra scanner: $e');
    }
  }

  void dispose() {
    _sunmiSubscription?.cancel();
    _zebraSubscription?.cancel();
    _scannedDataController.close();
    _isInitialized = false;
  }
}
