import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sunmi_scanner/sunmi_scanner.dart';

/// A mixin to add Sunmi Hardware Scanner support to any StatefulWidget.
/// 
/// It automatically handles stream subscription and cancellation.
/// Override [onHardwareScan] to handle the scanned barcode data.
mixin SunmiScannerMixin<T extends StatefulWidget> on State<T> {
  StreamSubscription? _scannerSubscription;

  @override
  void initState() {
    super.initState();
    _initScanner();
  }

  void _initScanner() {
    try {
      _scannerSubscription = SunmiScanner.onBarcodeScanned().listen((event) {
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
          onHardwareScan(event);
        }
      });
    } catch (e) {
      debugPrint('SunmiScannerMixin: Failed to initialize scanner listener: $e');
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
