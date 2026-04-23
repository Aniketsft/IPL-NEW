import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'offline_barcode_processor.dart';
export 'offline_barcode_processor.dart' show ScanResult;

class AppBarcodeScanner extends StatefulWidget {
  final Function(ScanResult)? onScanSuccess;
  final Function(String)? onScan;
  final Function(String)? onUnknownBarcode;
  final Function(double)? onManualAdd;
  final Map<String, double>? manualEntries;
  final double height;
  final Color themeColor;
  /// If true, the camera starts immediately on mount and the internal
  /// START/STOP toggle row is hidden (parent widget controls open/close).
  final bool autoStart;

  const AppBarcodeScanner({
    super.key,
    this.onScanSuccess,
    this.onScan,
    this.onUnknownBarcode,
    this.onManualAdd,
    this.manualEntries,
    this.height = 200.0,
    this.themeColor = const Color(0xFFFF9800),
    this.autoStart = false,
  });

  @override
  State<AppBarcodeScanner> createState() => _AppBarcodeScannerState();
}

class _AppBarcodeScannerState extends State<AppBarcodeScanner> {
  MobileScannerController? _scannerController;
  bool _isScannerVisible = false;
  final OfflineBarcodeProcessor _processor = OfflineBarcodeProcessor();

  // Set to avoid processing barcodes too frequently
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      // Start camera immediately without waiting for user to tap START SCAN
      WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
    }
  }

  Future<void> _startCamera() async {
    final status = await Permission.camera.request();
    if (status.isGranted && mounted) {
      setState(() {
        _isScannerVisible = true;
        _scannerController?.dispose();
        _scannerController = MobileScannerController(
          formats: [
            BarcodeFormat.ean13,
            BarcodeFormat.code128,
            BarcodeFormat.qrCode,
          ],
        );
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera permission is required to scan'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _toggleScanner() async {
    if (!_isScannerVisible) {
      final status = await Permission.camera.request();
      if (status.isGranted) {
        setState(() {
          _isScannerVisible = true;
          _scannerController?.dispose();
          _scannerController = MobileScannerController(
            formats: [
              BarcodeFormat.ean13,
              BarcodeFormat.code128,
              BarcodeFormat.qrCode,
            ],
          );
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera permission is required to scan'),
            ),
          );
        }
      }
    } else {
      setState(() {
        _isScannerVisible = false;
        _scannerController?.dispose();
        _scannerController = null;
      });
    }
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;

    for (final barcode in barcodes) {
      final String? code = barcode.rawValue;
      if (code != null && code.isNotEmpty) {
        // Pause between any two scans to avoid continuous/accidental fires
        // Configured to 5 seconds per user request
        if (_lastScanTime != null) {
          if (DateTime.now().difference(_lastScanTime!).inSeconds < 2) {
            continue;
          }
        }

        _lastScanTime = DateTime.now();

        if (widget.onScan != null) {
          widget.onScan!(code);
        }

        if (widget.onScanSuccess != null || widget.onUnknownBarcode != null) {
          final result = await _processor.processBarcode(code);
          if (mounted) {
            if (result != null) {
              widget.onScanSuccess?.call(result);
            } else {
              if (widget.onUnknownBarcode != null) {
                widget.onUnknownBarcode!(code);
              }
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isScannerVisible && _scannerController != null)
          Container(
            height: widget.height,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.themeColor.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14.5),
              child: MobileScanner(
                controller: _scannerController!,
                onDetect: _handleScan,
              ),
            ),
          ),
        // Only show internal START/STOP row when NOT in autoStart mode
        if (!widget.autoStart)
        Row(
          children: [
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                onPressed: _toggleScanner,
                icon: Icon(
                  _isScannerVisible
                      ? Icons.power_settings_new
                      : Icons.qr_code_scanner,
                ),
                label: Text(_isScannerVisible ? 'STOP SCAN' : 'START SCAN'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isScannerVisible
                      ? Colors.red.withValues(alpha: 0.2)
                      : widget.themeColor,
                  foregroundColor: _isScannerVisible
                      ? Colors.red
                      : Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: _isScannerVisible
                        ? const BorderSide(color: Colors.red)
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
            if (widget.manualEntries != null && widget.onManualAdd != null) ...[
              const SizedBox(width: 8),
              ...widget.manualEntries!.entries
                  .map(
                    (entry) => Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () => widget.onManualAdd!(entry.value),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                        ),
                        child: Text(
                          entry.key.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ],
          ],
        ),
      ],
    );
  }
}
