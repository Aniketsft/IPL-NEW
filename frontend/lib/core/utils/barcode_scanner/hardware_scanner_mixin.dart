import 'dart:async';
import 'package:flutter/material.dart';
import 'hardware_scanner_service.dart';

/// A mixin to add Hardware Scanner support (Sunmi & Zebra) to any StatefulWidget.
/// 
/// It automatically handles stream subscription and cancellation via [HardwareScannerService].
/// Override [onHardwareScan] to handle the scanned barcode data.
mixin HardwareScannerMixin<T extends StatefulWidget> on State<T> {
  StreamSubscription? _scannerSubscription;
  final HardwareScannerService _scannerService = HardwareScannerService();

  @override
  void initState() {
    super.initState();
    _initScanner();
  }

  Future<void> _initScanner() async {
    try {
      await _scannerService.init();
      _scannerSubscription = _scannerService.onScan.listen((data) {
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
          onHardwareScan(data);
        }
      });
    } catch (e) {
      debugPrint('HardwareScannerMixin: Failed to initialize scanner listener: $e');
    }
  }

  /// Override this method to process the scanned barcode data.
  void onHardwareScan(String data);

  @override
  void dispose() {
    _scannerSubscription?.cancel();
    super.dispose();
  }
}
