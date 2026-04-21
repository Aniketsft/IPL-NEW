import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/utils/barcode_scanner/barcode_scanner_widget.dart';
import '../../../../core/utils/audio/audio_service.dart';


class ProductScanDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> initialScans;

  const ProductScanDetailScreen({
    super.key,
    required this.product,
    required this.initialScans,
  });

  @override
  State<ProductScanDetailScreen> createState() =>
      _ProductScanDetailScreenState();
}

class _ProductScanDetailScreenState extends State<ProductScanDetailScreen> {
  late List<Map<String, dynamic>> _scans;
  // Removed MobileScannerController
  bool _isScannerVisible = false;
  bool _isProcessingScan = false;

  @override
  void initState() {
    super.initState();
    _scans = List.from(widget.initialScans);
  }

  @override
  void dispose() {
    // _scannerController?.dispose(); // No longer needed
    super.dispose();
  }

  double get _totalWeight {
    return _scans.fold(
      0.0,
      (sum, item) => sum + (double.tryParse(item['weight'].toString()) ?? 0.0),
    );
  }

  Future<void> _toggleScanner() async {
    setState(() {
      _isScannerVisible = !_isScannerVisible;
    });
  }

  void _onScanSuccess(ScanResult result) {
    if (_isProcessingScan) return;
    _isProcessingScan = true;

    try {
      HapticFeedback.lightImpact();
      setState(() {
        _scans.add({
          'barcode': result.barcode,
          'productName': result.description,
          'weight': result.weight,
        });
      });
      AudioService.instance.playSuccess(); // VALID SCAN - Synchronized with appearance in list
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingScan = false;
        });
      }
    }
  }

  void _addManualOneKg() {
    // AudioService.instance.playSuccess(); // Removed to only trigger on 'detected' scans
    setState(() {
      _scans.add({
        'barcode': 'MANUAL-${DateTime.now().millisecondsSinceEpoch}',
        'productName': widget.product['productName'],
        'weight': 1.0,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orange = theme.primaryColor;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.product['productName'] ?? 'Product Details',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87),
          onPressed: () => Navigator.pop(context, _scans),
        ),
      ),
      body: Column(
        children: [
          // Summary Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL WEIGHT',
                      style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 12),
                    ),
                    Text(
                      '${_totalWeight.toStringAsFixed(2)} KG',
                      style: TextStyle(
                        color: orange,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'COUNT',
                      style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 12),
                    ),
                    Text(
                      '${_scans.length} Items',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Scanner Section
          if (_isScannerVisible)
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppBarcodeScanner(
                onScanSuccess: _onScanSuccess,
                onUnknownBarcode: (code) {
                  AudioService.instance.playError();
                  HapticFeedback.heavyImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Unknown barcode or invalid format'),
                      backgroundColor: Colors.red,
                    ),
                  );
                },
                onManualAdd: (weight) {
                  setState(() {
                    _scans.add({
                      'barcode': 'MANUAL-${DateTime.now().millisecondsSinceEpoch}',
                      'productName': widget.product['productName'],
                      'weight': weight,
                    });
                  });
                },
                manualEntries: const {'1KG': 1.0},
                themeColor: orange,
              ),
            ),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _toggleScanner,
                    icon: Icon(
                      _isScannerVisible ? Icons.close : Icons.qr_code_scanner,
                    ),
                    label: Text(
                      _isScannerVisible ? 'CLOSE SCANNER' : 'OPEN SCANNER',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isScannerVisible
                          ? Colors.red
                          : orange,
                      foregroundColor: _isScannerVisible ? Colors.white : Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _addManualOneKg,
                    icon: const Icon(Icons.add),
                    label: const Text('SCAN 1KG'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                      foregroundColor: isDark ? Colors.white : Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SCANNED ITEMS',
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),

          // List of items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _scans.length,
              itemBuilder: (context, index) {
                final scan = _scans[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          Icons.qr_code,
                          color: orange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              scan['barcode'] ?? 'N/A',
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Standard Entry',
                              style: TextStyle(
                                color: isDark ? Colors.white38 : Colors.black38,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${scan['weight']} KG',
                        style: TextStyle(
                          color: orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _scans.removeAt(index);
                          });
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Bottom Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _scans),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'CONFIRM AND RETURN',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
