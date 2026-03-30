import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/utils/barcode_scanner/barcode_scanner_widget.dart';


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
    if (!_scans.any((s) => s['barcode'] == result.barcode)) {
      HapticFeedback.lightImpact();
      setState(() {
        _scans.add({
          'barcode': result.barcode,
          'productName': result.description,
          'weight': result.weight,
        });
      });
    }
  }

  void _addManualOneKg() {
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.product['productName'] ?? 'Product Details',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context, _scans),
        ),
      ),
      body: Column(
        children: [
          // Summary Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TOTAL WEIGHT',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      '${_totalWeight.toStringAsFixed(2)} KG',
                      style: const TextStyle(
                        color: Color(0xFFFF9800),
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'COUNT',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      '${_scans.length} Items',
                      style: const TextStyle(
                        color: Colors.white,
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
                themeColor: const Color(0xFFFF9800),
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
                          : const Color(0xFFFF9800),
                      foregroundColor: Colors.black,
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
                      backgroundColor: Colors.white10,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: Colors.white24),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SCANNED ITEMS',
                style: TextStyle(
                  color: Colors.grey,
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
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.qr_code,
                          color: Color(0xFFFF9800),
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
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const Text(
                              'Standard Entry',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${scan['weight']} KG',
                        style: const TextStyle(
                          color: Color(0xFFFF9800),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Color.fromARGB(255, 255, 0, 0),
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
            decoration: const BoxDecoration(
              color: Color(0xFF121212),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _scans),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
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
