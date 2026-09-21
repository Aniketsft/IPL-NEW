import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_datawedge/flutter_datawedge.dart';
import 'package:sunmi_scanner/sunmi_scanner.dart';

enum ScannerType { sunmi, zebra, qunsuo, unknown }

class HardwareScannerService {
  static final HardwareScannerService _instance = HardwareScannerService._internal();
  factory HardwareScannerService() => _instance;
  HardwareScannerService._internal();

  final _scannedDataController = StreamController<String>.broadcast();
  Stream<String> get onScan => _scannedDataController.stream;

  ScannerType _type = ScannerType.unknown;
  ScannerType get type => _type;

  String _detectedManufacturer = 'Unknown';
  String get detectedManufacturer => _detectedManufacturer;

  String _detectedModel = 'Unknown';
  String get detectedModel => _detectedModel;

  FlutterDataWedge? _zebraScanner;
  StreamSubscription? _sunmiSubscription;
  StreamSubscription? _zebraSubscription;
  StreamSubscription? _qunsuoSubscription;

  static const EventChannel _qunsuoEventChannel =
      EventChannel('com.qunsuo.scanner/stream');

  bool _isInitialized = false;

  // Keystroke buffer for Keyboard Wedge (HID) fallback
  final StringBuffer _keyBuffer = StringBuffer();
  DateTime _lastKeyTime = DateTime.now();

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final manufacturer = androidInfo.manufacturer.toUpperCase();
        final model = androidInfo.model.toUpperCase();

        _detectedManufacturer = androidInfo.manufacturer;
        _detectedModel = androidInfo.model;

        debugPrint('HardwareScannerService: Detected Manufacturer: $manufacturer, Model: $model');

        if (manufacturer.contains('SUNMI')) {
          _type = ScannerType.sunmi;
          _initSunmi();
        } else if (manufacturer.contains('ZEBRA') ||
            manufacturer.contains('MOTOROLA') ||
            manufacturer.contains('SYMBOL')) {
          _type = ScannerType.zebra;
          await _initZebra();
        } else {
          // Default Android OEM scanner (Qunsuo PDA602, Tablet QS-1003, Alps, etc.)
          _type = ScannerType.qunsuo;
          debugPrint('HardwareScannerService: Initialized Qunsuo broadcast scanner for $manufacturer $model');
          _initQunsuo();
        }
      } else {
        _type = ScannerType.unknown;
        debugPrint('HardwareScannerService: Non-Android platform (${Platform.operatingSystem})');
      }

      // Attach global Keyboard Wedge (HID) handler as an additional fallback
      _initKeyboardWedgeFallback();

      _isInitialized = true;
    } catch (e) {
      debugPrint('HardwareScannerService: Failed to initialize: $e');
    }
  }

  void _initSunmi() {
    try {
      _sunmiSubscription = SunmiScanner.onBarcodeScanned().listen((barcode) {
        final cleaned = barcode.trim();
        if (cleaned.isNotEmpty) {
          _scannedDataController.add(cleaned);
        }
      });
      debugPrint('HardwareScannerService: Sunmi scanner initialized');
    } catch (e) {
      debugPrint('HardwareScannerService: Failed to init Sunmi scanner: $e');
    }
  }

  Future<void> _initZebra() async {
    try {
      _zebraScanner = FlutterDataWedge();
      await _zebraScanner!.initialize();

      _zebraSubscription = _zebraScanner!.onScanResult.listen((result) {
        debugPrint('HardwareScannerService: Raw Zebra Scan - Data: "${result.data}", Type: "${result.labelType}"');
        final cleaned = result.data.trim();
        if (cleaned.isNotEmpty) {
          _scannedDataController.add(cleaned);
        }
      });

      debugPrint('HardwareScannerService: Zebra DataWedge initialized and listening');
    } catch (e) {
      debugPrint('HardwareScannerService: Failed to init Zebra scanner: $e');
    }
  }

  void _initQunsuo() {
    try {
      _qunsuoSubscription = _qunsuoEventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          final barcode = event?.toString().trim() ?? '';
          debugPrint('HardwareScannerService: Received Qunsuo Scan: "$barcode"');
          if (barcode.isNotEmpty) {
            _scannedDataController.add(barcode);
          }
        },
        onError: (dynamic error) {
          debugPrint('HardwareScannerService: Qunsuo EventChannel error: $error');
        },
      );
      debugPrint('HardwareScannerService: Qunsuo scanner initialized on channel "com.qunsuo.scanner/stream"');
    } catch (e) {
      debugPrint('HardwareScannerService: Failed to init Qunsuo scanner: $e');
    }
  }

  /// Global Keystroke buffer fallback.
  /// If the physical device is configured in Keyboard Wedge mode (simulated typing)
  /// rather than Broadcast Intent, this captures rapid key sequences ending in Enter.
  void _initKeyboardWedgeFallback() {
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();
    final elapsed = now.difference(_lastKeyTime).inMilliseconds;
    _lastKeyTime = now;

    // Scanners type very quickly (< 50ms between keys)
    if (elapsed > 100) {
      _keyBuffer.clear();
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final scannedText = _keyBuffer.toString().trim();
      _keyBuffer.clear();

      if (scannedText.length >= 3) {
        debugPrint('HardwareScannerService: Captured Keyboard Wedge Scan: "$scannedText"');
        _scannedDataController.add(scannedText);
      }
      return false;
    }

    final char = event.character;
    if (char != null && char.isNotEmpty && char.codeUnitAt(0) >= 32) {
      _keyBuffer.write(char);
    }

    return false;
  }

  /// Allows manual injection of simulated barcode scans (useful for testing and diagnostics)
  void simulateScan(String barcode) {
    final cleaned = barcode.trim();
    if (cleaned.isNotEmpty) {
      _scannedDataController.add(cleaned);
    }
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _sunmiSubscription?.cancel();
    _zebraSubscription?.cancel();
    _qunsuoSubscription?.cancel();
    _scannedDataController.close();
    _isInitialized = false;
  }
}
